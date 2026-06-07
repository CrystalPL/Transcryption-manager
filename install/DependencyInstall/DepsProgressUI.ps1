function Format-DownloadSize([long]$bytes) {
    <#
    .SYNOPSIS Formatuje liczbe bajtow jako MB/KB/B.
    .EXAMPLE Format-DownloadSize 1572864   # -> "1.5 MB"
    #>
    if ($bytes -ge 1MB) { return "{0:F1} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:F0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Render-ProgressRow {
    <#
    .SYNOPSIS Rysuje jeden wiersz tabeli postepu wg stanu $St (faza, %, rozmiar, czas).
    .PARAMETER Name Nazwa komponentu.
    .PARAMETER St Hashtable stanu komponentu (Phase, Pct, DlBytes, TotalBytes, StartedAt, LastLine).
    .PARAMETER W Szerokosc konsoli.
    #>
    param([string]$Name, [hashtable]$St, [int]$W)
    $bw    = 20
    $label = ""
    $bar   = "[" + (" " * $bw) + "]"
    $info  = ""
    $color = 'DarkGray'

    switch ($St.Phase) {
        'skip' {
            $label = "Zachowany"
            $bar   = "[" + ("=" * $bw) + "]"
            $color = 'DarkGreen'
        }
        'wait-dl' { $label = "Oczekuje" }
        'wait-in' { $label = "Oczekuje" }
        'dl' {
            $label  = if ($St.DlBytes -gt 0) { "Pobieranie" } else { "Laczenie" }
            $filled = [Math]::Min($bw, [int]($St.Pct * $bw / 100))
            $bar    = "[" + ("=" * $filled) + (" " * ($bw - $filled)) + "]"
            $dlStr  = Format-DownloadSize $St.DlBytes
            $totStr = if ($St.TotalBytes -gt 0) { Format-DownloadSize $St.TotalBytes } else { "??" }
            $info   = " $("{0,3}" -f $St.Pct)%  $("{0,8}" -f $dlStr) / $totStr"
            $color  = 'White'
        }
        'inst' {
            $label   = "Instalowanie"
            $elapsed = if ($St.StartedAt) { [int]((Get-Date) - $St.StartedAt).TotalSeconds } else { 0 }
            $info    = " $($elapsed)s"
            $color   = 'Yellow'
        }
        'pip' {
            $label   = "pip install"
            $elapsed = if ($St.StartedAt) { [int]((Get-Date) - $St.StartedAt).TotalSeconds } else { 0 }
            $min     = [int]($elapsed / 60)
            $sec     = $elapsed % 60
            $timeStr = if ($St.StartedAt) { if ($min -gt 0) { " ${min}m ${sec}s" } else { " ${sec}s" } } else { " ~10-20 min" }
            $pipLine = if ($St.LastLine) { "  $($St.LastLine)" } else { "" }
            $info    = $timeStr + $pipLine
            $color   = 'Yellow'
        }
        'ok' {
            $label  = "Gotowe"
            $bar    = "[" + ("=" * $bw) + "]"
            $sz     = if ($St.TotalBytes -gt 0) { Format-DownloadSize $St.TotalBytes } else { "" }
            $info   = if ($sz) { " $sz" } else { "" }
            $color  = 'Green'
        }
        'err' {
            $label = "Blad!"
            $bar   = "[" + ("!" * $bw) + "]"
            $color = 'Red'
        }
    }

    $line     = "  {0,-10} {1,-12} {2}{3}" -f $Name, $label, $bar, $info
    $rendered = if ($line.Length -gt $W - 1) { $line.Substring(0, $W - 1) } else { $line.PadRight($W - 1) }
    Write-Host $rendered -ForegroundColor $color -NoNewline
    Write-Host ""
}

function Show-DepRow {
    <#
    .SYNOPSIS Renderuje wiersz postepu danej zaleznosci w jej stalej pozycji, po czym wraca kursor pod tabele.
    .PARAMETER Ctx Kontekst instalacji (TableRow, RowOf, St, W, AfterRow).
    .PARAMETER Name Nazwa komponentu.
    #>
    param([hashtable]$Ctx, [string]$Name)
    [Console]::SetCursorPosition(0, $Ctx.TableRow + $Ctx.RowOf[$Name])
    Render-ProgressRow $Name $Ctx.St[$Name] $Ctx.W
    [Console]::SetCursorPosition(0, $Ctx.AfterRow)
}

function Initialize-ProgressTable {
    <#
    .SYNOPSIS Drukuje naglowek tabeli postepu i zapisuje wspolrzedne renderowania do $Ctx (TableRow/TimerRow/AfterRow/RowOf/St).
    .PARAMETER Ctx Kontekst instalacji.
    .PARAMETER InstallTasks Lista zadan z trybem innym niz 'reuse'.
    #>
    param([hashtable]$Ctx, [object[]]$InstallTasks)
    $w   = $Ctx.W
    $sep = "  " + ("-" * [Math]::Min($w - 4, 62))

    Write-Host ""
    Write-Host "  Instalowanie skladnikow..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  {0,-10} {1,-12}  {2}" -f "Komponent", "Status", "Postep") -ForegroundColor DarkGray
    Write-Host $sep -ForegroundColor DarkGray

    $Ctx.TableRow = [Console]::CursorTop
    $ri = 0
    foreach ($t in $InstallTasks) {
        $Ctx.St[$t.Dep.Name]    = @{ Phase = 'wait-dl'; Pct = 0; DlBytes = 0L; TotalBytes = 0L; StartedAt = $null }
        $Ctx.RowOf[$t.Dep.Name] = $ri; $ri++
        Write-Host ""
    }

    Write-Host $sep -ForegroundColor DarkGray
    $Ctx.TimerRow = [Console]::CursorTop; Write-Host ""
    $Ctx.AfterRow = [Console]::CursorTop

    foreach ($t in $InstallTasks) { Show-DepRow $Ctx $t.Dep.Name }
}
