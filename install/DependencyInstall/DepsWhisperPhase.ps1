function Get-WhisperInstallPython {
    <#
    .SYNOPSIS Wybiera Pythona do instalacji whispera portable: embeddable z runtime\python albo izolowany venv runtime\whisper-env zbudowany z systemowego Pythona. Nigdy nie zwraca golego systemowego Pythona. Zwraca sciezke do python.exe lub $null.
    .PARAMETER Ctx Kontekst instalacji.
    #>
    param([hashtable]$Ctx)
    $RuntimeDir = $Ctx.RuntimeDir
    $pyExe      = Join-Path $RuntimeDir "python\python.exe"
    if (Test-Path $pyExe) { return $pyExe }

    $pyCmd = Get-Command "python" -ErrorAction SilentlyContinue
    if (-not $pyCmd -or $pyCmd.Source -like "*\Microsoft\WindowsApps\*") { return $null }
    $basePy = $pyCmd.Source

    $venvDir = Join-Path $RuntimeDir "whisper-env"
    if (Test-Path $venvDir) { Remove-Item $venvDir -Recurse -Force -ErrorAction SilentlyContinue }
    & $basePy -m venv $venvDir 2>&1 | Out-Null
    $venvPy = Join-Path $venvDir "Scripts\python.exe"
    if (Test-Path $venvPy) { return $venvPy }
    return $null
}

function Install-WhisperPackage {
    <#
    .SYNOPSIS Instaluje setuptools/wheel + openai-whisper do podanego Pythona, kazdy krok z guardem timeoutu. Zwraca @{ Ok; WhisperExe; PipLog }.
    .PARAMETER Ctx Kontekst instalacji.
    .PARAMETER InstallPy Sciezka do python.exe (izolowanego).
    #>
    param([hashtable]$Ctx, [string]$InstallPy)
    $st   = $Ctx.St
    $name = 'whisper'

    $LogDir = $Ctx.LogDir
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue | Out-Null }
    if (-not (Test-Path $LogDir)) { $LogDir = $env:TEMP }
    $pipLog = Join-Path $LogDir "pip-whisper.log"

    $st[$name].Phase = 'pip'
    Show-DepRow $Ctx $name

    $savedHome = $env:PYTHONHOME; $savedPath = $env:PYTHONPATH
    $env:PYTHONHOME       = $null; $env:PYTHONPATH = $null
    $env:PYTHONUNBUFFERED = '1';   $env:PYTHONIOENCODING = 'utf-8'

    Add-Content -Path $pipLog -Value "`n=== $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) ===" -Encoding UTF8 -ErrorAction SilentlyContinue
    Add-Content -Path $pipLog -Value "Python: $InstallPy" -Encoding UTF8 -ErrorAction SilentlyContinue

    $setupOut = "$pipLog.setup"; $setupErr = "$pipLog.setup.err"
    $setupProc = Start-Process -FilePath $InstallPy `
        -ArgumentList @('-m', 'pip', 'install', '--upgrade', 'setuptools', 'wheel', '--no-warn-script-location') `
        -RedirectStandardOutput $setupOut -RedirectStandardError $setupErr `
        -NoNewWindow -PassThru
    $setupRes  = Wait-GuardedProcess -Process $setupProc -TimeoutSec $Ctx.Timeouts.Setup
    $setupExit = if ($setupRes.Completed) { $setupProc.ExitCode } else { 1 }
    $env:PYTHONHOME = $savedHome; $env:PYTHONPATH = $savedPath
    Add-Content -Path $pipLog -Value "setuptools exit=$setupExit ($($setupRes.Reason))" -Encoding UTF8 -ErrorAction SilentlyContinue
    foreach ($tf in @($setupOut, $setupErr)) {
        if (Test-Path $tf) {
            $tc = Get-Content $tf -Raw -ErrorAction SilentlyContinue
            if ($tc) { Add-Content -Path $pipLog -Value $tc -Encoding UTF8 -ErrorAction SilentlyContinue }
            Remove-Item $tf -Force -ErrorAction SilentlyContinue
        }
    }

    if ($setupExit -gt 0) { return @{ Ok = $false; WhisperExe = $null; PipLog = $pipLog } }

    $st[$name].StartedAt = Get-Date
    Show-DepRow $Ctx $name

    $installArgs = @('-m', 'pip', 'install', '--upgrade', '--no-build-isolation', 'openai-whisper', '--no-warn-script-location')
    Add-Content -Path $pipLog -Value "`n--- whisper pip: $($installArgs -join ' ') ---" -Encoding UTF8 -ErrorAction SilentlyContinue
    Add-Content -Path $pipLog -Value "start: $((Get-Date).ToString('HH:mm:ss'))" -Encoding UTF8 -ErrorAction SilentlyContinue

    $pipOut = "$pipLog.out"; $pipErrF = "$pipLog.err"
    $savedHome2 = $env:PYTHONHOME; $savedPath2 = $env:PYTHONPATH
    $env:PYTHONHOME = $null; $env:PYTHONPATH = $null
    $env:PYTHONUNBUFFERED = '1'; $env:PYTHONIOENCODING = 'utf-8'

    $pipProc = Start-Process -FilePath $InstallPy -ArgumentList $installArgs `
        -RedirectStandardOutput $pipOut -RedirectStandardError $pipErrF `
        -NoNewWindow -PassThru

    $onTickPip = { Show-DepRow $Ctx $name }.GetNewClosure()
    $pipRes = Wait-GuardedProcess -Process $pipProc -TimeoutSec $Ctx.Timeouts.Pip -OnTick $onTickPip

    $env:PYTHONHOME = $savedHome2; $env:PYTHONPATH = $savedPath2

    foreach ($tf in @($pipOut, $pipErrF)) {
        if (Test-Path $tf) {
            $tc = Get-Content $tf -Raw -ErrorAction SilentlyContinue
            if ($tc) { Add-Content -Path $pipLog -Value $tc -Encoding UTF8 -ErrorAction SilentlyContinue }
            Remove-Item $tf -Force -ErrorAction SilentlyContinue
        }
    }
    $ec = if ($pipRes.Completed) { $pipProc.ExitCode } else { 1 }
    Add-Content -Path $pipLog -Value "end: $((Get-Date).ToString('HH:mm:ss'))  exit=$ec ($($pipRes.Reason))" -Encoding UTF8 -ErrorAction SilentlyContinue

    $pyParent   = Split-Path $InstallPy -Parent
    $scriptsDir = if ($pyParent -like "*\Scripts") { $pyParent } else { Join-Path $pyParent "Scripts" }
    $whisperExe = Join-Path $scriptsDir "whisper.exe"
    Add-Content -Path $pipLog -Value "whisper.exe: $(if ($whisperExe -and (Test-Path $whisperExe)) { 'OK' } else { 'brak' })" -Encoding UTF8 -ErrorAction SilentlyContinue

    $ok = ($ec -eq 0) -and $whisperExe -and (Test-Path $whisperExe)
    return @{ Ok = $ok; WhisperExe = $whisperExe; PipLog = $pipLog }
}

