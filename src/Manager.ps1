#Requires -Version 5.1
# Manager.ps1 -- entry point dla aplikacji Transcription Manager
# Dot-source'uje lib/, pokazuje menu glowne, uruchamia Scripts/

# Wymus UTF-8 w konsoli (zeby polskie znaki w nazwach plikow sie poprawnie wyswietlaly)
# PS 5.1 domyslnie uzywa systemowego code page (CP1250 dla PL Windows) -- nie zgadza sie z UTF-8 plikow
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
    $OutputEncoding           = [System.Text.UTF8Encoding]::new()
} catch {}

$ScriptRoot = Split-Path $PSCommandPath -Parent
$LibDir     = Join-Path $ScriptRoot "lib"
$ScriptsDir = Join-Path $ScriptRoot "Scripts"

# ============== ZALADUJ WSZYSTKIE BIBLIOTEKI ==============
# Kolejnosc wazna: Format -> Ansi -> Console -> reszta.
# Lista pochodzi z LoadOrder.ps1 (jedno zrodlo prawdy, wspoldzielone z bootstrapem
# workera w Watch-Farm.ps1). LoadOrder.ps1 ladujemy jawnie -- nie ma go w liscie.
. (Join-Path $LibDir 'LoadOrder.ps1')
$libOrder = Get-LibLoadOrder
foreach ($libFile in $libOrder) {
    . (Join-Path $LibDir $libFile)
}

# Dopisz portable narzedzia (runtime.json) na poczatek PATH -- whisper sam odpala
# ffmpeg przez subprocess i znajduje go po PATH, wiec MUSI tu trafic. No-op bez manifestu.
Initialize-RuntimePath

# ============== MENU GLOWNE ==============
function Show-MainMenu {
    $w = Get-ConsoleWidth
    $b = "-" * ($w - 4)

    Clear-Host
    Write-Host ""
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host (Fit "  | Transcription Manager" $w) -ForegroundColor Cyan
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host (Fit "  Co chcesz zrobić?" $w) -ForegroundColor White
    Write-Host (Fit ("  " + "-" * ($w - 2)) $w) -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  " -NoNewline
    Write-Host " 1 " -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    Write-Host "  Tworzenie transkrypcji" -ForegroundColor White
    Write-Host "      Whisper AI — generuje .srt / .vtt / .txt z plików wideo" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  " -NoNewline
    Write-Host " 2 " -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    Write-Host "  Dodawanie rozdziałów do nagrania" -ForegroundColor White
    Write-Host "      mkvmerge — wpina XML rozdziały do MKV bez ponownego kodowania" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host (Fit ("  " + "-" * ($w - 2)) $w) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host " 3 " -ForegroundColor Black -BackgroundColor Magenta -NoNewline
    Write-Host "  Farma: dodaj zlecenia" -ForegroundColor White
    Write-Host "      Wrzuca pliki do kolejki na wspólnym folderze (dla wielu maszyn)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host " 4 " -ForegroundColor Black -BackgroundColor Magenta -NoNewline
    Write-Host "  Farma: tryb workera" -ForegroundColor White
    Write-Host "      Ta maszyna bierze zlecenia z kolejki i transkrybuje" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host " 5 " -ForegroundColor Black -BackgroundColor Magenta -NoNewline
    Write-Host "  Farma: monitor" -ForegroundColor White
    Write-Host "      Podgląd liczników kolejki i stanu maszyn" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host (Fit ("  " + "-" * ($w - 2)) $w) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host " Q " -ForegroundColor Black -BackgroundColor DarkGray -NoNewline
    Write-Host "  Wyjście" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Naciśnij 1-5 lub Q..." -ForegroundColor DarkGray
}

function Invoke-Script {
    param([string]$ScriptName)
    $path = Join-Path $ScriptsDir $ScriptName
    if (-not (Test-Path $path)) {
        Write-Host "  BLAD: nie znaleziono $path" -ForegroundColor Red
        $null = Read-Host "`n  Nacisnij Enter..."
        return
    }
    # Dot-source -- skrypt ma dostep do funkcji z lib/
    . $path
}

# ============== PETLA MENU ==============
while ($true) {
    Show-MainMenu
    $k = [Console]::ReadKey($true)
    $c = [char]::ToLower($k.KeyChar)

    switch ($c) {
        '1' { Invoke-Script "New-Transcription.ps1" }
        '2' { Invoke-Script "Add-Chapters.ps1" }
        '3' { Invoke-Script "Send-FarmJobs.ps1" }
        '4' { Invoke-Script "Start-FarmWorker.ps1" }
        '5' { Invoke-Script "Watch-Farm.ps1" }
        default {
            if ($c -eq 'q' -or $k.Key -eq 'Escape') {
                Clear-Host
                exit 0
            }
        }
    }
}
