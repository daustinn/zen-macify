[CmdletBinding()]
param(
    [string]$ProfilePath
)

$ErrorActionPreference = "Stop"

function Get-ZenProfilePath {
    param([string]$CustomPath)

    if ($CustomPath -and (Test-Path $CustomPath)) {
        return (Resolve-Path $CustomPath).Path
    }

    $zenDir = Join-Path $env:APPDATA "zen"
    if (-not (Test-Path $zenDir)) {
        throw "Zen Browser directory not found at: $zenDir"
    }

    $profilesIni = Join-Path $zenDir "profiles.ini"
    if (Test-Path $profilesIni) {
        $lines = Get-Content $profilesIni

        # 1. Check [Install...] section Default=Profiles/...
        $installDefault = $lines | Where-Object { $_ -match '^Default=(Profiles/.+)$' } | ForEach-Object { $matches[1] } | Select-Object -First 1
        if ($installDefault) {
            $candidate = Join-Path $zenDir ($installDefault -replace '/', '\')
            if (Test-Path $candidate) {
                return $candidate
            }
        }

        # 2. Check [Profile...] with Default=1
        $currentPath = $null
        $isDefault = $false
        foreach ($line in $lines) {
            if ($line -match '^\[Profile') {
                if ($isDefault -and $currentPath) {
                    $candidate = Join-Path $zenDir ($currentPath -replace '/', '\')
                    if (Test-Path $candidate) { return $candidate }
                }
                $currentPath = $null
                $isDefault = $false
            }
            if ($line -match '^Path=(.+)$') {
                $currentPath = $matches[1]
            }
            if ($line -match '^Default=1') {
                $isDefault = $true
            }
        }
        if ($isDefault -and $currentPath) {
            $candidate = Join-Path $zenDir ($currentPath -replace '/', '\')
            if (Test-Path $candidate) { return $candidate }
        }
    }

    # 3. Fallback: scan Profiles folder
    $profilesDir = Join-Path $zenDir "Profiles"
    if (Test-Path $profilesDir) {
        $dirs = Get-ChildItem -Path $profilesDir -Directory
        $release = $dirs | Where-Object { $_.Name -like "*release*" } | Select-Object -First 1
        if ($release) { return $release.FullName }
        $defaultDir = $dirs | Where-Object { $_.Name -like "*default*" } | Select-Object -First 1
        if ($defaultDir) { return $defaultDir.FullName }
        if ($dirs.Count -gt 0) { return $dirs[0].FullName }
    }

    throw "Could not automatically locate Zen Browser profile folder."
}

function Get-ChromeCssContent {
    # Check local file relative to script
    $localFile = $null
    if ($PSScriptRoot) {
        $candidate = Join-Path $PSScriptRoot "chrome.css"
        if (Test-Path $candidate) {
            $localFile = $candidate
        }
    }
    if (-not $localFile -and (Test-Path "chrome.css")) {
        $localFile = (Resolve-Path "chrome.css").Path
    }

    if ($localFile) {
        Write-Host "Reading local chrome.css from: $localFile"
        return [System.IO.File]::ReadAllText($localFile)
    }

    # Fetch from remote GitHub repo
    $remoteUrl = "https://raw.githubusercontent.com/daustinn/zen-macify/main/chrome.css"
    Write-Host "Downloading chrome.css from GitHub..."
    $response = Invoke-RestMethod -Uri $remoteUrl -Method Get
    return $response
}

try {
    $targetProfile = Get-ZenProfilePath -CustomPath $ProfilePath
    Write-Host "Target Zen profile: $targetProfile"

    $chromeDir = Join-Path $targetProfile "chrome"
    if (-not (Test-Path $chromeDir)) {
        New-Item -ItemType Directory -Path $chromeDir -Force | Out-Null
    }

    $targetFile = Join-Path $chromeDir "zen-themes.css"
    $cssContent = (Get-ChromeCssContent).Trim()

    $startMarker = "/* === START ZEN MACIFY === */"
    $endMarker = "/* === END ZEN MACIFY === */"
    $wrappedContent = "$startMarker`r`n$cssContent`r`n$endMarker"

    if (Test-Path $targetFile) {
        $existingContent = [System.IO.File]::ReadAllText($targetFile)

        if ($existingContent -match [regex]::Escape($startMarker) -and $existingContent -match [regex]::Escape($endMarker)) {
            $pattern = "(?s)" + [regex]::Escape($startMarker) + ".*?" + [regex]::Escape($endMarker)
            $newContent = [regex]::Replace($existingContent, $pattern, $wrappedContent)
            [System.IO.File]::WriteAllText($targetFile, $newContent)
            Write-Host "Updated Zen Macify section in $targetFile"
        } else {
            $separator = if ($existingContent.Length -gt 0 -and -not $existingContent.EndsWith("`n")) { "`r`n`r`n" } else { "`r`n" }
            $newContent = $existingContent + $separator + $wrappedContent + "`r`n"
            [System.IO.File]::WriteAllText($targetFile, $newContent)
            Write-Host "Appended Zen Macify to $targetFile"
        }
    } else {
        $newContent = $wrappedContent + "`r`n"
        [System.IO.File]::WriteAllText($targetFile, $newContent)
        Write-Host "Created $targetFile with Zen Macify content"
    }

    Write-Host "Done. Please restart Zen Browser to apply changes."
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