function Save-WhisperModel {
    <#
    .SYNOPSIS Pobiera model 'medium' do <InstallDir>\models (best-effort, z detekcja zastoju i twardym timeoutem).
    .PARAMETER Ctx Kontekst instalacji.
    .PARAMETER InstallPy Sciezka do python.exe z zainstalowanym whisperem.
    #>
    param([hashtable]$Ctx, [string]$InstallPy)
    $st   = $Ctx.St
    $name = 'whisper'

    $modelsDir   = Join-Path $Ctx.InstallDir "models"
    New-Item -ItemType Directory -Force -Path $modelsDir -ErrorAction SilentlyContinue | Out-Null
    $modelLogErr = Join-Path $Ctx.LogDir "whisper-model.err"
    $modelScript = Join-Path $env:TEMP "tm-model-dl.py"
    Set-Content -Path $modelScript -Value "import whisper; whisper.load_model('medium', download_root=r'$modelsDir')" -Encoding UTF8

    $st[$name].Phase     = 'inst'
    $st[$name].LastLine  = "Pobieranie modelu medium (~1.5 GB)..."
    $st[$name].StartedAt = Get-Date
    Show-DepRow $Ctx $name

    $modelProc = Start-Process -FilePath $InstallPy -ArgumentList @($modelScript) `
        -RedirectStandardError $modelLogErr -NoNewWindow -PassThru -ErrorAction SilentlyContinue

    if ($modelProc) {
        $modelsRef   = $modelsDir
        $onTickModel = { Show-DepRow $Ctx $name }.GetNewClosure()
        $probeModel  = {
            try { [string]((Get-ChildItem $modelsRef -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) } catch { '' }
        }.GetNewClosure()
        $null = Wait-GuardedProcess -Process $modelProc -TimeoutSec $Ctx.Timeouts.ModelTimeout -StallSec $Ctx.Timeouts.ModelStall -LivenessProbe $probeModel -OnTick $onTickModel
    }

    Remove-Item $modelScript -Force -ErrorAction SilentlyContinue
    $st[$name].Phase = 'ok'
    Show-DepRow $Ctx $name
}

function Invoke-WhisperPhase {
    <#
    .SYNOPSIS Instaluje whispera portable: izolowany Python (venv/embeddable) -> pip -> model. Nigdy nie instaluje do golego systemowego Pythona.
    .PARAMETER Ctx Kontekst instalacji.
    .PARAMETER WhisperTask Zadanie whispera w trybie 'portable' (lub $null = pomin faze).
    #>
    param([hashtable]$Ctx, $WhisperTask)
    if (-not $WhisperTask) { return }

    $st   = $Ctx.St
    $dep  = $WhisperTask.Dep
    $name = $dep.Name

    if (-not (Test-Path $Ctx.RuntimeDir)) { New-Item -ItemType Directory -Path $Ctx.RuntimeDir -Force | Out-Null }

    $installPy = Get-WhisperInstallPython -Ctx $Ctx
    if (-not $installPy) {
        $st[$name].Phase = 'err'
        Show-DepRow $Ctx $name
        return
    }

    $res = Install-WhisperPackage -Ctx $Ctx -InstallPy $installPy
    $st[$name].Phase = if ($res.Ok) { 'ok' } else { 'err' }
    Show-DepRow $Ctx $name

    if ($res.PipLog -and (Test-Path $res.PipLog)) {
        Write-Host "    Log pip: $($res.PipLog)" -ForegroundColor DarkGray
    }
    if (-not $res.Ok -and $res.PipLog -and (Test-Path $res.PipLog)) {
        $tail = Get-Content $res.PipLog -Tail 20 -ErrorAction SilentlyContinue
        if ($tail) {
            Write-Host ""
            foreach ($line in $tail) { Write-Host "    $line" -ForegroundColor DarkGray }
        }
    }

    if (-not $res.Ok) { return }

    Save-WhisperModel -Ctx $Ctx -InstallPy $installPy

    $Ctx.Manifest[$dep.Command] = @{
        mode = 'portable'
        path = $dep.RelPath($res.WhisperExe, $Ctx.InstallDir)
    }
    $Ctx.NeedRuntime = $true
}
