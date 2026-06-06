# Watch-Farm.ps1 -- monitor farmy: liczniki kolejki + tabela workerow + reclaim.
# Na starcie pyta o uruchomienie lokalnego workera (jako osobny proces).
# Reuse: Farm.ps1, Console.ps1, Ansi.ps1.

$ScriptDir   = Split-Path $PSCommandPath -Parent
$ProjectRoot = Split-Path $ScriptDir -Parent
$ConfigDir   = if ($env:TRANSCRIPTION_CONFIG_DIR) { $env:TRANSCRIPTION_CONFIG_DIR } else { $ProjectRoot }
$ConfigPath  = Join-Path $ConfigDir "Farm.config.json"

$cfg = Read-Config -Path $ConfigPath -Default @{ queuePath = "" }
$queuePath = if ($env:TRANSCRIPTION_FARM_DIR) { $env:TRANSCRIPTION_FARM_DIR } else { $cfg.queuePath }

if (-not $queuePath -or -not (Test-Path $queuePath)) {
    Show-Header -Title "Farma: monitor" -Subtitle "Wskaz wspolny folder kolejki (UNC)"
    $queuePath = Select-Folder "Wskaz folder kolejki farmy" $queuePath $ProjectRoot
    if (-not $queuePath) { return }
    Update-Config -Path $ConfigPath -Key "queuePath" -Value $queuePath
}
if (-not (Initialize-FarmQueue $queuePath)) {
    Show-Header -Title "Farma: monitor" -Subtitle "BLAD: kolejka niedostepna (share offline?)"
    $null = Read-Host "`n  Nacisnij Enter aby wrocic do menu"
    return
}

# Decyzja "wybor przy uruchomieniu": czy ta maszyna tez pracuje (osobny proces workera).
Show-Header -Title "Farma: monitor" -Subtitle "Konfiguracja"
if (Ask-TakNie "Uruchomic tez workera na tym komputerze?" $false) {
    # Worker w osobnym oknie: dziedziczy env, ma wlasny dashboard. Komunikacja
    # z monitorem tylko przez workers\<maszyna>.json (zero wspoldzielonego stanu).
    # Manager nie ma trybu "tylko worker", wiec bootstrap inline: laduje lib i
    # odpala Start-FarmWorker.ps1.
    $env:TRANSCRIPTION_FARM_DIR = $queuePath
    $boot = "Set-Location '$ProjectRoot'; " +
            ". (Join-Path 'lib' 'LoadOrder.ps1'); " +
            "foreach (`$f in (Get-LibLoadOrder)) { . (Join-Path 'lib' `$f) }; " +
            "Initialize-RuntimePath; " +
            ". '.\Scripts\Start-FarmWorker.ps1'"
    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $boot
    ) | Out-Null
    Write-Host "  Worker uruchomiony w osobnym oknie." -ForegroundColor Green
    Start-Sleep -Milliseconds 600
}

function Render-FarmMonitor {
    param([string]$QueuePath)
    $w = [Math]::Max(80, [Console]::WindowWidth - 1); $b = "-" * ($w - 4)
    $counts  = Get-FarmCounts $QueuePath
    $workers = Get-FarmWorkers $QueuePath

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$script:ESC[H`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  | Farma: monitor" $w) 'Cyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Kolejka : $QueuePath" $w) 'White') + "`n`n")

    $line = "  todo: {0}    claimed: {1}    done: {2}    failed: {3}" -f $counts.Todo, $counts.Claimed, $counts.Done, $counts.Failed
    [void]$sb.Append((Wrap-Ansi (Fit $line $w) 'Yellow') + "`n`n")

    [void]$sb.Append((Wrap-Ansi (Fit ("  " + "-" * ($w - 2)) $w) 'DarkGray') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Maszyna              Status     Plik                                  Postep   Heartbeat" $w) 'DarkGray') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit ("  " + "-" * ($w - 2)) $w) 'DarkGray') + "`n")

    if ($workers.Count -eq 0) {
        [void]$sb.Append((Wrap-Ansi (Fit "  (brak zarejestrowanych workerow)" $w) 'DarkGray') + "`n")
    } else {
        foreach ($wk in $workers) {
            $dead  = $wk.AgeSec -gt 120
            $color = if ($dead) { 'Red' } elseif ($wk.Status -eq 'working') { 'Green' } else { 'DarkGray' }
            $nm = $wk.CurrentFile; $nmW = 36
            if ($nm.Length -gt $nmW) { $nm = $nm.Substring(0, $nmW - 3) + "..." }
            $hbStr = if ($dead) { "$($wk.AgeSec)s (!)" } else { "$($wk.AgeSec)s" }
            $row = "  {0,-20} {1,-9}  {2,-36}  {3,5}%   {4}" -f `
                $wk.Machine, $wk.Status, $nm.PadRight($nmW), $wk.Progress, $hbStr
            [void]$sb.Append((Wrap-Ansi (Fit $row $w) $color) + "`n")
        }
    }

    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit ("  " + "-" * ($w - 2)) $w) 'DarkGray') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  [Esc] powrot do menu   (reclaim zombie zlecen automatyczny)" $w) 'DarkGray'))
    [void]$sb.Append("$script:ESC[J")
    [Console]::Write($sb.ToString())
}

try {
    [Console]::CursorVisible = $false
    Clear-Host
    $lastW = [Console]::WindowWidth; $lastH = [Console]::WindowHeight

    while ($true) {
        Invoke-FarmReclaim $queuePath | Out-Null

        $curW = [Console]::WindowWidth; $curH = [Console]::WindowHeight
        if ($curW -ne $lastW -or $curH -ne $lastH) { $lastW = $curW; $lastH = $curH; Clear-Host }
        Render-FarmMonitor $queuePath

        $waited = 0
        while (-not [Console]::KeyAvailable -and $waited -lt 1000) {
            Start-Sleep -Milliseconds 50
            $waited += 50
            $nw = [Console]::WindowWidth; $nh = [Console]::WindowHeight
            if ($nw -ne $lastW -or $nh -ne $lastH) { $lastW = $nw; $lastH = $nh; Clear-Host; Render-FarmMonitor $queuePath }
        }
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Escape' -or [char]::ToLower($k.KeyChar) -eq 'q') { break }
        }
    }
} finally {
    [Console]::CursorVisible = $true
}

Clear-Host
