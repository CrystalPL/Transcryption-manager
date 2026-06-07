function Test-RealPython {
    <#
    .SYNOPSIS Sprawdza czy w systemie jest prawdziwy Python (nie stub WindowsApps).
    .EXAMPLE if (Test-RealPython) { ... }
    #>
    $cmd = Get-Command "python" -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    if ($cmd.Source -like "*\Microsoft\WindowsApps\*") { return $false }
    return $true
}

function Test-WhisperPortable([string]$RuntimeDir) {
    <#
    .SYNOPSIS Czy whisper jest zainstalowany portable (venv lub embeddable) w runtime\.
    .PARAMETER RuntimeDir Katalog runtime instalacji.
    .EXAMPLE Test-WhisperPortable "C:\Transkrypcja\runtime"
    #>
    return (Test-Path (Join-Path $RuntimeDir "whisper-env\Scripts\whisper.exe")) -or
           (Test-Path (Join-Path $RuntimeDir "python\Scripts\whisper.exe"))
}

function Get-PortablePresence {
    <#
    .SYNOPSIS Mapa nazwa->bool: czy dana zaleznosc jest obecna jako portable w runtime\.
    .PARAMETER Deps Lista obiektow Dependency.
    .PARAMETER RuntimeDir Katalog runtime instalacji.
    .EXAMPLE $present = Get-PortablePresence -Deps $deps -RuntimeDir $rt
    #>
    param([object[]]$Deps, [string]$RuntimeDir)
    $exe = @{
        'Python'   = Join-Path $RuntimeDir "python\python.exe"
        'ffmpeg'   = Join-Path $RuntimeDir "ffmpeg\bin\ffmpeg.exe"
        'mkvmerge' = Join-Path $RuntimeDir "mkvtoolnix\mkvmerge.exe"
    }
    $present = @{}
    foreach ($dep in $Deps) {
        if ($dep.Name -eq 'whisper') {
            $present[$dep.Name] = Test-WhisperPortable $RuntimeDir
        } else {
            $p = $exe[$dep.Name]
            $present[$dep.Name] = ($null -ne $p -and (Test-Path $p))
        }
    }
    return $present
}

function Test-AllDepsPresent([string]$InstallDir) {
    <#
    .SYNOPSIS Czy wszystkie zaleznosci sa obecne (portable w runtime\ lub systemowo na PATH).
    .PARAMETER InstallDir Katalog instalacji.
    .EXAMPLE if (Test-AllDepsPresent $InstallDir) { ... }
    #>
    $RuntimeDir = Join-Path $InstallDir "runtime"
    $portableExes = @{
        'Python'   = Join-Path $RuntimeDir "python\python.exe"
        'ffmpeg'   = Join-Path $RuntimeDir "ffmpeg\bin\ffmpeg.exe"
        'mkvmerge' = Join-Path $RuntimeDir "mkvtoolnix\mkvmerge.exe"
    }
    $deps = @([PythonDependency]::new(), [FfmpegDependency]::new(), [MkvmergeDependency]::new(), [WhisperDependency]::new())
    foreach ($d in $deps) {
        if ($d.Name -eq 'whisper') {
            $present = (Test-WhisperPortable $RuntimeDir) -or $d.Test()
        } else {
            $present = (Test-Path $portableExes[$d.Name])
            if (-not $present -and $d.Name -ne 'Python') { $present = $d.Test() }
            if (-not $present -and $d.Name -eq 'Python') { $present = Test-RealPython }
        }
        if (-not $present) { return $false }
    }
    return $true
}
