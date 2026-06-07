$ProjectRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent
$ConfigDir   = if ($env:TRANSCRIPTION_CONFIG_DIR) { $env:TRANSCRIPTION_CONFIG_DIR } else { $ProjectRoot }
$ConfigPath  = Join-Path $ConfigDir "Farm.config.json"
$LogsRoot    = if ($env:TRANSCRIPTION_LOGS_DIR) { $env:TRANSCRIPTION_LOGS_DIR } else { Join-Path $ProjectRoot "logi" }

if (-not (Test-Whisper)) {
    Show-Header -Title "Farma: tryb workera" -Subtitle "BLAD: nie znaleziono whispera"
    Write-Host "  Whisper nie jest zainstalowany." -ForegroundColor Red
    Write-Host "  Uruchom instalator ponownie aby zainstalowac brakujace skladniki." -ForegroundColor Yellow
    $null = Read-Host "`n  Nacisnij Enter aby wrocic do menu"
    return
}

$cfg = Read-Config -Path $ConfigPath -Default @{ queuePath = "" }
$queuePath = if ($env:TRANSCRIPTION_FARM_DIR) { $env:TRANSCRIPTION_FARM_DIR } else { $cfg.queuePath }

if (-not $queuePath -or -not (Test-Path $queuePath)) {
    Show-Header -Title "Farma: tryb workera" -Subtitle "Wskaz wspolny folder kolejki (UNC)"
    $queuePath = Select-Folder "Wskaz folder kolejki farmy" $queuePath $ProjectRoot
    if (-not $queuePath) { return }
    Update-Config -Path $ConfigPath -Key "queuePath" -Value $queuePath
}
if (-not (Initialize-FarmQueue $queuePath)) {
    Show-Header -Title "Farma: tryb workera" -Subtitle "BLAD: kolejka niedostepna (share offline?)"
    $null = Read-Host "`n  Nacisnij Enter aby wrocic do menu"
    return
}

$env:PYTHONUNBUFFERED = "1"
$env:PYTHONIOENCODING = "utf-8"

