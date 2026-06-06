function Ask-YN {
    param([string]$Q, [bool]$Default = $true)
    $opt = if ($Default) { "[T/n]" } else { "[t/N]" }
    Write-Host "`n  $Q $opt " -NoNewline -ForegroundColor Yellow
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') {
            $lbl = if ($Default) { "Tak" } else { "Nie" }
            $col = if ($Default) { 'Green' } else { 'Red' }
            Write-Host $lbl -ForegroundColor $col
            return $Default
        }
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
    Write-Host ""
    Write-Host "  $Question" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $Default) { ">" } else { " " }
        Write-Host ("    $marker $($i+1)  $($Options[$i])") -ForegroundColor White
    }
    Write-Host "  Wybór: " -NoNewline -ForegroundColor Yellow

    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') {
            Write-Host ($Default + 1) -ForegroundColor Green
            return $Default
        }
        $c = $k.KeyChar
        if ($c -match '\d') {
            $n = [int][string]$c - 1
            if ($n -ge 0 -and $n -lt $Options.Count) {
                Write-Host ($n + 1) -ForegroundColor Green
                return $n
            }
        }
    }
}
