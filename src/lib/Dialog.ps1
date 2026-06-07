Add-Type -AssemblyName System.Windows.Forms

<#
.SYNOPSIS Otwiera natywne okno wyboru folderu Windows.
.PARAMETER Description Tekst nad lista folderow
.PARAMETER StartPath Folder od ktorego zaczynamy
#>
function Open-FolderDialog {
    param(
        [string]$Description,
        [string]$StartPath
    )
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description         = $Description
    $dlg.ShowNewFolderButton = $true
    $dlg.SelectedPath        = if ($StartPath -and (Test-Path $StartPath)) { $StartPath } else { $HOME }

    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost      = $true
    $owner.Visible      = $false
    $owner.ShowInTaskbar = $false
    $owner.Size         = New-Object System.Drawing.Size(1, 1)

    $result = $dlg.ShowDialog($owner)
    $owner.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

<#
.SYNOPSIS Wybor folderu z opcja uzycia ostatnio wybranego (z pamieci konfiguracji).
#>
function Select-Folder {
    param(
        [string]$Description,
        [string]$LastDir,
        [string]$Fallback
    )
    if ($LastDir -and (Test-Path $LastDir)) {
        Write-Host "  Ostatnio wybrany : " -NoNewline -ForegroundColor DarkGray
        Write-Host $LastDir -ForegroundColor Cyan
        if (Ask-TakNie "Uzyc tego samego folderu?" $true) { return $LastDir }
        Write-Host ""
    }
    Write-Host "  Otwieram okno wyboru folderu..." -ForegroundColor DarkGray
    $start = if ($LastDir -and (Test-Path $LastDir)) { $LastDir } else { $Fallback }
    return Open-FolderDialog $Description $start
}
