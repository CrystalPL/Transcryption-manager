class FfmpegDependency : Dependency {
    FfmpegDependency() {
        $this.Name             = "ffmpeg"
        $this.Command          = "ffmpeg"
        $this.SupportsPortable = $true
    }

    [string] GetPortableZipUrl() {
        return "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    }

    [string] GetPortableTempPath() { return (Join-Path $env:TEMP "tm-ffmpeg.zip") }

    [bool] Install() {
        if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
            Write-Host "        [FAIL] Wymagany winget." -ForegroundColor Red
            return $false
        }
        & winget install --id Gyan.FFmpeg --source winget --accept-source-agreements --accept-package-agreements --silent
        return $LASTEXITCODE -eq 0
    }

    [bool] InstallFromZip([string]$ZipPath, [string]$RuntimeDir) {
        $dest = Join-Path $RuntimeDir "ffmpeg"
        $tmp  = Join-Path $env:TEMP "tm-ffmpeg-extract"
        try {
            if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
            Expand-Archive -Path $ZipPath -DestinationPath $tmp -Force
            Remove-Item $ZipPath -Force -EA SilentlyContinue

            $binSrc = Get-ChildItem $tmp -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
            if (-not $binSrc) {
                Write-Host "        [FAIL] Brak ffmpeg.exe w archiwum" -ForegroundColor Red
                return $false
            }

            $binDir = Split-Path $binSrc.FullName -Parent
            $destBin = Join-Path $dest "bin"
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            New-Item -ItemType Directory -Path $destBin -Force | Out-Null
            Copy-Item (Join-Path $binDir "*.exe") -Destination $destBin -Force
            Remove-Item $tmp -Recurse -Force -EA SilentlyContinue

            return (Test-Path (Join-Path $destBin "ffmpeg.exe"))
        } catch {
            Write-Host "        [FAIL] ffmpeg portable: $_" -ForegroundColor Red
            return $false
        }
    }

    [bool] InstallPortable([string]$RuntimeDir) {
        $zip = $this.GetPortableTempPath()
        Write-Host "        Pobieranie ffmpeg (~80 MB)..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $this.GetPortableZipUrl() -OutFile $zip -UseBasicParsing
        return $this.InstallFromZip($zip, $RuntimeDir)
    }

    [hashtable] ManifestEntry([string]$Mode, [string]$RuntimeDir, [string]$InstallDir) {
        if ($Mode -eq 'portable') {
            $full = Join-Path (Join-Path (Join-Path $RuntimeDir "ffmpeg") "bin") "ffmpeg.exe"
            return @{ mode = 'portable'; path = $this.RelPath($full, $InstallDir) }
        }
        return @{ mode = 'system'; path = $this.Command }
    }
}
