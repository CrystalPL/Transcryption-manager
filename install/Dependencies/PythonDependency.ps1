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

    [string] LatestEmbeddableVersion() {
        try {
            $releases = Invoke-RestMethod -Uri "https://endoflife.date/api/python.json" -UseBasicParsing
            $ver = $releases |
                Where-Object { (-not $_.eol) -or ([datetime]$_.eol -gt (Get-Date)) } |
                Sort-Object { [version]$_.latest } -Descending |
                Select-Object -ExpandProperty latest -First 1
            if ($ver) { return $ver }
        } catch { }
        return "3.13.3"
    }

    [string] GetPortableZipUrl() {
        $ver = $this.LatestEmbeddableVersion()
        return "https://www.python.org/ftp/python/$ver/python-$ver-embed-amd64.zip"
    }

    [string] GetPortableTempPath() { return (Join-Path $env:TEMP "tm-python-embed.zip") }

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

    [bool] InstallFromZip([string]$ZipPath, [string]$RuntimeDir) {
        $dest = Join-Path $RuntimeDir "python"
        try {
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Expand-Archive -Path $ZipPath -DestinationPath $dest -Force
            Remove-Item $ZipPath -Force -EA SilentlyContinue

            $pth = Get-ChildItem $dest -Filter "python3*._pth" | Select-Object -First 1
            if ($pth) {
                $lines = [System.IO.File]::ReadAllLines($pth.FullName)
                $out   = foreach ($l in $lines) { if ($l.Trim() -eq '#import site') { 'import site' } else { $l } }
                [System.IO.File]::WriteAllLines($pth.FullName, $out)
            }

            $py = Join-Path $dest "python.exe"
            if (-not (Test-Path $py)) {
                Write-Host "        [FAIL] Brak python.exe po rozpakowaniu" -ForegroundColor Red
                return $false
            }

            $getpip = Join-Path $env:TEMP "tm-get-pip.py"
            Write-Host "        Bootstrap pip..." -ForegroundColor DarkGray
            Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getpip -UseBasicParsing
            & $py $getpip --no-warn-script-location
            Remove-Item $getpip -Force -EA SilentlyContinue

            [System.IO.File]::WriteAllText(
                (Join-Path $dest "pip.ini"),
                "[install]`nno-build-isolation = true`n"
            )

            $pipOk = (Test-Path (Join-Path $dest "Scripts\pip.exe")) -or
                     (Test-Path (Join-Path $dest "Lib\site-packages\pip"))
            if (-not $pipOk) {
                Write-Host "        [FAIL] Bootstrap pip nie powiodl sie" -ForegroundColor Red
                return $false
            }
            return $true
        } catch {
            Write-Host "        [FAIL] Python portable: $_" -ForegroundColor Red
            return $false
        }
    }

    [bool] InstallPortable([string]$RuntimeDir) {
        $zip = $this.GetPortableTempPath()
        Write-Host "        Pobieranie Python embeddable..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $this.GetPortableZipUrl() -OutFile $zip -UseBasicParsing
        return $this.InstallFromZip($zip, $RuntimeDir)
    }

    [hashtable] ManifestEntry([string]$Mode, [string]$RuntimeDir, [string]$InstallDir) {
        if ($Mode -eq 'portable') {
            $full = Join-Path (Join-Path $RuntimeDir "python") "python.exe"
            return @{ mode = 'portable'; path = $this.RelPath($full, $InstallDir) }
        }
        return @{ mode = 'system'; path = $this.Command }
    }
}
