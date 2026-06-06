# Send-FarmJobs.ps1 -- dodaje zlecenia transkrypcji do kolejki farmy (todo\).
# Reuse: Select-Folder, Show-MultiPicker, Config, Farm.ps1. Whispera NIE odpala.

$VideoExtensions = Get-VideoExtensions

$ProjectRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent
$ConfigDir   = if ($env:TRANSCRIPTION_CONFIG_DIR) { $env:TRANSCRIPTION_CONFIG_DIR } else { $ProjectRoot }
$ConfigPath  = Join-Path $ConfigDir "Farm.config.json"

$cfg = Read-Config -Path $ConfigPath -Default @{
    queuePath = ""; defaultOutput = ""; lastSourceDir = ""
    model = "medium"; language = "Polish"; fp16 = "True"
}

# Sciezka kolejki: env override (spojnie z konwencja) -> config -> pytanie.
$queuePath = if ($env:TRANSCRIPTION_FARM_DIR) { $env:TRANSCRIPTION_FARM_DIR } else { $cfg.queuePath }

while ($true) {
    # KROK 1: sciezka kolejki
    Show-Header -Title "Farma: dodaj zlecenia" -Krok "[1/3]" -Subtitle "Wskaz wspolny folder kolejki (UNC)"
    if ($queuePath -and (Test-Path $queuePath)) {
        Write-Host "  Kolejka : " -NoNewline -ForegroundColor DarkGray; Write-Host $queuePath -ForegroundColor Cyan
        if (-not (Ask-TakNie "Uzyc tej samej kolejki?" $true)) { $queuePath = "" }
    }
    if (-not $queuePath -or -not (Test-Path $queuePath)) {
        $queuePath = Select-Folder "Wskaz folder kolejki farmy (np. \\NAS\TM-Farma)" $cfg.queuePath $ProjectRoot
        if (-not $queuePath) { return }
    }
    if (-not (Initialize-FarmQueue $queuePath)) {
        Write-Host "  BLAD: nie udalo sie utworzyc/otworzyc kolejki (share offline?)." -ForegroundColor Red
        $null = Read-Host "`n  Nacisnij Enter aby wrocic do menu"
        return
    }
    Update-Config -Path $ConfigPath -Key "queuePath" -Value $queuePath

    # KROK 2: folder zrodlowy + multipicker
    Show-Header -Title "Farma: dodaj zlecenia" -Krok "[2/3]" -Subtitle "Wybierz folder z nagraniami"
    $sourceDir = Select-Folder "Wskaz folder z nagraniami (osiagalny dla workerow!)" $cfg.lastSourceDir ([Environment]::GetFolderPath("MyVideos"))
    if (-not $sourceDir) { return }
    Update-Config -Path $ConfigPath -Key "lastSourceDir" -Value $sourceDir

    $pickerResult = Show-MultiPicker `
        -DirPath  $sourceDir `
        -Title    "Farma: dodaj zlecenia" `
        -Krok     "[2/3]" `
        -Extensions $VideoExtensions `
        -ExtensionsLabel "mkv, mp4, avi, mov, wmv, ts, mts..."

    if ($null -eq $pickerResult) { return }
    if ($pickerResult.Count -eq 0) { continue }
    $selectedFiles = @($pickerResult | Where-Object { $_ -and $_ -is [string] })
    if ($selectedFiles.Count -eq 0) { continue }

    # KROK 3: folder docelowy + parametry
    Show-Header -Title "Farma: dodaj zlecenia" -Krok "[3/3]" -Subtitle "Wybierz folder docelowy (osiagalny sieciowo)"
    $outputDir = Select-Folder "Wskaz folder docelowy wynikow" $cfg.defaultOutput $sourceDir
    if (-not $outputDir) { return }
    Update-Config -Path $ConfigPath -Key "defaultOutput" -Value $outputDir

    $fp16Val = if ($cfg.fp16) { $cfg.fp16 } else { "True" }
    $fp16Val = if (Ask-TakNie "Uzyc fp16? (szybsze na GPU, wylacz jesli bledy)" ($fp16Val -ne "False")) { "True" } else { "False" }

    $modelVal = if ($cfg.model) { $cfg.model } else { "medium" }
    $langVal  = if ($cfg.language) { $cfg.language } else { "Polish" }

    Save-Config -Path $ConfigPath -Data @{
        queuePath = $queuePath; defaultOutput = $outputDir; lastSourceDir = $sourceDir
        model = $modelVal; language = $langVal; fp16 = $fp16Val
    }

    # Podsumowanie + decyzja (wzorzec z New-Transcription)
    Clear-Host
    $w = Get-ConsoleWidth; $b = "-" * ($w - 4)
    Write-Host ""
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host (Fit "  | Farma: dodaj zlecenia  [podsumowanie]" $w) -ForegroundColor Cyan
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Kolejka         : " -NoNewline -ForegroundColor DarkGray; Write-Host $queuePath -ForegroundColor White
    Write-Host "  Folder docelowy : " -NoNewline -ForegroundColor DarkGray; Write-Host $outputDir -ForegroundColor White
    Write-Host "  Model / jezyk   : " -NoNewline -ForegroundColor DarkGray; Write-Host "$modelVal / $langVal" -ForegroundColor White
    Write-Host "  fp16            : " -NoNewline -ForegroundColor DarkGray; Write-Host $fp16Val -ForegroundColor White
    Write-Host "  Liczba zlecen   : " -NoNewline -ForegroundColor DarkGray; Write-Host $selectedFiles.Count -ForegroundColor White
    Write-Host ""
    foreach ($f in $selectedFiles) {
        Write-Host "    - $(Split-Path $f -Leaf)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host (Fit ("  " + "-" * ($w - 2)) $w) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline; Write-Host " T " -ForegroundColor Black -BackgroundColor Green   -NoNewline; Write-Host "  Wrzuc zlecenia do kolejki" -ForegroundColor White
    Write-Host "  " -NoNewline; Write-Host " W " -ForegroundColor Black -BackgroundColor Yellow  -NoNewline; Write-Host "  Wroc i zmien parametry"    -ForegroundColor White
    Write-Host "  " -NoNewline; Write-Host " Q " -ForegroundColor Black -BackgroundColor DarkGray -NoNewline; Write-Host "  Anuluj"                   -ForegroundColor DarkGray
    Write-Host ""

    $decision = Read-StartBackCancel
    if ($decision -eq 'start')  { break }
    if ($decision -eq 'cancel') { return }
    $cfg = Read-Config -Path $ConfigPath -Default @{}
}

# ============== WRZUCANIE ZLECEN ==============
$created = 0
foreach ($f in $selectedFiles) {
    try {
        $id = Write-FarmJob -QueuePath $queuePath -Source $f -Output $outputDir `
            -Language $langVal -Model $modelVal -Fp16 $fp16Val
        $created++
        Write-Host "  + job-$id.json  <-  $(Split-Path $f -Leaf)" -ForegroundColor Green
    } catch {
        Write-Host "  ! Blad zapisu zlecenia dla $(Split-Path $f -Leaf): $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "  Wrzucono zlecen: $created / $($selectedFiles.Count)" -ForegroundColor Cyan
Write-Host "  Kolejka: $(Join-Path $queuePath 'todo')" -ForegroundColor DarkGray
Write-Host ""
$null = Read-Host "  Nacisnij Enter aby wrocic do menu"
