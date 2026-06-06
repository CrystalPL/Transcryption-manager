#Requires -Version 5.1
<#
.SYNOPSIS Instalator Transcription Manager.

.DESCRIPTION
Tryb najprostszy (pobierze repo z GitHub):
    irm https://raw.githubusercontent.com/CrystalPL/Transcription-manager/master/install.ps1 | iex

Tryb lokalny (gdy plik jest obok src/ i install/):
    .\install.ps1 -SkipDownload

Inne opcje:
    .\install.ps1 -InstallDir "D:\Apps\TM"   # folder docelowy (zamiast pytania)
    .\install.ps1 -NoShortcut                # nie twórz skrótu Start Menu
    .\install.ps1 -NoDeps                    # nie instaluj brakujących zależności
#>

param(
    [string]$InstallDir,
    [string]$GithubRepo = "CrystalPL/Transcription-manager",
    [string]$Branch     = "master",
    [switch]$SkipDownload,
    [switch]$NoShortcut,
    [switch]$NoDeps
)

$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Add-Type -AssemblyName System.Windows.Forms

$logFile = Join-Path $env:TEMP "transcription-manager-install-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$null = Start-Transcript -Path $logFile -Force -ErrorAction SilentlyContinue

if ($SkipDownload) {
    $repoRoot = $PSScriptRoot
    Write-Host "  Tryb lokalny — pliki z $repoRoot" -ForegroundColor DarkGray
} else {
    $tmpZip = Join-Path $env:TEMP "tm-install.zip"
    $tmpDir = Join-Path $env:TEMP "tm-install-extract"
    $url    = "https://github.com/$GithubRepo/archive/refs/heads/$Branch.zip"

    Write-Host "  Pobieranie aplikacji..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
    } catch {
        Write-Host "  BŁĄD: nie udało się pobrać: $_" -ForegroundColor Red
        exit 1
    }
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
    $repoRoot = (Get-ChildItem $tmpDir -Directory | Select-Object -First 1).FullName
}

$instDir = Join-Path $repoRoot "install"
if (-not (Test-Path $instDir)) {
    Write-Host "  BŁĄD: brak folderu install/ w $repoRoot" -ForegroundColor Red
    exit 1
}

Get-ChildItem (Join-Path $instDir "Core") -Filter *.ps1 | ForEach-Object { . $_.FullName }

# Klasa bazowa Dependency musi sie zaladowac przed pochodnymi (PS class inheritance)
. (Join-Path $instDir "Dependencies\Dependency.ps1")
Get-ChildItem (Join-Path $instDir "Dependencies") -Filter "*Dependency.ps1" |
    Where-Object { $_.Name -ne "Dependency.ps1" } | ForEach-Object { . $_.FullName }

Get-ChildItem (Join-Path $instDir "Phases") -Filter *.ps1 | ForEach-Object { . $_.FullName }

Invoke-Install -RepoRoot $repoRoot -InstallDir $InstallDir -NoShortcut:$NoShortcut -NoDeps:$NoDeps -LogFile $logFile

$null = Stop-Transcript -ErrorAction SilentlyContinue
$null = Read-Host "  Naciśnij Enter aby zakończyć"
