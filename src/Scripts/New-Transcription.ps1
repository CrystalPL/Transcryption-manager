$VideoExtensions = Get-VideoExtensions

$ProjectRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent

$ConfigDir  = if ($env:TRANSCRIPTION_CONFIG_DIR) { $env:TRANSCRIPTION_CONFIG_DIR } else { $ProjectRoot }
$ConfigPath = Join-Path $ConfigDir "New-Transcription.config.json"

$LogsRoot   = if ($env:TRANSCRIPTION_LOGS_DIR)   { $env:TRANSCRIPTION_LOGS_DIR }   else { Join-Path $ProjectRoot "logi" }
$DefaultOut = if ($env:TRANSCRIPTION_OUTPUT_DIR) { $env:TRANSCRIPTION_OUTPUT_DIR } else { Join-Path $ProjectRoot "Wyniki" }

if (-not (Test-Whisper)) {
    Show-Header -Title "Tworzenie transkrypcji" -Subtitle "BLAD: nie znaleziono whispera"
    Write-Host "  Whisper nie jest zainstalowany." -ForegroundColor Red
    Write-Host "  Uruchom instalator ponownie aby zainstalowac brakujace skladniki." -ForegroundColor Yellow
    $null = Read-Host "`n  Nacisnij Enter aby wrocic do menu"
    return
}

$cfg = Read-Config -Path $ConfigPath -Default @{
    lastSourceDir = ""; lastOutputDir = ""; fp16 = "True"
}

$sourceDir = ""; $selectedFiles = @(); $outputDir = ""
$fp16Val = if ($cfg.fp16) { $cfg.fp16 } else { "True" }

