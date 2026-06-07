class MkvmergeDependency : Dependency {
    MkvmergeDependency() {
        $this.Name             = "mkvmerge"
        $this.Command          = "mkvmerge"
        $this.SupportsPortable = $true
    }

    hidden [string] LatestVersion() {
        try {
            $resp = Invoke-RestMethod `
                -Uri "https://gitlab.com/api/v4/projects/mbunkus%2Fmkvtoolnix/releases?per_page=1" `
                -UseBasicParsing -Headers @{ "User-Agent" = "tm-installer" }
            $tag = if ($resp -and $resp.Count -gt 0) { $resp[0].tag_name } else { $null }
            $ver = if ($tag) { $tag -replace '^release-', '' } else { $null }
            if ($ver -match '^\d') { return $ver }
        } catch {}
        try {
            $page  = Invoke-WebRequest -Uri "https://mkvtoolnix.download/downloads.html" -UseBasicParsing
            $match = [regex]::Match($page.Content, 'mkvtoolnix-64-bit-([\d.]+)\.7z')
            if ($match.Success) { return $match.Groups[1].Value }
        } catch {}
        return $null
    }

    [string] GetPortableZipUrl() {
        $ver = $this.LatestVersion()
        if (-not $ver) { return $null }
        return "https://mkvtoolnix.download/windows/releases/$ver/mkvtoolnix-64-bit-$ver.7z"
    }

    [string] GetPortableTempPath() { return (Join-Path $env:TEMP "tm-mkvtoolnix.7z") }

    [bool] Install() {
        if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
            Write-Host "        [FAIL] Wymagany winget." -ForegroundColor Red
            return $false
        }
        & winget install --id MoritzBunkus.MKVToolNix --source winget --accept-source-agreements --accept-package-agreements --silent
        return $LASTEXITCODE -eq 0
    }

    [bool] InstallFromZip([string]$SevenZPath, [string]$RuntimeDir) {
        $dest   = Join-Path $RuntimeDir "mkvtoolnix"
        $tmpExt = Join-Path $env:SystemDrive "tm-mkv-x"
        $7zrExe = Join-Path $env:TEMP "tm-7zr.exe"
        try {
            if (-not (Test-Path $7zrExe)) {
                Invoke-WebRequest -Uri "https://www.7-zip.org/a/7zr.exe" -OutFile $7zrExe -UseBasicParsing
            }

            if (Test-Path $tmpExt) { Remove-Item $tmpExt -Recurse -Force }
            New-Item -ItemType Directory -Path $tmpExt -Force | Out-Null

            & $7zrExe x $SevenZPath "-o$tmpExt" -y | Out-Null
            Remove-Item $SevenZPath  -Force -EA SilentlyContinue
            Remove-Item $7zrExe      -Force -EA SilentlyContinue

            $binSrc = Get-ChildItem $tmpExt -Recurse -Filter "mkvmerge.exe" | Select-Object -First 1
            if (-not $binSrc) {
                Write-Host "        [FAIL] Brak mkvmerge.exe po rozpakowaniu" -ForegroundColor Red
                return $false
            }

            $binDir = Split-Path $binSrc.FullName -Parent
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Copy-Item (Join-Path $binDir "*") -Destination $dest -Recurse -Force
            Remove-Item $tmpExt -Recurse -Force -EA SilentlyContinue

            return (Test-Path (Join-Path $dest "mkvmerge.exe"))
        } catch {
            Write-Host "        [FAIL] mkvmerge portable: $_" -ForegroundColor Red
            return $false
        }
    }

    [bool] InstallPortable([string]$RuntimeDir) {
        $url = $this.GetPortableZipUrl()
        if (-not $url) {
            Write-Host "        [FAIL] Nie mozna ustalic URL do mkvtoolnix." -ForegroundColor Red
            return $false
        }
        $tmp = $this.GetPortableTempPath()
        Write-Host "        Pobieranie MKVToolNix..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        return $this.InstallFromZip($tmp, $RuntimeDir)
    }

    [hashtable] ManifestEntry([string]$Mode, [string]$RuntimeDir, [string]$InstallDir) {
        if ($Mode -eq 'portable') {
            $full = Join-Path (Join-Path $RuntimeDir "mkvtoolnix") "mkvmerge.exe"
            return @{ mode = 'portable'; path = $this.RelPath($full, $InstallDir) }
        }
        return @{ mode = 'system'; path = $this.Command }
    }
}
