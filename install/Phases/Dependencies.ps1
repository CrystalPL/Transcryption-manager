function Invoke-Dependencies {
    <#
    .SYNOPSIS Faza [3-4]: wykrywa zaleznosci, pyta o tryb i instaluje je (portable albo systemowo), zapisuje runtime.json.
    .DESCRIPTION Cienki orkiestrator — deleguje do faz: Get-DepTasks, Invoke-DownloadPhase, Invoke-ReuseSystemPhase, Invoke-PortableExtractPhase, Invoke-WhisperPhase, Save-RuntimeManifest. Stan dzielony przez obiekt $ctx.
    .PARAMETER NoDeps Pomin instalacje.
    .PARAMETER InstallDir Katalog instalacji.
    .PARAMETER LogDir Katalog logow.
    .PARAMETER Total Liczba krokow instalatora (do numeracji).
    #>
    param(
        [switch]$NoDeps,
        [string]$InstallDir,
        [string]$LogDir,
        [int]$Total = 5
    )
    if (-not $LogDir) { $LogDir = $env:TEMP }

    $deps = @(
        [PythonDependency]::new(),
        [FfmpegDependency]::new(),
        [MkvmergeDependency]::new(),
        [WhisperDependency]::new()
    )

    $RuntimeDir      = Join-Path $InstallDir "runtime"
    $portablePresent = Get-PortablePresence -Deps $deps -RuntimeDir $RuntimeDir

    Write-Step "[3/$Total] Sprawdzanie zaleznosci..."
    foreach ($d in $deps) {
        $onPath   = $d.Test()
        $portable = $portablePresent[$d.Name]
        if ($onPath -or $portable) {
            $src = if ($portable -and $onPath) { 'portable + systemowy' }
                   elseif ($portable)          { 'portable' }
                   else                        { 'systemowy' }
            Write-OK ("{0,-9}({1})" -f $d.Name, $src)
        } else {
            Write-Missing $d.Name
        }
    }

    if (Test-Command "nvidia-smi") {
        try {
            $gpuName = (& nvidia-smi --query-gpu=name --format=csv,noheader | Select-Object -First 1).Trim()
            Write-OK "GPU NVIDIA: $gpuName"
        } catch { Write-OK "GPU NVIDIA wykryta" }
    } else {
        Write-Skip "Brak GPU NVIDIA (CUDA) — Whisper bedzie dzialal na CPU (znacznie wolniej)"
    }

    if ($NoDeps) {
        Write-Step "[4/$Total] Instalacja zaleznosci pominieta (-NoDeps)"
        return
    }

    $ctx = @{
        Deps            = $deps
        InstallDir      = $InstallDir
        RuntimeDir      = $RuntimeDir
        LogDir          = $LogDir
        Total           = $Total
        PortablePresent = $portablePresent
        Manifest        = @{}
        NeedRuntime     = $false
        St              = @{}
        RowOf           = @{}
        TableRow        = 0
        TimerRow        = 0
        AfterRow        = [Console]::CursorTop
        W               = [Console]::WindowWidth
        Timeouts        = @{ DlStall = 90; DlTimeout = 1200; Extract = 900; Setup = 600; Pip = 2700; ModelStall = 240; ModelTimeout = 5400 }
    }

    $tasks        = Get-DepTasks -Ctx $ctx
    $installTasks = @($tasks | Where-Object { $_.Mode -ne 'reuse' })
    if ($installTasks.Count -gt 0) { Initialize-ProgressTable -Ctx $ctx -InstallTasks $installTasks }

    Invoke-DownloadPhase        -Ctx $ctx -Tasks $tasks
    $whisperTask = Invoke-ReuseSystemPhase -Ctx $ctx -Tasks $tasks
    Invoke-PortableExtractPhase -Ctx $ctx -Tasks $tasks

    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    Invoke-WhisperPhase -Ctx $ctx -WhisperTask $whisperTask

    Write-Host ""
    Save-RuntimeManifest -Ctx $ctx -InstallTaskCount $installTasks.Count
}
