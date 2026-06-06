class MkvmergeDependency : Dependency {
    MkvmergeDependency() {
        $this.Name             = "mkvmerge"
        $this.Command          = "mkvmerge"
        $this.SupportsPortable = $true
    }

    [bool] Install() {
        if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
            Write-Host "        [FAIL] Wymagany winget." -ForegroundColor Red
            return $false
        }
        & winget install --id MoritzBunkus.MKVToolNix --source winget --accept-source-agreements --accept-package-agreements --silent
        return $LASTEXITCODE -eq 0
    }

    [bool] InstallPortable([string]$RuntimeDir) {
        $dest = Join-Path $RuntimeDir "mkvtoolnix"
        $zip  = Join-Path $env:TEMP "tm-mkvtoolnix.zip"
        $tmp  = Join-Path $env:TEMP "tm-mkvtoolnix-extract"
        $url  = "https://mkvtoolnix.download/windows/releases/latest/mkvtoolnix-64-bit-latest.7z"

        try {
            Write-Host "        Pobieranie MKVToolNix portable (~40 MB)..." -ForegroundColor DarkGray
            # mkvtoolnix portable jest dystrybuowany jako .7z; jesli brak 7z, sprobuj .zip mirror.
            # Uzywamy oficjalnego ZIP-a portable z GitHub release przez API (asset *.zip).
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/MoritzBunkus/mkvtoolnix-releases/releases/latest" -UseBasicParsing -Headers @{ "User-Agent" = "tm-installer" }
            $asset = $rel.assets | Where-Object { $_.name -match 'win.*portable.*\.zip$' -or $_.name -match 'portable.*64.*\.zip$' } | Select-Object -First 1
            if (-not $asset) { Write-Host "        [FAIL] Brak assetu portable .zip w release" -ForegroundColor Red; return $false }
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing

            if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath $tmp -Force

            $binSrc = Get-ChildItem $tmp -Recurse -Filter "mkvmerge.exe" | Select-Object -First 1
            if (-not $binSrc) { Write-Host "        [FAIL] Brak mkvmerge.exe w archiwum" -ForegroundColor Red; return $false }

            $binDir = Split-Path $binSrc.FullName -Parent
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            # Kopiujemy caly folder bin (mkvmerge wymaga towarzyszacych .dll/libów)
            Copy-Item (Join-Path $binDir "*") -Destination $dest -Recurse -Force

            Remove-Item $zip -Force -EA SilentlyContinue
            Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
            return (Test-Path (Join-Path $dest "mkvmerge.exe"))
        } catch {
            Write-Host "        [FAIL] mkvmerge portable: $_" -ForegroundColor Red
            return $false
        }
    }

    [hashtable] ManifestEntry([string]$Mode, [string]$RuntimeDir, [string]$InstallDir) {
        if ($Mode -eq 'portable') {
            $full = Join-Path (Join-Path $RuntimeDir "mkvtoolnix") "mkvmerge.exe"
            return @{ mode = 'portable'; path = $this.RelPath($full, $InstallDir) }
        }
        return @{ mode = 'system'; path = $this.Command }
    }
}
