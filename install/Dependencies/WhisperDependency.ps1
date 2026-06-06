class WhisperDependency : Dependency {
    WhisperDependency() {
        $this.Name             = "whisper"
        $this.Command          = "whisper"
        $this.SupportsPortable = $true
    }

    [bool] Install() {
        if (-not (Get-Command "pip" -ErrorAction SilentlyContinue)) {
            Write-Host "        [FAIL] Najpierw zainstaluj Pythona (pip jest z nim)." -ForegroundColor Red
            return $false
        }
        & pip install --upgrade openai-whisper
        return $LASTEXITCODE -eq 0
    }

    [bool] InstallPortable([string]$RuntimeDir) {
        $py = Join-Path (Join-Path $RuntimeDir "python") "python.exe"
        if (-not (Test-Path $py)) {
            Write-Host "        [FAIL] Brak portable Pythona ($py). Zainstaluj Python (portable) najpierw." -ForegroundColor Red
            return $false
        }
        Write-Host "        Instalacja openai-whisper do portable Pythona (PyTorch ~2.5-3 GB)..." -ForegroundColor Yellow
        & $py -m pip install --upgrade openai-whisper --no-warn-script-location
        if ($LASTEXITCODE -ne 0) { return $false }
        return (Test-Path (Join-Path (Join-Path $RuntimeDir "python") "Scripts\whisper.exe"))
    }

    [hashtable] ManifestEntry([string]$Mode, [string]$RuntimeDir, [string]$InstallDir) {
        if ($Mode -eq 'portable') {
            $full = Join-Path (Join-Path (Join-Path $RuntimeDir "python") "Scripts") "whisper.exe"
            return @{ mode = 'portable'; path = $this.RelPath($full, $InstallDir) }
        }
        return @{ mode = 'system'; path = $this.Command }
    }
}
