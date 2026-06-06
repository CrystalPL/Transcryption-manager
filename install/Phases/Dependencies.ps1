function Invoke-Dependencies {
    param(
        [switch]$NoDeps,
        [string]$InstallDir
    )

    # Kolejnosc WYMUSZONA: Python przed Whisperem (whisper portable potrzebuje pip
    # z portable Pythona). pip nie ma trybu portable (idzie z Pythonem) -> pomijamy
    # go w wyborze, ale zostawiamy w tescie obecnosci.
    $dependencies = @(
        [PythonDependency]::new(),
        [FfmpegDependency]::new(),
        [MkvmergeDependency]::new(),
        [WhisperDependency]::new()
    )

    Write-Step "[3/5] Sprawdzanie zależności..."

    foreach ($dep in $dependencies) {
        if ($dep.Test()) { Write-OK $dep.Name } else { Write-Missing $dep.Name }
    }

    if (Test-Command "nvidia-smi") {
        try {
            $gpuName = (& nvidia-smi --query-gpu=name --format=csv,noheader | Select-Object -First 1).Trim()
            Write-OK "GPU NVIDIA: $gpuName"
        } catch { Write-OK "GPU NVIDIA wykryta" }
    } else {
        Write-Skip "Brak GPU NVIDIA — Whisper będzie działał na CPU (znacznie wolniej)"
    }

    if ($NoDeps) {
        Write-Step "[4/5] Instalacja zależności pominięta (-NoDeps)"
        return
    }

    Write-Step "[4/5] Konfiguracja zależności (systemowo / portable / pomiń)..."

    $RuntimeDir  = Join-Path $InstallDir "runtime"
    $manifest    = @{}
    $needRuntime = $false

    foreach ($dep in $dependencies) {
        $name = $dep.Name

        # 1. Reuse gdy juz w systemie.
        if ($dep.Test()) {
            Write-Host "`n  $name — wykryto w systemie" -ForegroundColor DarkGray
            if (Ask-YN "Użyć istniejącej instalacji systemowej $name?" $true) {
                $manifest[$dep.Command] = $dep.ManifestEntry('system', $RuntimeDir, $InstallDir)
                Write-OK "$name — tryb systemowy (reuse)"
                continue
            }
        }

        # 2. Wybor trybu.
        if ($dep.SupportsPortable) {
            $choice = Ask-Choice "Jak zainstalować $name?" @(
                "Systemowo (winget / pip)",
                "Portable (do folderu instalacji)",
                "Pomiń"
            ) 0
        } else {
            $sel = Ask-Choice "Jak zainstalować $name?" @(
                "Systemowo (winget / pip)",
                "Pomiń"
            ) 0
            $choice = if ($sel -eq 0) { 0 } else { 2 }
        }

        switch ($choice) {
            0 {
                Write-Host "  Instaluję $name (systemowo)..." -ForegroundColor Yellow
                if ($dep.Install()) {
                    $manifest[$dep.Command] = $dep.ManifestEntry('system', $RuntimeDir, $InstallDir)
                    Write-OK "$name zainstalowany (systemowo)"
                } else {
                    Write-Missing "Instalacja $name nieudana"
                }
            }
            1 {
                if (-not (Test-Path $RuntimeDir)) { New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null }
                Write-Host "  Instaluję $name (portable)..." -ForegroundColor Yellow
                if ($dep.InstallPortable($RuntimeDir)) {
                    $manifest[$dep.Command] = $dep.ManifestEntry('portable', $RuntimeDir, $InstallDir)
                    $needRuntime = $true
                    Write-OK "$name zainstalowany (portable)"
                } else {
                    Write-Missing "Instalacja portable $name nieudana"
                }
            }
            default {
                Write-Skip "$name — pominięto"
            }
        }
    }

    # Zapis manifestu tylko gdy cokolwiek ustalono.
    if ($manifest.Count -gt 0) {
        $runtimeFile = Join-Path $InstallDir "runtime.json"
        [PSCustomObject]$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $runtimeFile -Encoding UTF8
        Write-OK "Zapisano manifest: $runtimeFile"
    }

    if (-not $needRuntime) {
        Write-Host "`n  UWAGA: narzędzia systemowe mogą wymagać restartu PowerShella," -ForegroundColor Yellow
        Write-Host "         żeby pojawiły się w PATH." -ForegroundColor Yellow
    }
}
