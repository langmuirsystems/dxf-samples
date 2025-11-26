#Requires -Version 7.0

<#
.SYNOPSIS
    Generates a Markdown file with an image gallery from GitHub repository folders.

.DESCRIPTION
    Connects to a GitHub repository using an access token.
    Scans specified folders for PNG files and generates a Markdown file
    containing an HTML table with images (2 per row).
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
    [string]$OutputFile = "README.md"
)

begin {
    # GitHub API configuration
    $ApiBaseUrl = "https://api.github.com/repos/$Owner/$Repo/contents"
    $headers = @{
        "Authorization" = "Bearer $GitHubToken"
        "Accept"        = "application/vnd.github.v3+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    
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
        
        # --- 1. Get main folder contents ---
        $uri = if ([string]::IsNullOrEmpty($Path)) {
            $ApiBaseUrl
        } else {
            "$ApiBaseUrl/$Path"
        }
        
        Write-Host "🔍 Scanning folder '$Path' for subfolders..."
        $mainFolderContents = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        
        # --- 2. Filter and process subfolders ---
        $subfolders = $mainFolderContents | Where-Object { $_.type -eq 'dir' }
        
        if (-not $subfolders) {
            Write-Warning "No subfolders found in '$Path'. Exiting."
            return
        }
        
        Write-Host "✅ Found $($subfolders.Count) subfolders. Processing each..."
        
        # --- 3. Collect image information ---
        foreach ($folder in $subfolders) {
            $processedFolders++
            Write-Host "  - Processing folder: $($folder.name)"
            
            try {
                $subfolderContents = Invoke-RestMethod -Uri $folder.url -Headers $headers -Method Get
                $pngFile = $subfolderContents | Where-Object { $_.Name -like '*.png' } | Select-Object -First 1
                
                if ($pngFile) {
                    $foundImages++
                    $imageData.Add([pscustomobject]@{
                        Name = [System.IO.Path]::GetFileNameWithoutExtension($pngFile.name)
                        Url  = $pngFile.download_url
                        Folder = $folder.name
                    })
                    Write-Host "    ✨ Found PNG file: $($pngFile.name)"
                } else {
                    $missingImages++
                    Write-Warning "    ⚠️ No PNG file found in $($folder.name)"
                }
            }
            catch {
                Write-Warning "    ⚠️ Error processing $($folder.name): $($_.Exception.Message)"
                continue
            }
        }
        
        # --- 4. Check for valid data ---
        if ($imageData.Count -eq 0) {
            Write-Host "No images found for gallery creation. Exiting."
            return
        }
        
        # --- 5. Generate Markdown file ---
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
        <img src="$($image.Url)" alt="$($image.Name)" style="max-height:400px; max-width:100%; object-fit:contain">
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