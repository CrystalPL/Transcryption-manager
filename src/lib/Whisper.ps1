# Whisper.ps1 -- uruchamianie i finalizacja zadan whispera (wspoldzielone przez
# transkrypcje lokalna New-Transcription i tryb workera farmy Start-FarmWorker)
# Wymaga: ShellMetadata.ps1 (Read-FileSafe)

<#
.SYNOPSIS Sprawdza czy whisper jest dostepny w PATH (nie odpala procesu).
#>
function Test-Whisper {
    return $null -ne (Get-Command whisper -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS Buduje obiekt State whispera dla jednego pliku (wspolny dla lokalnej transkrypcji i farmy).
.DESCRIPTION Wyprowadza nazwy ze sciezki, czyta dlugosc przez Shell COM (Get-ShellDurations).
Zwraca PSCustomObject z polami konsumowanymi przez Start-WhisperJob/Render-Dashboard.
.PARAMETER Path Pelna sciezka pliku wideo.
.PARAMETER LogsDir Katalog w ktorym whisper zapisze log (<BaseName>.log).
.EXAMPLE New-WhisperState -Path "C:\nagrania\wyklad.mp4" -LogsDir "C:\logi\20260603"
#>
function New-WhisperState {
    param(
        [string]$Path,
        [string]$LogsDir
    )
    $dir      = Split-Path $Path -Parent
    $name     = Split-Path $Path -Leaf
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)

    $durStr = ""
    try {
        $durs = Get-ShellDurations $dir @($name)
        if ($durs[$name]) { $durStr = $durs[$name] }
    } catch {}

    return [PSCustomObject]@{
        Path        = $Path
        Name        = $name
        BaseName    = $baseName
        Duration    = Convert-DurationToSeconds $durStr
        DurationStr = $durStr
        Status      = 'Pending'
        Progress    = 0
        StartTime   = $null
        EndTime     = $null
        LogFile     = Join-Path $LogsDir "$baseName.log"
        ErrFile     = $null
        OutDir      = $null
        Process     = $null
    }
}

<#
.SYNOPSIS Aktualizuje Progress obiektu State na podstawie postepu z logu whispera.
.DESCRIPTION Czyta ostatni timestamp z logu (Get-WhisperProgressSec), liczy procent
wzgledem Duration i mutuje State.Progress (cap 99% w trakcie pracy). No-op gdy Duration <= 0.
Get-WhisperProgressSec jest w Dashboard.ps1 (ladowany po Whisper.ps1) -- wolane dopiero w runtime.
.PARAMETER State Obiekt stanu pliku (z polami LogFile, Duration, Progress).
#>
function Update-WhisperProgress {
    param($State)
    $secDone = Get-WhisperProgressSec $State.LogFile
    if ($State.Duration -gt 0) {
        $State.Progress = [Math]::Min(99, [Math]::Round(100 * $secDone / $State.Duration))
    }
}

<#
.SYNOPSIS Startuje whispera dla jednego pliku (Start-Process, log do pliku).
.DESCRIPTION Mutuje przekazany obiekt State (Status/Progress/Process/OutDir/ErrFile).
Jesli w OutputDir\<BaseName>\*.srt juz istnieje, oznacza Skipped (idempotencja).
.PARAMETER State Obiekt stanu pliku (z polami Path, BaseName, LogFile, ...)
.PARAMETER OutputDir Folder docelowy wynikow
.PARAMETER Fp16Val "True" lub "False"
.PARAMETER Language Jezyk whispera (domyslnie Polish)
.PARAMETER Model Model whispera (domyslnie medium)
#>
function Start-WhisperJob {
    param(
        $State,
        [string]$OutputDir,
        [string]$Fp16Val,
        [string]$Language = "Polish",
        [string]$Model = "medium"
    )
    $fileOutputDir = Join-Path $OutputDir $State.BaseName
    New-Item -ItemType Directory -Force -Path $fileOutputDir | Out-Null
    $State.OutDir = $fileOutputDir

    if (Test-Path (Join-Path $fileOutputDir "*.srt")) {
        $State.Status   = 'Skipped'
        $State.Progress = 100
        $State.EndTime  = Get-Date
        return
    }

    $errFile = $State.LogFile + ".err"
    $State.ErrFile = $errFile

    $argList = @(
        "`"$($State.Path)`""
        "--language", $Language
        "--model", $Model
        "--device", "cuda"
        "--fp16", $Fp16Val
        "--output_format", "all"
        "--output_dir", "`"$fileOutputDir`""
        "--verbose", "True"
    )

    try {
        $proc = Start-Process -FilePath "whisper" `
            -ArgumentList $argList `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $State.LogFile `
            -RedirectStandardError $errFile
    } catch {
        Set-Content -Path $State.LogFile -Value "BLAD startu whispera: $_" -Encoding UTF8
        $State.Status = 'Error'
        $State.EndTime = Get-Date
        return
    }

    $State.Process   = $proc
    $State.Status    = 'Active'
    $State.StartTime = Get-Date
}

<#
.SYNOPSIS Finalizuje zadanie whispera: doklejenie stderr, ustalenie Done/Error.
#>
function Finalize-WhisperJob {
    param($State)
    try { $State.Process.WaitForExit(100) | Out-Null } catch {}
    if ($State.ErrFile -and (Test-Path $State.ErrFile)) {
        try {
            $err = Read-FileSafe $State.ErrFile
            if ($err.Trim()) {
                Add-Content -Path $State.LogFile -Value "`n--- STDERR ---`n$err" -Encoding UTF8
            }
            Remove-Item $State.ErrFile -Force -EA SilentlyContinue
        } catch {}
    }
    $State.EndTime = Get-Date
    $State.Status  = if ($State.Process -and $State.Process.ExitCode -eq 0) { 'Done' } else { 'Error' }
    if ($State.Status -eq 'Done') { $State.Progress = 100 }
}