while ($true) {
    Show-Header -Title "Tworzenie transkrypcji" -Krok "[1/3]" -Subtitle "Wybierz folder z nagraniami"
    $sourceDir = Select-Folder "Wskaz folder z nagraniami" $cfg.lastSourceDir ([Environment]::GetFolderPath("MyVideos"))
    if (-not $sourceDir) { return }
    Update-Config -Path $ConfigPath -Key "lastSourceDir" -Value $sourceDir

    $pickerResult = Show-MultiPicker `
        -DirPath  $sourceDir `
        -Title    "Tworzenie transkrypcji" `
        -Krok     "[2/3]" `
        -Extensions $VideoExtensions `
        -ExtensionsLabel "mkv, mp4, avi, mov, wmv, ts, mts..."

    if ($null -eq $pickerResult) { return }
    if ($pickerResult.Count -eq 0) { continue }   # pusty folder -> wroc do KROK 1

    $selectedFiles = @($pickerResult | Where-Object { $_ -and $_ -is [string] })
    if ($selectedFiles.Count -eq 0) { continue }

    Show-Header -Title "Tworzenie transkrypcji" -Krok "[3/3]" -Subtitle "Wybierz folder docelowy"
    $outputDir = Select-Folder "Wskaz folder docelowy" $cfg.lastOutputDir $sourceDir
    if (-not $outputDir) {
        $outputDir = $DefaultOut
        Write-Host "  Uzyto domyslnego: $outputDir" -ForegroundColor DarkGray
    }

    $fp16Val = if (Ask-TakNie "Uzyc fp16? (szybsze na GPU, wylacz jesli bledy)" ($fp16Val -ne "False")) { "True" } else { "False" }

    Save-Config -Path $ConfigPath -Data @{
        lastSourceDir = $sourceDir; lastOutputDir = $outputDir; fp16 = $fp16Val
    }

    Clear-Host
    $w = Get-ConsoleWidth; $b = "-" * ($w - 4)
    Write-Host ""
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host (Fit "  | Tworzenie transkrypcji  [podsumowanie]" $w) -ForegroundColor Cyan
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Folder zrodlowy : " -NoNewline -ForegroundColor DarkGray; Write-Host $sourceDir -ForegroundColor White
    Write-Host "  Folder docelowy : " -NoNewline -ForegroundColor DarkGray; Write-Host $outputDir -ForegroundColor White
    Write-Host "  fp16            : " -NoNewline -ForegroundColor DarkGray; Write-Host $fp16Val   -ForegroundColor White
    Write-Host "  Liczba plikow   : " -NoNewline -ForegroundColor DarkGray; Write-Host $selectedFiles.Count -ForegroundColor White
    Write-Host ""
    foreach ($f in $selectedFiles) {
        Write-Host "    - $(Split-Path $f -Leaf)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host (Fit ("  " + "-" * ($w - 2)) $w) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline; Write-Host " T " -ForegroundColor Black -BackgroundColor Green   -NoNewline; Write-Host "  Rozpocznij transkrypcje" -ForegroundColor White
    Write-Host "  " -NoNewline; Write-Host " W " -ForegroundColor Black -BackgroundColor Yellow  -NoNewline; Write-Host "  Wroc i zmien parametry"  -ForegroundColor White
    Write-Host "  " -NoNewline; Write-Host " Q " -ForegroundColor Black -BackgroundColor DarkGray -NoNewline; Write-Host "  Anuluj"                 -ForegroundColor DarkGray
    Write-Host ""

    $decision = Read-StartBackCancel
    if ($decision -eq 'start')  { break }
    if ($decision -eq 'cancel') { return }
    $cfg = Read-Config -Path $ConfigPath -Default @{}
}

$logsDir = Join-Path $LogsRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$env:PYTHONUNBUFFERED = "1"
$env:PYTHONIOENCODING = "utf-8"

$states = @()
foreach ($f in $selectedFiles) {
    $states += New-WhisperState -Path $f -LogsDir $logsDir
}

$activeIdx = 0
$cancelled = $false

Start-WhisperJob $states[$activeIdx] $outputDir $fp16Val
if ($states[$activeIdx].Status -eq 'Skipped') {
    $activeIdx++
    if ($activeIdx -lt $states.Count) {
        Start-WhisperJob $states[$activeIdx] $outputDir $fp16Val
    }
}

try {
    [Console]::CursorVisible = $false
    Clear-Host
    $lastDashW = [Console]::WindowWidth
    $lastDashH = [Console]::WindowHeight

    while ($activeIdx -lt $states.Count) {
        $cur = $states[$activeIdx]

        $curW = [Console]::WindowWidth
        $curH = [Console]::WindowHeight
        if ($curW -ne $lastDashW -or $curH -ne $lastDashH) {
            $lastDashW = $curW; $lastDashH = $curH
            Clear-Host
        }

        if ($cur.Status -eq 'Active') {
            Update-WhisperProgress $cur
            if ($cur.Process -and $cur.Process.HasExited) {
                Finalize-WhisperJob $cur
                $activeIdx++
                if ($activeIdx -lt $states.Count) {
                    Start-WhisperJob $states[$activeIdx] $outputDir $fp16Val
                    while ($activeIdx -lt $states.Count -and $states[$activeIdx].Status -eq 'Skipped') {
                        $activeIdx++
                        if ($activeIdx -lt $states.Count) {
                            Start-WhisperJob $states[$activeIdx] $outputDir $fp16Val
                        }
                    }
                }
                continue
            }
        }

        Render-Dashboard -States $states -ActiveIdx $activeIdx -AppTitle "Tworzenie transkrypcji"

        $waited = 0
        while (-not [Console]::KeyAvailable -and $waited -lt 500) {
            Start-Sleep -Milliseconds 50
            $waited += 50
            $nw = [Console]::WindowWidth; $nh = [Console]::WindowHeight
            if ($nw -ne $lastDashW -or $nh -ne $lastDashH) {
                $lastDashW = $nw; $lastDashH = $nh
                Clear-Host
                Render-Dashboard -States $states -ActiveIdx $activeIdx -AppTitle "Tworzenie transkrypcji"
            }
        }

        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            $c = [char]::ToLower($k.KeyChar)

            if ($c -eq 'q' -or $k.Key -eq 'Escape') {
                if (Ask-TakNie "Anulowac transkrypcje?" $false) {
                    $cancelled = $true
                    if ($cur.Process -and -not $cur.Process.HasExited) {
                        try { $cur.Process.Kill() } catch {}
                    }
                    break
                }
            } elseif ($c -match '\d') {
                $idx = [int][string]$c - 1
                if ($idx -ge 0 -and $idx -lt $states.Count) {
                    View-Logs $states[$idx]
                }
            }
        }
    }
} finally {
    [Console]::CursorVisible = $true
    foreach ($s in $states) {
        if ($s.Process -and -not $s.Process.HasExited) {
            try { $s.Process.Kill() } catch {}
        }
        if ($s.ErrFile -and (Test-Path $s.ErrFile)) {
            try {
                $err = Read-FileSafe $s.ErrFile
                if ($err.Trim()) {
                    Add-Content -Path $s.LogFile -Value "`n--- STDERR ---`n$err" -Encoding UTF8
                }
                Remove-Item $s.ErrFile -Force -EA SilentlyContinue
            } catch {}
        }
    }
}

Render-Dashboard -States $states -ActiveIdx $states.Count -AppTitle "Tworzenie transkrypcji"

Write-Host ""
if ($cancelled) {
    Write-Host "  Transkrypcja anulowana." -ForegroundColor Yellow
} else {
    $okCount   = ($states | Where-Object { $_.Status -eq 'Done' }).Count
    $skipCount = ($states | Where-Object { $_.Status -eq 'Skipped' }).Count
    $errCount  = ($states | Where-Object { $_.Status -eq 'Error' }).Count
    Write-Host "  Zakonczone: $okCount   Pominiete: $skipCount   Bledy: $errCount" -ForegroundColor Cyan
}
Write-Host "  Logi: $logsDir" -ForegroundColor DarkGray
Write-Host ""
$null = Read-Host "  Nacisnij Enter aby wrocic do menu"
