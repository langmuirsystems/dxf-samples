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
    [string]$OutputFile = "samples/dxf-files.properties"
)

# GitHub API configuration
$ApiBaseUrl = "https://api.github.com/repos/$Owner/$Repo/contents"
$headers = @{
    "Authorization" = "Bearer $GitHubToken"
    "Accept"        = "application/vnd.github.v3+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$properties = [System.Collections.Generic.List[string]]::new()

try {
    Write-Host "🚀 Starting properties file generation..."
    
    # 1. Get all subfolders in the specified path
    $uri = "$ApiBaseUrl/$Path"
    $mainFolderContents = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    $subfolders = $mainFolderContents | Where-Object { $_.type -eq 'dir' }
    
    if (-not $subfolders) {
        Write-Warning "No subfolders found in '$Path'. Exiting."
        return
    }

    Write-Host "✅ Found $($subfolders.Count) subfolders. Processing each..."

    # 2. Process each subfolder
    foreach ($folder in $subfolders) {
        Write-Host "  - Processing folder: $($folder.name)"
        $subfolderContents = Invoke-RestMethod -Uri $folder.url -Headers $headers -Method Get
        
        # Find DXF file in the subfolder
        $dxfFile = $subfolderContents | Where-Object { $_.Name -like '*.dxf' } | Select-Object -First 1
        
        if (-not $dxfFile) {
            Write-Warning "    ⚠️ No DXF file found in $($folder.name). Skipping."
            continue
        }
        
        # Determine the unit (IN or MM)
        $unitFile = $subfolderContents | Where-Object { $_.Name -like 'IN*' -or $_.Name -like 'MM*' } | Select-Object -First 1
        $unit = if ($unitFile) {
            Write-Host "    ✨ Found unit file: $($unitFile.Name)"
            $unitFile.Name.Substring(0, 2).ToUpper()
        } else {
            Write-Host "    ⚠️ No unit file found, defaulting to 'MM'."
            'MM'
        }

        # Key is the folder name, URL is the raw download URL
        $key = $folder.name
        $url = $dxfFile.download_url

        $properties.Add("$key=$url,$unit")
    }

    # 3. Save the properties file
    Set-Content -Path $OutputFile -Value ($properties -join "`n") -Encoding UTF8 -NoNewline
    Write-Host "✅ Success! Properties file saved to: $OutputFile"

} catch {
    Write-Error "❌ GitHub API Error: $($_.Exception.Message)"
    exit 1
}