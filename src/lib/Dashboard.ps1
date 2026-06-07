<#
.SYNOPSIS Parsuje ostatni timestamp [start --> end] z logu whispera, zwraca sekundy.
#>
function Get-WhisperProgressSec {
    param([string]$LogFile)
    $content = Read-FileSafe $LogFile
    if (-not $content) { return 0 }
    $matches = [regex]::Matches($content, '-->\s+(\d+(?::\d+)+\.\d+)\]')
    if ($matches.Count -eq 0) { return 0 }
    return Convert-DurationToSeconds $matches[$matches.Count - 1].Groups[1].Value
}

<#
.SYNOPSIS Buduje pasek postepu znakami # i -.
#>
function Build-ProgressBar {
    param([int]$Pct, [int]$Width)
    $Pct  = [Math]::Max(0, [Math]::Min(100, $Pct))
    $fill = [Math]::Floor($Width * $Pct / 100)
    return ("#" * $fill) + ("-" * ($Width - $fill))
}

<#
.SYNOPSIS Renderuje glowny dashboard z listą plikow i pasekiem aktywnego.
.PARAMETER States Tablica obiektow stanu plikow
.PARAMETER ActiveIdx Indeks aktualnie przetwarzanego pliku
.PARAMETER AppTitle Tytul aplikacji w naglowku
#>
function Render-Dashboard {
    param(
        [object[]]$States,
        [int]$ActiveIdx,
        [string]$AppTitle = "Tworzenie transkrypcji"
    )

    $w = [Math]::Max(80, [Console]::WindowWidth - 1)
    $b = "-" * ($w - 4)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$script:ESC[H`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  | $AppTitle  [w toku]" $w) 'Cyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n`n")

    if ($ActiveIdx -lt $States.Count) {
        $cur     = $States[$ActiveIdx]
        $elapsed = if ($cur.StartTime) { [int]((Get-Date) - $cur.StartTime).TotalSeconds } else { 0 }
        $pct     = $cur.Progress
        $eta     = if ($pct -gt 0 -and $pct -lt 100) { [int](($elapsed * (100 - $pct)) / $pct) } else { 0 }

        $suffix = " {0,3}%   uplynelo {1}   pozostalo ~{2}" -f $pct, (Format-Time $elapsed), (Format-Time $eta)
        $barW   = [Math]::Max(15, $w - $suffix.Length - 6)
        $bar    = Build-ProgressBar $pct $barW

        [void]$sb.Append((Wrap-Ansi (Fit ("  Plik $($ActiveIdx + 1) / $($States.Count): " + $cur.Name) $w) 'White') + "`n")
        $statusLine = "  [" + $bar + "]" + $suffix
        [void]$sb.Append((Wrap-Ansi (Fit $statusLine $w) 'Green') + "`n")
    } else {
        [void]$sb.Append((Wrap-Ansi (Fit "  Wszystkie pliki przetworzone." $w) 'Green') + "`n`n")
    }

    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit ("  " + "-" * ($w - 2)) $w) 'DarkGray') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "   #   Status     Plik                                              Dlugosc    Postep   Czas" $w) 'DarkGray') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit ("  " + "-" * ($w - 2)) $w) 'DarkGray') + "`n")

    for ($i = 0; $i -lt $States.Count; $i++) {
        $s = $States[$i]
        $statusTxt = switch ($s.Status) {
            'Pending' { '[   ]' }
            'Active'  { '[>>]'  }
            'Done'    { '[OK]'  }
            'Skipped' { '[--]'  }
            'Error'   { '[!!]'  }
        }
        $color = switch ($s.Status) {
            'Pending' { 'DarkGray' }
            'Active'  { 'Cyan' }
            'Done'    { 'Green' }
            'Skipped' { 'Yellow' }
            'Error'   { 'Red' }
        }

        $nm = $s.Name; $nmW = 50
        if ($nm.Length -gt $nmW) { $nm = $nm.Substring(0, $nmW - 3) + "..." }

        $timeStr = switch ($s.Status) {
            'Pending' { "-" }
            'Active'  { Format-Time ([int]((Get-Date) - $s.StartTime).TotalSeconds) }
            'Done'    { Format-Time ([int]($s.EndTime - $s.StartTime).TotalSeconds) }
            'Skipped' { "pomieto" }
            'Error'   { "blad" }
        }
        $progStr = switch ($s.Status) {
            'Active'  { "{0,3}%" -f $s.Progress }
            'Done'    { "100%" }
            'Skipped' { "  -" }
            'Error'   { " !" }
            default   { "  -" }
        }

        $line = "   {0,2}  {1,-5}  {2,-50}  {3,8}  {4,6}   {5}" -f ($i + 1), $statusTxt, $nm.PadRight($nmW), $s.DurationStr, $progStr, $timeStr
        [void]$sb.Append((Wrap-Ansi (Fit $line $w) $color) + "`n")
    }

    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit ("  " + "-" * ($w - 2)) $w) 'DarkGray') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  [1-9] zobacz logi pliku   [Q] anuluj wszystko" $w) 'DarkGray'))
    [void]$sb.Append("$script:ESC[J")
    [Console]::Write($sb.ToString())
}

<#
.SYNOPSIS Otwiera live viewer logu wybranego pliku. Esc / Q wraca do dashboardu.
#>
function View-Logs {
    param($State)

    [Console]::CursorVisible = $false
    Clear-Host
    $lastLen = -1
    $lastW   = [Console]::WindowWidth
    $lastH   = [Console]::WindowHeight

    while ($true) {
        $w        = [Math]::Max(80, [Console]::WindowWidth - 1)
        $h        = [Console]::WindowHeight
        $maxLines = $h - 5

        if ($w -ne $lastW -or $h -ne $lastH) {
            $lastW = $w; $lastH = $h; $lastLen = -1
            Clear-Host
        }

        $content = Read-FileSafe $State.LogFile
        if ($State.ErrFile -and (Test-Path $State.ErrFile)) {
            $errContent = Read-FileSafe $State.ErrFile
            if ($errContent.Trim()) { $content += "`n--- STDERR ---`n" + $errContent }
        }

        if ($content.Length -ne $lastLen) {
            $lastLen = $content.Length
            $lines   = $content -split "`r?`n"
            $tail    = if ($lines.Count -gt $maxLines) { $lines[($lines.Count - $maxLines)..($lines.Count - 1)] } else { $lines }

            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("$script:ESC[H")
            [void]$sb.Append((Wrap-Ansi (Fit "  Logi: $($State.Name)  [status: $($State.Status)]" $w) 'Cyan') + "`n")
            [void]$sb.Append((Wrap-Ansi (Fit ("  " + "-" * ($w - 2)) $w) 'DarkGray') + "`n`n")

            foreach ($ln in $tail) {
                [void]$sb.Append((Wrap-Ansi (Fit $ln $w) 'White') + "`n")
            }

            [void]$sb.Append("$script:ESC[J")
            [void]$sb.Append("$script:ESC[$($h);1H")
            [void]$sb.Append((Wrap-Ansi (Fit "  [Esc] powrot do dashboardu" $w) 'DarkGray'))
            [Console]::Write($sb.ToString())
        }

        $waited = 0
        while (-not [Console]::KeyAvailable -and $waited -lt 200) {
            Start-Sleep -Milliseconds 50
            $waited += 50
        }
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Escape' -or $k.KeyChar -eq 'q') {
                Clear-Host
                return
            }
        }
    }
}
