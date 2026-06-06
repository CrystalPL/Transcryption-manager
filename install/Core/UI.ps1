function Ask-YN {
    param([string]$Q, [bool]$Default = $true)
    $opt = if ($Default) { "[T/n]" } else { "[t/N]" }
    Write-Host "`n  $Q $opt " -NoNewline -ForegroundColor Yellow
    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = [char]::ToLower($k.KeyChar)
        if ($c -eq 't' -or $c -eq 'y') { Write-Host "Tak" -ForegroundColor Green; return $true }
        if ($c -eq 'n')                 { Write-Host "Nie" -ForegroundColor Red;   return $false }
    }
}

function Show-Header {
    Clear-Host
    $script:Bar = "=" * 70
    Write-Host ""
    Write-Host "  $script:Bar" -ForegroundColor Cyan
    Write-Host "    Transcription Manager — Instalator" -ForegroundColor White
    Write-Host "  $script:Bar" -ForegroundColor Cyan
}

function Get-InstallDir {
    param([string]$PassedValue)
    if ($PassedValue) { return $PassedValue }

    $default = "C:\Transkrypcja"
    Write-Host ""
    Write-Host "  Domyślny folder instalacji: " -NoNewline -ForegroundColor Yellow
    Write-Host $default -ForegroundColor Cyan

    if (Ask-YN "Użyć domyślnego folderu?" $true) { return $default }

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description         = "Wybierz folder docelowy dla Transcription Manager"
    $dlg.ShowNewFolderButton = $true
    $dlg.SelectedPath        = "C:\"

    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true; $owner.Visible = $false; $owner.ShowInTaskbar = $false
    $owner.Size = New-Object System.Drawing.Size(1, 1)
    $result = $dlg.ShowDialog($owner)
    $owner.Dispose()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "`n  Anulowano." -ForegroundColor DarkGray
        exit 0
    }
    return $dlg.SelectedPath
}

function Show-Summary {
    param([string]$InstallDir, [string]$LogFile)
    Write-Host ""
    Write-Host "  $script:Bar" -ForegroundColor Green
    Write-Host "    Instalacja zakończona!" -ForegroundColor White
    Write-Host "  $script:Bar" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Aplikacja zainstalowana w: " -NoNewline -ForegroundColor DarkGray
    Write-Host $InstallDir -ForegroundColor White
    Write-Host ""
    Write-Host "  Uruchom przez:" -ForegroundColor White
    Write-Host "    - Klawisz Windows -> 'Zarządzanie transkrypcją'" -ForegroundColor Cyan
    Write-Host "    - Lub bezpośrednio: $(Join-Path $InstallDir 'Manager.ps1')" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Odinstaluj: $(Join-Path $InstallDir 'uninstall.ps1')" -ForegroundColor DarkGray
    Write-Host "  Log instalacji: " -NoNewline -ForegroundColor DarkGray
    Write-Host $LogFile -ForegroundColor DarkGray
    Write-Host ""
}

function Ask-Choice {
    param(
        [string]$Question,
        [string[]]$Options,
        [int]$Default = 0
    )
    $sel = $Default
    $w   = [Console]::WindowWidth

    Write-Host ""
    Write-Host "  $Question" -ForegroundColor Yellow
    Write-Host "  (strzalki góra/dół, Enter zatwierdza)" -ForegroundColor DarkGray

    $startRow = [Console]::CursorTop
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $sel) { ">" } else { " " }
        $color  = if ($i -eq $sel) { 'Cyan' } else { 'White' }
        Write-Host ("    $marker  $($Options[$i])").PadRight($w - 1) -ForegroundColor $color
    }

    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') { break }

        $newSel = $sel
        if ($k.Key -eq 'UpArrow')   { $newSel = [Math]::Max(0, $sel - 1) }
        if ($k.Key -eq 'DownArrow') { $newSel = [Math]::Min($Options.Count - 1, $sel + 1) }

        if ($newSel -ne $sel) {
            [Console]::SetCursorPosition(0, $startRow + $sel)
            Write-Host ("       $($Options[$sel])").PadRight($w - 1) -ForegroundColor White -NoNewline
            [Console]::SetCursorPosition(0, $startRow + $newSel)
            Write-Host ("    >  $($Options[$newSel])").PadRight($w - 1) -ForegroundColor Cyan -NoNewline
            $sel = $newSel
        }
    }

    [Console]::SetCursorPosition(0, $startRow + $Options.Count)
    Write-Host ""
    return $sel
}
