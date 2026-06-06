function Write-DepsRow {
    param([hashtable]$Row, [bool]$IsSelected, [int]$Width, [hashtable]$Labels)
    $marker  = if ($IsSelected) { "> " } else { "  " }
    $name    = $Row.Dep.Name.PadRight(12)
    $state   = (if ($Row.Detected) { "wykryto" } else { "brak" }).PadRight(10)
    $mode    = $Labels[$Row.Modes[$Row.Idx]]
    $modeStr = "[ <- $($mode.PadRight(16)) -> ]"
    $line    = "  $marker $name  $state  $modeStr"
    $color   = if ($IsSelected) { 'Cyan' } else { 'White' }
    Write-Host $line.PadRight($Width - 1) -ForegroundColor $color -NoNewline
    Write-Host ""
}

function Show-DepsConfig {
    param([object[]]$Deps)

    $labels = @{ reuse = 'Zachowaj'; system = 'Systemowo'; portable = 'Portable' }

    $rows = @()
    foreach ($dep in $Deps) {
        $detected = $dep.Test()
        $modes = if ($dep.SupportsPortable) {
            if ($detected) { @('reuse', 'system', 'portable') } else { @('system', 'portable') }
        } else {
            if ($detected) { @('reuse', 'system') } else { @('system') }
        }
        $rows += @{ Dep = $dep; Detected = $detected; Modes = $modes; Idx = 0 }
    }

    $sel = 0
    $w   = [Console]::WindowWidth
    $sep = "  " + ("-" * ([Math]::Min($w - 4, 58)))

    Write-Host ""
    Write-Host "  Konfiguracja zaleznosci:" -ForegroundColor Cyan
    Write-Host "  (strzalki góra/dól: wybierz   lewo/prawo: zmien tryb   Enter: zatwierdz)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("  {0,-14}  {1,-10}  {2}" -f "Komponent", "Status", "Tryb instalacji") -ForegroundColor DarkGray
    Write-Host $sep -ForegroundColor DarkGray

    $dataRow = [Console]::CursorTop
    for ($i = 0; $i -lt $rows.Count; $i++) { Write-Host "" }
    Write-Host $sep -ForegroundColor DarkGray

    for ($i = 0; $i -lt $rows.Count; $i++) {
        [Console]::SetCursorPosition(0, $dataRow + $i)
        Write-DepsRow $rows[$i] ($i -eq $sel) $w $labels
    }
    [Console]::SetCursorPosition(0, $dataRow + $rows.Count + 1)

    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') { break }

        $prevSel = $sel
        if ($k.Key -eq 'UpArrow')    { $sel = [Math]::Max(0, $sel - 1) }
        if ($k.Key -eq 'DownArrow')  { $sel = [Math]::Min($rows.Count - 1, $sel + 1) }
        if ($k.Key -eq 'LeftArrow') {
            $rows[$sel].Idx = ($rows[$sel].Idx - 1 + $rows[$sel].Modes.Count) % $rows[$sel].Modes.Count
        }
        if ($k.Key -eq 'RightArrow') {
            $rows[$sel].Idx = ($rows[$sel].Idx + 1) % $rows[$sel].Modes.Count
        }

        if ($prevSel -ne $sel) {
            [Console]::SetCursorPosition(0, $dataRow + $prevSel)
            Write-DepsRow $rows[$prevSel] $false $w $labels
        }
        [Console]::SetCursorPosition(0, $dataRow + $sel)
        Write-DepsRow $rows[$sel] $true $w $labels
        [Console]::SetCursorPosition(0, $dataRow + $rows.Count + 1)
    }

    Write-Host ""
    $result = [System.Collections.ArrayList]::new()
    foreach ($r in $rows) {
        [void]$result.Add(@{ Dep = $r.Dep; Mode = $r.Modes[$r.Idx]; ZipDest = $null })
    }
    return $result
}

