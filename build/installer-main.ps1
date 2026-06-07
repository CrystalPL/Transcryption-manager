$ErrorActionPreference = 'Stop'
$InstallDir = $env:TM_INSTALL_DIR
$NoShortcut = $env:TM_NO_SHORTCUT -eq "1"
$NoDeps     = $env:TM_NO_DEPS     -eq "1"

$logFile = Join-Path $env:TEMP "transcription-manager-install-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$null = Start-Transcript -Path $logFile -Force -ErrorAction SilentlyContinue

Write-Host "  Transcription Manager installer $script:TM_VERSION" -ForegroundColor DarkGray

$srcZip    = Join-Path $env:TEMP "tm-src.zip"
$srcDir    = Join-Path $env:TEMP "tm-src-extract"

Write-Host "  Pobieranie aplikacji ($script:TM_SRC_URL)..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $script:TM_SRC_URL -OutFile $srcZip -UseBasicParsing
} catch {
    Write-Host "  BŁĄD: nie udało się pobrać src.zip: $_" -ForegroundColor Red
    $null = Stop-Transcript -ErrorAction SilentlyContinue
    $null = Read-Host "  Naciśnij Enter aby zakończyć"
    exit 1
}

if (Test-Path $srcDir) { Remove-Item $srcDir -Recurse -Force }
Expand-Archive -Path $srcZip -DestinationPath $srcDir -Force

$repoRoot = $srcDir
if (-not (Test-Path (Join-Path $repoRoot "src"))) {
    $inner = Get-ChildItem $srcDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName "src") } | Select-Object -First 1
    if ($inner) { $repoRoot = $inner.FullName }
}
if (-not (Test-Path (Join-Path $repoRoot "src"))) {
    Write-Host "  BŁĄD: rozpakowany src.zip nie zawiera folderu src/" -ForegroundColor Red
    $null = Stop-Transcript -ErrorAction SilentlyContinue
    $null = Read-Host "  Naciśnij Enter aby zakończyć"
    exit 1
}

$logDir = $null
try {
    $logDir = Invoke-Install -RepoRoot $repoRoot -InstallDir $InstallDir -NoShortcut:$NoShortcut -NoDeps:$NoDeps -LogFile $logFile
} catch [OperationCanceledException] {
    Remove-Item $srcZip -Force -EA SilentlyContinue
    Remove-Item $srcDir -Recurse -Force -EA SilentlyContinue
} catch {
    Write-Host "`n  BLAD INSTALACJI: $_" -ForegroundColor Red
    Write-Host "  Szczegoly w logu: $logFile" -ForegroundColor DarkGray
}

$null = Stop-Transcript -ErrorAction SilentlyContinue
if ($logDir -and (Test-Path $logFile)) {
    try { Move-Item $logFile (Join-Path $logDir "install.log") -Force -ErrorAction Stop } catch {}
}
$null = Read-Host "  Naciśnij dowolny klawisz aby zamknąć"
