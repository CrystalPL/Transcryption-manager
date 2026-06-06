class PythonDependency : Dependency {
    PythonDependency() {
        $this.Name             = "Python"
        $this.Command          = "python"
        $this.SupportsPortable = $true
    }

    [string] LatestPackageId() {
        $found = (winget search "Python.Python.3" --source winget 2>$null |
            Select-String -Pattern 'Python\.Python\.3\.(\d+)').Matches |
            Sort-Object { [int]$_.Groups[1].Value } -Descending |
            Select-Object -ExpandProperty Value -First 1
        if (-not $found) { return "Python.Python.3.14" }
        return $found
    }

    [bool] Install() {
        if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
            Write-Host "        [FAIL] Wymagany winget. Pobierz z Microsoft Store (App Installer)." -ForegroundColor Red
            return $false
        }
        $pkg = $this.LatestPackageId()
        Write-Host "        Pakiet: $pkg" -ForegroundColor DarkGray
        & winget install --id $pkg --source winget --accept-source-agreements --accept-package-agreements --silent
        return $LASTEXITCODE -eq 0
    }

    [bool] InstallPortable([string]$RuntimeDir) {
        $dest = Join-Path $RuntimeDir "python"
        $zip  = Join-Path $env:TEMP "tm-python-embed.zip"
        # Wersja embeddable — stabilna 3.11.9 (whisper + torch maja kola dla 3.11).
        $ver  = "3.11.9"
        $url  = "https://www.python.org/ftp/python/$ver/python-$ver-embed-amd64.zip"
        $tag  = "311"

        try {
            Write-Host "        Pobieranie Python embeddable $ver (~10 MB)..." -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Expand-Archive -Path $zip -DestinationPath $dest -Force
            Remove-Item $zip -Force -EA SilentlyContinue

            # Odblokuj 'import site' (potrzebne by pip i site-packages dzialaly).
            # python3xx._pth ma zakomentowane '#import site' -> odkomentuj.
            $pth = Get-ChildItem $dest -Filter "python${tag}._pth" | Select-Object -First 1
            if (-not $pth) { $pth = Get-ChildItem $dest -Filter "python3*._pth" | Select-Object -First 1 }
            if ($pth) {
                $lines = [System.IO.File]::ReadAllLines($pth.FullName)
                $out = foreach ($l in $lines) {
                    if ($l.Trim() -eq '#import site') { 'import site' } else { $l }
                }
                [System.IO.File]::WriteAllLines($pth.FullName, $out)
            }

            $py = Join-Path $dest "python.exe"
            if (-not (Test-Path $py)) { Write-Host "        [FAIL] Brak python.exe po rozpakowaniu" -ForegroundColor Red; return $false }

            # Bootstrap pip przez get-pip.py (embeddable nie ma ensurepip).
            $getpip = Join-Path $env:TEMP "tm-get-pip.py"
            Write-Host "        Bootstrap pip..." -ForegroundColor DarkGray
            Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getpip -UseBasicParsing
            & $py $getpip --no-warn-script-location
            Remove-Item $getpip -Force -EA SilentlyContinue

            $pipOk = (Test-Path (Join-Path $dest "Scripts\pip.exe")) -or (Test-Path (Join-Path $dest "Lib\site-packages\pip"))
            if (-not $pipOk) { Write-Host "        [FAIL] Bootstrap pip nie powiodl sie" -ForegroundColor Red; return $false }
            return $true
        } catch {
            Write-Host "        [FAIL] Python portable: $_" -ForegroundColor Red
            return $false
        }
    }

    [hashtable] ManifestEntry([string]$Mode, [string]$RuntimeDir, [string]$InstallDir) {
        if ($Mode -eq 'portable') {
            $full = Join-Path (Join-Path $RuntimeDir "python") "python.exe"
            return @{ mode = 'portable'; path = $this.RelPath($full, $InstallDir) }
        }
        return @{ mode = 'system'; path = $this.Command }
    }
}