function Render-WorkerIdle {
    param([object]$Counts)
    $w = [Math]::Max(80, [Console]::WindowWidth - 1); $b = "-" * ($w - 4)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$script:ESC[H`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  | Farma: tryb workera ($($env:COMPUTERNAME))  [oczekiwanie]" $w) 'Cyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Kolejka : $queuePath" $w) 'White') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Stan    : todo=$($Counts.Todo)  claimed=$($Counts.Claimed)  done=$($Counts.Done)  failed=$($Counts.Failed)" $w) 'DarkGray') + "`n`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Czekam na wolne zlecenia..." $w) 'Yellow') + "`n`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  [Esc] zakoncz tryb workera" $w) 'DarkGray'))
    [void]$sb.Append("$script:ESC[J")
    [Console]::Write($sb.ToString())
}

$logsDir = Join-Path $LogsRoot ("worker_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$lastHb = [datetime]::MinValue
$running = $true

Write-FarmLog $queuePath "Worker start"
try {
    [Console]::CursorVisible = $false
    Clear-Host
    $lastW = [Console]::WindowWidth; $lastH = [Console]::WindowHeight

    while ($running) {
        Invoke-FarmReclaim $queuePath | Out-Null

        $job = $null
        try { $job = Invoke-FarmClaim $queuePath } catch { $job = $null }

        if ($null -eq $job) {
            Update-FarmWorkerStatus -QueuePath $queuePath -Status "idle"
            $counts = Get-FarmCounts $queuePath

            $curW = [Console]::WindowWidth; $curH = [Console]::WindowHeight
            if ($curW -ne $lastW -or $curH -ne $lastH) { $lastW = $curW; $lastH = $curH; Clear-Host }
            Render-WorkerIdle $counts

            $waited = 0
            while ($waited -lt 1500) {
                if ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if ($k.Key -eq 'Escape' -or [char]::ToLower($k.KeyChar) -eq 'q') { $running = $false; break }
                }
                Start-Sleep -Milliseconds 50
                $waited += 50
                $nw = [Console]::WindowWidth; $nh = [Console]::WindowHeight
                if ($nw -ne $lastW -or $nh -ne $lastH) { $lastW = $nw; $lastH = $nh; Clear-Host; Render-WorkerIdle $counts }
            }
            continue
        }

        $p = Get-FarmPaths $queuePath
        $fp16 = if ($job.fp16) { $job.fp16 } else { "True" }
        $lang = if ($job.language) { $job.language } else { "Polish" }
        $model = if ($job.model) { $job.model } else { "medium" }

        $state = New-WhisperState -Path $job.source -LogsDir $logsDir
        $states = @($state)

        Update-FarmHeartbeat -QueuePath $queuePath -JobId $job.id
        Update-FarmWorkerStatus -QueuePath $queuePath -CurrentFile $state.Name -Progress 0 -Status "working"

        Write-FarmLog $queuePath "Claim: $($job.id) ($($state.Name))"

        if (-not (Test-Path $state.Path)) {
            $state.Status = 'Error'
            $failDest = Join-Path $p.Failed "job-$($job.id).json"
            try { Move-Item -Path $job.ClaimedPath -Destination $failDest -Force -EA Stop } catch {}
            Set-Content -Path ($failDest + ".error") -Value "Plik zrodlowy niedostepny: $($state.Path)" -Encoding UTF8 -EA SilentlyContinue
            $hb = Join-Path $p.Claimed "job-$($job.id).heartbeat"
            if (Test-Path $hb) { Remove-Item $hb -Force -EA SilentlyContinue }
            Write-FarmLog $queuePath "Error: $($job.id) - source missing: $($state.Path)"
            continue
        }

        Start-WhisperJob $state $job.output $fp16 $lang $model

        Clear-Host
        $lastW = [Console]::WindowWidth; $lastH = [Console]::WindowHeight

        while ($state.Status -eq 'Active' -or $state.Status -eq 'Skipped') {
            if ($state.Status -eq 'Skipped') { break }

            Update-WhisperProgress $state

            if (((Get-Date) - $lastHb).TotalSeconds -ge 10) {
                Update-FarmHeartbeat -QueuePath $queuePath -JobId $job.id
                Update-FarmWorkerStatus -QueuePath $queuePath -CurrentFile $state.Name -Progress $state.Progress -Status "working"
                $lastHb = Get-Date
            }

            if ($state.Process -and $state.Process.HasExited) {
                Finalize-WhisperJob $state
                break
            }

            $curW = [Console]::WindowWidth; $curH = [Console]::WindowHeight
            if ($curW -ne $lastW -or $curH -ne $lastH) { $lastW = $curW; $lastH = $curH; Clear-Host }
            Render-Dashboard -States $states -ActiveIdx 0 -AppTitle "Farma: worker ($($env:COMPUTERNAME))"

            $waited = 0
            while (-not [Console]::KeyAvailable -and $waited -lt 500) {
                Start-Sleep -Milliseconds 50
                $waited += 50
                $nw = [Console]::WindowWidth; $nh = [Console]::WindowHeight
                if ($nw -ne $lastW -or $nh -ne $lastH) {
                    $lastW = $nw; $lastH = $nh; Clear-Host
                    Render-Dashboard -States $states -ActiveIdx 0 -AppTitle "Farma: worker ($($env:COMPUTERNAME))"
                }
            }
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Escape' -or [char]::ToLower($k.KeyChar) -eq 'q') {
                    if (Ask-TakNie "Przerwac biezace zadanie i wyjsc? (zadanie wroci do kolejki)" $false) {
                        if ($state.Process -and -not $state.Process.HasExited) { try { $state.Process.Kill() } catch {} }
                        try { Move-Item -Path $job.ClaimedPath -Destination (Join-Path $p.Todo "job-$($job.id).json") -Force -EA Stop } catch {}
                        $hb = Join-Path $p.Claimed "job-$($job.id).heartbeat"
                        if (Test-Path $hb) { Remove-Item $hb -Force -EA SilentlyContinue }
                        Write-FarmLog $queuePath "Returned: $($job.id) ($($state.Name)) - user interrupt"
                        $running = $false
                        break
                    }
                }
            }
        }

        if (-not $running) { break }

        $hb = Join-Path $p.Claimed "job-$($job.id).heartbeat"
        if ($state.Status -eq 'Done' -or $state.Status -eq 'Skipped') {
            try { Move-Item -Path $job.ClaimedPath -Destination (Join-Path $p.Done "job-$($job.id).json") -Force -EA Stop } catch {}
            Write-FarmLog $queuePath "Done: $($job.id) ($($state.Name))"
        } else {
            $failDest = Join-Path $p.Failed "job-$($job.id).json"
            try { Move-Item -Path $job.ClaimedPath -Destination $failDest -Force -EA Stop } catch {}
            $errTail = Read-FileSafe $state.LogFile
            if ($errTail.Length -gt 4000) { $errTail = $errTail.Substring($errTail.Length - 4000) }
            Set-Content -Path ($failDest + ".error") -Value $errTail -Encoding UTF8 -EA SilentlyContinue
            Write-FarmLog $queuePath "Failed: $($job.id) ($($state.Name)) exitcode=$($state.ExitCode)"
        }
        if (Test-Path $hb) { Remove-Item $hb -Force -EA SilentlyContinue }
    }
} finally {
    [Console]::CursorVisible = $true
    Update-FarmWorkerStatus -QueuePath $queuePath -Status "stopped"
    if ($state -and $state.Process -and -not $state.Process.HasExited) { try { $state.Process.Kill() } catch {} }
    Write-FarmLog $queuePath "Worker stop"
}

Clear-Host
Write-Host ""
Write-Host "  Tryb workera zakonczony." -ForegroundColor Cyan
Write-Host "  Logi: $logsDir" -ForegroundColor DarkGray
Write-Host ""
$null = Read-Host "  Nacisnij Enter aby wrocic do menu"