function Format-DownloadSize([long]$bytes) {
    if ($bytes -ge 1MB) { return "{0:F1} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:F0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Invoke-ParallelDownloads {
    param([array]$Tasks)  # @{Label; Url; Dest}

    $progress = @{}
    $clients  = @()

    foreach ($t in $Tasks) {
        $progress[$t.Label] = @{ Pct = 0; Downloaded = 0L; Total = 0L; Done = $false }
    }

    foreach ($t in $Tasks) {
        $capturedLabel    = $t.Label
        $capturedProgress = $progress
        $handler = {
            param($s, $e)
            $capturedProgress[$capturedLabel].Pct        = $e.ProgressPercentage
            $capturedProgress[$capturedLabel].Downloaded = $e.BytesReceived
            $capturedProgress[$capturedLabel].Total      = $e.TotalBytesToReceive
        }.GetNewClosure()
        $wc = New-Object System.Net.WebClient
        $wc.Add_DownloadProgressChanged([System.Net.DownloadProgressChangedEventHandler]$handler)
        $wc.DownloadFileAsync([Uri]$t.Url, $t.Dest)
        $clients += $wc
    }

    $startTime = Get-Date
    $w         = [Console]::WindowWidth
    $startRow  = [Console]::CursorTop
    for ($i = 0; $i -le $Tasks.Count; $i++) { Write-Host "" }

    while ($clients | Where-Object { $_.IsBusy }) {
        $elapsed    = [int]((Get-Date) - $startTime).TotalSeconds
        $elapsedStr = "{0}:{1:D2}" -f [int]($elapsed / 60), ($elapsed % 60)

        [Console]::SetCursorPosition(0, $startRow)
        foreach ($t in $Tasks) {
            $p      = $progress[$t.Label]
            $pct    = $p.Pct
            $filled = [Math]::Min(20, [int]($pct / 5))
            $bar    = "[" + ("=" * $filled) + (" " * (20 - $filled)) + "]"
            $dl     = Format-DownloadSize $p.Downloaded
            $tot    = if ($p.Total -gt 0) { Format-DownloadSize $p.Total } else { "??" }
            $line   = "  {0,-12} {1} {2,3}%  {3,8} / {4}" -f $t.Label, $bar, $pct, $dl, $tot
            Write-Host $line.PadRight($w - 1) -ForegroundColor White
        }
        Write-Host ("  Czas: $elapsedStr").PadRight($w - 1) -ForegroundColor DarkGray

        Start-Sleep -Milliseconds 250
    }

    # Finalny render po zakonczeniu
    $elapsed    = [int]((Get-Date) - $startTime).TotalSeconds
    $elapsedStr = "{0}:{1:D2}" -f [int]($elapsed / 60), ($elapsed % 60)
    [Console]::SetCursorPosition(0, $startRow)
    foreach ($t in $Tasks) {
        $p    = $progress[$t.Label]
        $tot  = Format-DownloadSize $p.Total
        $line = "  {0,-12} [====================] 100%  {1,8}" -f $t.Label, $tot
        Write-Host $line.PadRight($w - 1) -ForegroundColor Green
    }
    Write-Host ("  Czas: $elapsedStr").PadRight($w - 1) -ForegroundColor DarkGray

    $clients | ForEach-Object { $_.Dispose() }
}

function Invoke-Dependencies {
    param(
        [switch]$NoDeps,
        [string]$InstallDir
    )

    # Kolejnosc wymuszona: Python przed Whisperem (whisper portable potrzebuje pip z portable Pythona)
    $deps = @(
        [PythonDependency]::new(),
        [FfmpegDependency]::new(),
        [MkvmergeDependency]::new(),
        [WhisperDependency]::new()
    )

    Write-Step "[3/5] Sprawdzanie zaleznosci..."
    foreach ($d in $deps) {
        if ($d.Test()) { Write-OK $d.Name } else { Write-Missing $d.Name }
    }

    if (Test-Command "nvidia-smi") {
        try {
            $gpuName = (& nvidia-smi --query-gpu=name --format=csv,noheader | Select-Object -First 1).Trim()
            Write-OK "GPU NVIDIA: $gpuName"
        } catch { Write-OK "GPU NVIDIA wykryta" }
    } else {
        Write-Skip "Brak GPU NVIDIA — Whisper bedzie dzialal na CPU (znacznie wolniej)"
    }

    if ($NoDeps) {
        Write-Step "[4/5] Instalacja zaleznosci pominieta (-NoDeps)"
        return
    }

    Write-Step "[4/5] Konfiguracja zaleznosci..."

    $RuntimeDir  = Join-Path $InstallDir "runtime"
    $manifest    = @{}
    $needRuntime = $false

    # --- Faza 1: zbierz wybory przez interaktywna tabelke ---
    $tasks = Show-DepsConfig $deps

    # --- Faza 2: rozwiaz URL-e i pobierz wszystko rownoleglie ---
    $downloadTasks = [System.Collections.ArrayList]::new()
    foreach ($t in $tasks) {
        if ($t.Mode -ne 'portable') { continue }
        $url = $t.Dep.GetPortableZipUrl()
        if (-not $url) { continue }
        $dest       = $t.Dep.GetPortableTempPath()
        $t.ZipDest  = $dest
        [void]$downloadTasks.Add(@{ Label = $t.Dep.Name; Url = $url; Dest = $dest })
    }

    if ($downloadTasks.Count -gt 0) {
        Write-Host ""
        Write-Host "  Pobieranie skladnikow..." -ForegroundColor Cyan
        Invoke-ParallelDownloads $downloadTasks.ToArray()
    }

    # --- Faza 3: instalacja w kolejnosci (Python -> ffmpeg/mkvmerge -> Whisper) ---
    foreach ($t in $tasks) {
        $dep  = $t.Dep
        $name = $dep.Name

        switch ($t.Mode) {
            'reuse' {
                $manifest[$dep.Command] = $dep.ManifestEntry('system', $RuntimeDir, $InstallDir)
                Write-OK "$name — tryb systemowy (reuse)"
            }
            'system' {
                Write-Host "`n  Instaluje $name (systemowo)..." -ForegroundColor Yellow
                if ($dep.Install()) {
                    $manifest[$dep.Command] = $dep.ManifestEntry('system', $RuntimeDir, $InstallDir)
                    Write-OK "$name zainstalowany (systemowo)"
                } else {
                    Write-Missing "Instalacja $name nieudana"
                }
            }
            'portable' {
                if (-not (Test-Path $RuntimeDir)) { New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null }
                Write-Host "`n  Instaluje $name (portable)..." -ForegroundColor Yellow
                $ok = if ($t.ZipDest -and (Test-Path $t.ZipDest)) {
                    $dep.InstallFromZip($t.ZipDest, $RuntimeDir)
                } else {
                    $dep.InstallPortable($RuntimeDir)
                }
                if ($ok) {
                    $manifest[$dep.Command] = $dep.ManifestEntry('portable', $RuntimeDir, $InstallDir)
                    $needRuntime = $true
                    Write-OK "$name zainstalowany (portable)"
                } else {
                    Write-Missing "Instalacja portable $name nieudana"
                }
            }
        }
    }

    if ($manifest.Count -gt 0) {
        $runtimeFile = Join-Path $InstallDir "runtime.json"
        [PSCustomObject]$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $runtimeFile -Encoding UTF8
        Write-OK "Zapisano manifest: $runtimeFile"
    }

    if (-not $needRuntime) {
        Write-Host "`n  UWAGA: narzedzia systemowe moga wymagac restartu PowerShella," -ForegroundColor Yellow
        Write-Host "         zeby pojawily sie w PATH." -ForegroundColor Yellow
    }
}
