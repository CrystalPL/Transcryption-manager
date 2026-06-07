function Invoke-Install {
    <#
    .SYNOPSIS Orkiestracja faz instalacji — wspólna dla install.ps1 (dev) i installer.ps1 (release).
    .PARAMETER RepoRoot Katalog zawierający src/ (klon / rozpakowany repo ZIP / rozpakowany src.zip).
    .PARAMETER InstallDir Folder docelowy; pusty = Get-InstallDir zapyta/użyje domyślnego.
    .PARAMETER NoShortcut Pomiń tworzenie skrótu Start Menu.
    .PARAMETER NoDeps Pomiń instalację zależności.
    .PARAMETER LogFile Ścieżka tymczasowego logu instalacji (transkrypt; przenoszony do LogDir po Stop-Transcript).
    .EXAMPLE Invoke-Install -RepoRoot C:\tmp\repo -InstallDir C:\Transkrypcja
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $RepoRoot,
        [string] $InstallDir,
        [switch] $NoShortcut,
        [switch] $NoDeps,
        [string] $LogFile
    )

    Show-Header
    $InstallDir = Get-InstallDir -PassedValue $InstallDir
    Write-Host "`n  Folder instalacji: " -NoNewline -ForegroundColor DarkGray
    Write-Host $InstallDir -ForegroundColor Cyan

    Invoke-SystemCheck
    Invoke-CopyApp      -RepoRoot $RepoRoot -InstallDir $InstallDir

    $LogDir = Join-Path $InstallDir "logs\$(Get-Date -Format 'yyyyMMdd')"
    try { New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null } catch { $LogDir = $env:TEMP }
    Invoke-Dependencies -NoDeps:$NoDeps -InstallDir $InstallDir -LogDir $LogDir
    Invoke-Shortcut     -InstallDir $InstallDir -NoShortcut:$NoShortcut

    Show-Summary -InstallDir $InstallDir -LogFile (Join-Path $LogDir "install.log")
    return $LogDir
}
