#Requires -Version 7.0

<#
.SYNOPSIS
    Generates a Markdown file with an image gallery from GitHub repository folders.

.DESCRIPTION
    Connects to a GitHub repository using an access token.
    Scans specified folders for PNG files and generates a Markdown file
    containing an HTML table with images (2 per row).
    Images include a tooltip (title attribute) with: example name from dxf-files.properties,
    DXF file size in MB, and optional description from a description file in the folder.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$GitHubToken = $env:GITHUB_TOKEN,

    [Parameter(Mandatory = $false)]
    [string]$Owner = $env:GITHUB_REPOSITORY_OWNER,

    [Parameter(Mandatory = $false)]
    [string]$Repo = $env:GITHUB_REPOSITORY.Split('/')[-1],

    [Parameter(Mandatory = $false)]
    [string]$Path = "samples",

    [Parameter(Mandatory = $false)]
    [string]$PropertiesFile = "samples/dxf-files.properties",

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "README.md"
)

begin {
    # Initialize image data collection
    $imageData = [System.Collections.Generic.List[object]]::new()
    
    # Statistics counters
    $processedFolders = 0
    $foundImages = 0
    $missingImages = 0
}

process {
    try {
        Write-Host "🚀 Starting gallery generation..."

        # --- 0. Load dxf-files.properties into a lookup table ---
        $propertiesLookup = @{}
        if (Test-Path $PropertiesFile) {
            Write-Host "📄 Loading properties from '$PropertiesFile'..."
            Get-Content $PropertiesFile | ForEach-Object {
                $line = $_.Trim()
                if ($line -and $line -notmatch '^\s*#') {
                    $eqIndex = $line.IndexOf('=')
                    if ($eqIndex -gt 0) {
                        $key   = $line.Substring(0, $eqIndex).Trim()
                        $value = $line.Substring($eqIndex + 1).Trim()
                        $propertiesLookup[$key] = $value
                    }
                }
            }
            Write-Host "✅ Loaded $($propertiesLookup.Count) entries from properties file."
        } else {
            Write-Warning "⚠️ Properties file '$PropertiesFile' not found. Tooltips will lack example names."
        }

        # --- 1. Scan local filesystem for subfolders ---
        Write-Host "🔍 Scanning local folder '$Path' for subfolders..."
        $subfolders = Get-ChildItem -Path $Path -Directory | Sort-Object Name

        if (-not $subfolders) {
            Write-Warning "No subfolders found in '$Path'. Exiting."
            return
        }

        Write-Host "✅ Found $($subfolders.Count) subfolders. Processing each..."

        # --- 2. Collect image information ---
        foreach ($folder in $subfolders) {
            $processedFolders++
            Write-Host "  - Processing folder: $($folder.Name)"

            try {
                $pngFile = Get-ChildItem -Path $folder.FullName -Filter '*.png' | Select-Object -First 1

                if ($pngFile) {
                    $foundImages++
                    # Build the raw GitHub URL from the local relative path
                    $relativePath = ($pngFile.FullName.Replace('\', '/') -replace [regex]::Escape((Get-Location).Path.Replace('\', '/') + '/'), '')
                    # URL-encode spaces and special characters in the path
                    $encodedPath = $relativePath -replace ' ', '%20'
                    $rawUrl = "https://raw.githubusercontent.com/$Owner/$Repo/master/$encodedPath"

                    # --- Tooltip: example name from properties ---
                    $exampleName = $null
                    if ($propertiesLookup.ContainsKey($folder.Name)) {
                        $exampleName = $folder.Name
                    }

                    # --- Tooltip: DXF file size ---
                    $dxfFile = Get-ChildItem -Path $folder.FullName | Where-Object { $_.Extension -iin @('.dxf', '.DXF') } | Select-Object -First 1
                    $dxfSizeMb = $null
                    if ($dxfFile) {
                        $dxfSizeMb = [math]::Round($dxfFile.Length / 1MB, 3)
                    }

                    # --- Tooltip: optional description file ---
                    # Must contain the word 'description' in the filename (case-insensitive)
                    # and have extension .md, .txt, or no extension
                    $descriptionContent = $null
                    $descFile = Get-ChildItem -Path $folder.FullName | Where-Object {
                        $_.BaseName -imatch 'description' -and
                        ($_.Extension -iin @('.md', '.txt') -or $_.Extension -eq '')
                    } | Select-Object -First 1
                    if ($descFile) {
                        $descriptionContent = (Get-Content $descFile.FullName -Raw).Trim()
                    }

                    # --- Build tooltip string ---
                    $tooltipLines = [System.Collections.Generic.List[string]]::new()
                    if ($exampleName) {
                        $tooltipLines.Add("Example: $exampleName")
                    }
                    if ($null -ne $dxfSizeMb) {
                        $tooltipLines.Add("Size: $($dxfSizeMb) MB")
                    }
                    if ($descriptionContent) {
                        $tooltipLines.Add("Description: $descriptionContent")
                    }
                    $tooltip = $tooltipLines -join "&#10;"

                    $imageData.Add([pscustomobject]@{
                        Name    = [System.IO.Path]::GetFileNameWithoutExtension($pngFile.Name)
                        Url     = $rawUrl
                        Folder  = $folder.Name
                        Tooltip = $tooltip
                    })
                    Write-Host "    ✨ Found PNG file: $($pngFile.Name)"
                } else {
                    $missingImages++
                    Write-Warning "    ⚠️ No PNG file found in $($folder.Name)"
                }
            }
            catch {
                Write-Warning "    ⚠️ Error processing $($folder.Name): $($_.Exception.Message)"
                continue
            }
        }
        
        # --- 3. Check for valid data ---
        if ($imageData.Count -eq 0) {
            Write-Host "No images found for gallery creation. Exiting."
            return
        }
        
        # --- 4. Generate Markdown file ---
        Write-Host "🖼️ Generating Markdown file with $($imageData.Count) images..."
        
        $markdownLines = [System.Collections.Generic.List[string]]::new()
        $markdownLines.Add("")
        $markdownLines.Add("<table>")
        
        # Group images 2 per row
        for ($i = 0; $i -lt $imageData.Count; $i += 2) {
            $markdownLines.Add("<tr>")
            
            for ($j = 0; $j -lt 2; $j++) {
                if ($i + $j -lt $imageData.Count) {
                    $image = $imageData[$i + $j]
                    $markdownLines.Add(@"
    <td align="center" valign="bottom" style="width:50%">
      <div style="height:400px; display:flex; align-items:center; justify-content:center">
        <img src="$($image.Url)" alt="$($image.Name)" title="$($image.Tooltip)" style="max-height:400px; max-width:100%; object-fit:contain">
      </div>
      <br>
      <b>$($image.Name)</b><br>
      <small>($($image.Folder))</small>
    </td>
"@)
                } else {
                    # Empty cell for alignment
                    $markdownLines.Add('    <td></td>')
                }
            }
            
            $markdownLines.Add("</tr>")
        }
        
        $markdownLines.Add("</table>")
        $markdownLines.Add("")
        $markdownLines.Add("> *Total folders processed: $processedFolders*")
        $markdownLines.Add("> *Images found: $foundImages*")
        $markdownLines.Add("> *Folders without images: $missingImages*")
        
        # --- 6. Save file ---
        try {
            Set-Content -Path $OutputFile -Value ($markdownLines -join "`n") -Encoding UTF8 -NoNewline
            Write-Host "✅ Success! Gallery saved to: $OutputFile"
            Write-Host "📊 Statistics:"
            Write-Host "   - Folders processed: $processedFolders"
            Write-Host "   - Images found: $foundImages"
            Write-Host "   - Empty folders: $missingImages"
        }
        catch {
            Write-Error "❌ Failed to save file $OutputFile."
            Write-Error $_.Exception.Message
        }
    }
    catch {
        Write-Error "❌ GitHub API Error: $($_.Exception.Message)"
        exit 1
    }
}

end {
    # Clean up token from memory
    Remove-Variable -Name GitHubToken -ErrorAction SilentlyContinue
    [GC]::Collect()
}