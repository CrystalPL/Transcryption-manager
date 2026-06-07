function Invoke-CopyApp {
    param([string]$RepoRoot, [string]$InstallDir)

    Write-Step "[2/5] Kopiowanie aplikacji..."

    $srcDir = Join-Path $RepoRoot "src"
    if (-not (Test-Path $srcDir)) {
        Write-Missing "Brak folderu 'src' w $RepoRoot"
        exit 1
    }

    $drive = Split-Path $InstallDir -Qualifier -ErrorAction SilentlyContinue
    if ($drive -and -not (Test-Path "$drive\")) {
        Write-Missing "Dysk $drive nie istnieje"
        exit 1
    }

    if (Test-Path $InstallDir) {
        Write-Info "Folder $InstallDir już istnieje"
        if (-not (Ask-YN "Nadpisać pliki aplikacji (zachowamy configi i Wyniki/)?" $true)) {
            Write-Host "`n  Instalacja anulowana." -ForegroundColor Red
            throw [OperationCanceledException]::new("Anulowano przez użytkownika")
        }
        $preserve = @("*.config.json", "Wyniki", "logi", "logs")
        Get-ChildItem $InstallDir -Force | Where-Object {
            $name = $_.Name
            $keep = $false
            foreach ($p in $preserve) {
                if ($name -like $p -or $name -eq $p) { $keep = $true; break }
            }
            -not $keep
        } | Remove-Item -Recurse -Force -EA SilentlyContinue
    } else {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    Copy-Item -Path (Join-Path $srcDir "*") -Destination $InstallDir -Recurse -Force
    Write-OK "Skopiowano do $InstallDir"

    $uninstallSrc = Join-Path $RepoRoot "uninstall.ps1"
    if (Test-Path $uninstallSrc) {
        Copy-Item $uninstallSrc -Destination $InstallDir -Force
    }
}
