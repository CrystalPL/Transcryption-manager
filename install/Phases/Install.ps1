function Invoke-Install {
    <#
    .SYNOPSIS Orkiestracja faz instalacji — wspólna dla install.ps1 (dev) i installer.ps1 (release).
    .PARAMETER RepoRoot Katalog zawierający src/ (klon / rozpakowany repo ZIP / rozpakowany src.zip).
    .PARAMETER InstallDir Folder docelowy; pusty = Get-InstallDir zapyta/użyje domyślnego.
    .PARAMETER NoShortcut Pomiń tworzenie skrótu Start Menu.
    .PARAMETER NoDeps Pomiń instalację zależności.
    .PARAMETER LogFile Ścieżka logu instalacji (do wyświetlenia w podsumowaniu).
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
    Invoke-Dependencies -NoDeps:$NoDeps -InstallDir $InstallDir
    Invoke-Shortcut     -InstallDir $InstallDir -NoShortcut:$NoShortcut

    Show-Summary -InstallDir $InstallDir -LogFile $LogFile
}
