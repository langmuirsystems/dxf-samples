<#
.SYNOPSIS
    Reads a text file and extracts all text before the "=" symbol on each line.
.DESCRIPTION
    This script reads a text file line by line, splits each line at the first "=" character,
    and outputs the part before the "=" as a list.
.PARAMETER FilePath
    The path to the text file to process.
.EXAMPLE
    .\ExtractBeforeEquals.ps1 -FilePath "C:\files\config.txt"
#>

param (
    [Parameter(Mandatory=$true, HelpMessage="Path to the input text file")]
    [string]$FilePath
)

# Check if file exists
if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
    Write-Error "File not found: $FilePath"
    exit 1
}

try {
    # Read file and process each line
    $results = Get-Content -Path $FilePath | ForEach-Object {
        if ($_ -match '=') {
            # Split at first "=" and take the part before it
            $_.Split('=', 2)[0].Trim()
        }
    }

    # Output the results as a list
    $results
}
catch {
    Write-Error "An error occurred while processing the file: $_"
    exit 1
}