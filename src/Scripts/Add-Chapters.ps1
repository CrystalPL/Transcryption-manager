$VideoExtensions = Get-VideoExtensions

$ConfigDir = if ($env:TRANSCRIPTION_CONFIG_DIR) { $env:TRANSCRIPTION_CONFIG_DIR } `
             else { Split-Path $PSCommandPath -Parent | Split-Path -Parent }
$ConfigPath = Join-Path $ConfigDir "Add-Chapters.config.json"

function Test-Mkvmerge {
    return $null -ne (Get-Command mkvmerge -ErrorAction SilentlyContinue)
}

if (-not (Test-Mkvmerge)) {
    Show-Header -Title "Dodawanie rozdzialow" -Subtitle "BLAD: nie znaleziono mkvmerge"
    Write-Host "  Zainstaluj MKVToolNix: " -NoNewline -ForegroundColor Red
    Write-Host "winget install MoritzBunkus.MKVToolNix" -ForegroundColor Cyan
    $null = Read-Host "`n  Nacisnij Enter aby wrocic do menu"
    return
}

$cfg = Read-Config -Path $ConfigPath -Default @{ lastVideoDir = ""; lastXmlDir = "" }

Show-Header -Title "Dodawanie rozdzialow" -Krok "[1/2]" -Subtitle "Wybierz folder z filmem"
$videoDir = Select-Folder "Wskaz folder z filmem wideo" $cfg.lastVideoDir ([Environment]::GetFolderPath("MyVideos"))
if (-not $videoDir) { return }
Update-Config -Path $ConfigPath -Key "lastVideoDir" -Value $videoDir

$videoFile = Show-Picker `
    -StartPath $videoDir `
    -Title "Dodawanie rozdzialow" `
    -Krok "[1/2]" `
    -Extensions $VideoExtensions `
    -ExtensionsLabel "mkv, mp4, avi, mov, wmv, ts, mts..."
if (-not $videoFile) { return }

Show-Header -Title "Dodawanie rozdzialow" -Krok "[2/2]" -Subtitle "Wybierz folder z plikami XML rozdzialow"
$xmlDir = Select-Folder "Wskaz folder z plikami XML rozdzialow" $cfg.lastXmlDir ([Environment]::GetFolderPath("MyDocuments"))
if (-not $xmlDir) { return }
Update-Config -Path $ConfigPath -Key "lastXmlDir" -Value $xmlDir

$xmlFile = Show-Picker `
    -StartPath $xmlDir `
    -Title "Dodawanie rozdzialow" `
    -Krok "[2/2]" `
    -Extensions @('.xml') `
    -ExtensionsLabel "*.xml  (Matroska Chapters)"
if (-not $xmlFile) { return }

$srcDir  = Split-Path $videoFile -Parent
$srcBase = [IO.Path]::GetFileNameWithoutExtension($videoFile)
$outFile = Join-Path $srcDir "$srcBase - timeline.mkv"

Show-Header -Title "Dodawanie rozdzialow" -Subtitle "Podsumowanie"
Write-Host "  Plik wideo     : " -NoNewline -ForegroundColor DarkGray; Write-Host $videoFile -ForegroundColor White
Write-Host "  Rozdzialy XML  : " -NoNewline -ForegroundColor DarkGray; Write-Host $xmlFile   -ForegroundColor White
Write-Host "  Plik wyjsciowy : " -NoNewline -ForegroundColor DarkGray; Write-Host $outFile   -ForegroundColor Cyan
Write-Host ""
if (Test-Path $outFile) {
    Write-Host "  UWAGA: Plik wyjsciowy juz istnieje i zostanie nadpisany." -ForegroundColor DarkYellow
}
if (-not (Ask-TakNie "Rozpoczac dodawanie rozdzialow?" $true)) { return }

Write-Host ""
Write-Host "  Przetwarzanie... (remux bez ponownego kodowania)" -ForegroundColor Yellow
Write-Host ""

$proc = Start-Process -FilePath "mkvmerge" `
    -ArgumentList "--output", "`"$outFile`"", "--chapters", "`"$xmlFile`"", "`"$videoFile`"" `
    -Wait -PassThru -NoNewWindow

if ($proc.ExitCode -gt 1) {
    Write-Host "  BLAD: mkvmerge zakonczyl sie kodem $($proc.ExitCode)." -ForegroundColor Red
    $null = Read-Host "`n  Nacisnij Enter aby wrocic"
    return
}
if (-not (Test-Path $outFile)) {
    Write-Host "  BLAD: Plik wyjsciowy nie powstal." -ForegroundColor Red
    $null = Read-Host "`n  Nacisnij Enter aby wrocic"
    return
}

$outSize = Format-Size (Get-Item $outFile).Length
Write-Host "  [OK] Gotowe!  ($outSize)" -ForegroundColor Green
Write-Host "  $outFile" -ForegroundColor White

Write-Host ""
Write-Host "  Zastapic plik zrodlowy plikiem z rozdzialami?" -ForegroundColor DarkGray
if (Ask-TakNie "Usun oryginal i przemianuj?" $false) {
    try {
        Remove-Item -Path $videoFile -Force -EA Stop
        Rename-Item -Path $outFile -NewName "$srcBase.mkv" -EA Stop
        Write-Host ""
        Write-Host "  [OK] Zapisano jako: $(Join-Path $srcDir "$srcBase.mkv")" -ForegroundColor Green
    } catch {
        Write-Host "  BLAD: $_" -ForegroundColor Red
    }
}

Write-Host ""
$null = Read-Host "  Nacisnij Enter aby wrocic do menu"
