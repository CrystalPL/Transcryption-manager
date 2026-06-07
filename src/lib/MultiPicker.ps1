$script:MpW           = 80
$script:MpItemListRow = 11

function Format-MpFileLabel {
    param($Item, [int]$Width)
    $sfxLen = 39
    $pfxLen = 7   # "  [X]  "
    $nmW    = [Math]::Max(10, $Width - $pfxLen - $sfxLen)
    $nm     = $Item.RawName
    if ($nm.Length -gt $nmW) { $nm = $nm.Substring(0, $nmW - 3) + "..." }
    $check  = if ($Item.Selected) { "[X]" } else { "[ ]" }
    $Item.Label = "  $check  " + $nm.PadRight($nmW) +
                  "  " + $Item.RawSize.PadLeft(9) +
                  "  " + $Item.RawDate + " " + $Item.RawTime +
                  "  " + $Item.RawDur.PadLeft(8)
}

function Update-MpLabels {
    param([System.Collections.ArrayList]$Items, [int]$Width)
    foreach ($it in $Items) { Format-MpFileLabel $it $Width }
}

function Build-MpItemAnsi {
    param($Item, [bool]$Cursor, [int]$Width)
    $line = Fit $Item.Label $Width
    if ($Cursor) {
        $bg = if ($Item.Selected) { 'DarkGreen' } else { 'DarkBlue' }
        return Wrap-Ansi $line 'White' $bg
    }
    if ($Item.Selected) { return Wrap-Ansi $line 'Green' }
    return Wrap-Ansi $line 'Gray'
}

function Render-MultiPicker {
    param(
        $Krok, $Tytul, $DirPath, $ExtLabel,
        $Items, [int]$Cursor, [int]$Offset, [int]$MaxRows, [int]$SelCount
    )
    $script:MpW = Get-ConsoleWidth
    $w = $script:MpW; $b = "-" * ($w - 4)

    [Console]::CursorVisible = $false
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$script:ESC[H")

    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  | $Tytul  $Krok" $w) 'Cyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n")
    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Wybierz pliki (Spacja = zaznacz, A = wszystkie, Enter = potwierdz)" $w) 'White') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit ("  " + "-" * ($w - 2)) $w) 'DarkGray') + "`n")
    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Katalog : $DirPath" $w) 'White') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Filtr   : $ExtLabel" $w) 'Yellow') + "`n")
    [void]$sb.Append("`n")
    $script:MpItemListRow = 11

    $visCount = [Math]::Min($Items.Count - $Offset, $MaxRows)
    for ($i = 0; $i -lt $visCount; $i++) {
        [void]$sb.Append((Build-MpItemAnsi $Items[$Offset + $i] (($Offset + $i) -eq $Cursor) $w) + "`n")
    }
    for ($i = $visCount; $i -lt $MaxRows; $i++) { [void]$sb.Append((Fit "" $w) + "`n") }

    [void]$sb.Append("`n")
    $status = "  Zaznaczono: $SelCount / $($Items.Count)   [Spacja] zaznacz   [A] wszystkie/zadne   [Enter] potwierdz   [Esc] anuluj"
    [void]$sb.Append((Wrap-Ansi (Fit $status $w) 'DarkGray'))
    [void]$sb.Append("$script:ESC[J")
    [Console]::Write($sb.ToString())
}

function Update-MpTwoRows {
    param($Items, [int]$OldIdx, [int]$NewIdx, [int]$Offset)
    $w = $script:MpW
    $oldRow = $script:MpItemListRow + ($OldIdx - $Offset)
    $newRow = $script:MpItemListRow + ($NewIdx - $Offset)
    $frame  = "$script:ESC[$($oldRow + 1);1H" + (Build-MpItemAnsi $Items[$OldIdx] $false $w) +
              "$script:ESC[$($newRow + 1);1H" + (Build-MpItemAnsi $Items[$NewIdx] $true $w)
    [Console]::Write($frame)
}

function Update-MpOneRow {
    param($Items, [int]$Idx, [bool]$Cursor, [int]$Offset)
    $w = $script:MpW
    $row = $script:MpItemListRow + ($Idx - $Offset)
    $frame = "$script:ESC[$($row + 1);1H" + (Build-MpItemAnsi $Items[$Idx] $Cursor $w)
    [Console]::Write($frame)
}

function Update-MpStatusRow {
    param([int]$SelCount, [int]$Total, [int]$MaxRows)
    $w   = $script:MpW
    $row = $script:MpItemListRow + $MaxRows + 1
    $msg = "  Zaznaczono: $SelCount / $Total   [Spacja] zaznacz   [A] wszystkie/zadne   [Enter] potwierdz   [Esc] anuluj"
    [Console]::Write("$script:ESC[$($row + 1);1H" + (Wrap-Ansi (Fit $msg $w) 'DarkGray'))
}

<#
.SYNOPSIS Multi-select picker plikow w jednym katalogu.
.OUTPUTS Tablica pelnych sciezek wybranych plikow, lub $null gdy Esc
#>
function Show-MultiPicker {
    param(
        [string]$DirPath,
        [string]$Title,
        [string]$Krok,
        [string[]]$Extensions,
        [string]$ExtensionsLabel
    )

    $script:MpW = Get-ConsoleWidth

    $pliki = @(Get-ChildItem -Path $DirPath -File -EA Stop |
        Where-Object { $Extensions -contains $_.Extension.ToLower() } |
        Sort-Object { Get-NaturalSortKey $_.Name })

    if ($pliki.Count -eq 0) {
        Show-Header -Title $Title -Krok $Krok
        Write-Host "  Brak pasujacych plikow w wybranym katalogu." -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "  [Enter] wybierz inny folder    [Esc] anuluj" -ForegroundColor DarkGray
        while ($true) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Enter')  { return @() }    # sygnal: powrot do wyboru folderu
            if ($k.Key -eq 'Escape') { return $null }  # sygnal: anuluj calkowicie
        }
    }

    $durs  = Get-ShellDurations $DirPath ($pliki | ForEach-Object { $_.Name })
    $items = [System.Collections.ArrayList]@()
    foreach ($f in $pliki) {
        $it = [PSCustomObject]@{
            Path     = $f.FullName
            Name     = $f.Name
            RawName  = $f.Name
            RawSize  = Format-Size $f.Length
            RawDate  = $f.LastWriteTime.ToString("dd.MM.yyyy")
            RawTime  = $f.LastWriteTime.ToString("HH:mm")
            RawDur   = if ($durs[$f.Name]) { $durs[$f.Name] } else { "" }
            Selected = $false
            Label    = ""
        }
        Format-MpFileLabel $it $script:MpW
        [void]$items.Add($it)
    }

    $cursor   = 0
    $offset   = 0
    $selCount = 0
    $maxRows  = [Math]::Max(5, [Console]::WindowHeight - 14)
    $lastW    = $script:MpW
    $needFull = $true

    Clear-Host

    try {
        [Console]::CursorVisible = $false
        while ($true) {
            while (-not [Console]::KeyAvailable) {
                Start-Sleep -Milliseconds 30
                $nw = Get-ConsoleWidth
                if ($nw -ne $lastW) {
                    $script:MpW = $nw; $lastW = $nw
                    Update-MpLabels $items $nw
                    $maxRows = [Math]::Max(5, [Console]::WindowHeight - 14)
                    $needFull = $true
                }
                if ($needFull) {
                    Render-MultiPicker $Krok $Title $DirPath $ExtensionsLabel $items $cursor $offset $maxRows $selCount
                    $needFull = $false
                }
            }

            $k    = [Console]::ReadKey($true)
            $prev = $cursor

            $repeat = 1
            if ($k.Key -eq 'UpArrow' -or $k.Key -eq 'DownArrow') {
                while ([Console]::KeyAvailable) {
                    $next = [Console]::ReadKey($true)
                    if ($next.Key -eq $k.Key) { $repeat++ } else { break }
                }
            }

            switch ($k.Key) {
                'UpArrow' {
                    for ($r = 0; $r -lt $repeat; $r++) {
                        $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $items.Count - 1 }
                    }
                }
                'DownArrow' {
                    for ($r = 0; $r -lt $repeat; $r++) {
                        $cursor = if ($cursor -lt $items.Count - 1) { $cursor + 1 } else { 0 }
                    }
                }
                'Spacebar' {
                    $items[$cursor].Selected = -not $items[$cursor].Selected
                    if ($items[$cursor].Selected) { $selCount++ } else { $selCount-- }
                    Format-MpFileLabel $items[$cursor] $script:MpW
                    Update-MpOneRow $items $cursor $true $offset
                    Update-MpStatusRow $selCount $items.Count $maxRows
                }
                'Enter' {
                    $sel = @($items | Where-Object { $_.Selected } | ForEach-Object { $_.Path })
                    if ($sel.Count -eq 0) {
                        $items[$cursor].Selected = $true
                        $sel = @($items[$cursor].Path)
                    }
                    return $sel
                }
                'Escape' { return $null }
                default {
                    $c = [char]::ToLower($k.KeyChar)
                    if ($c -eq 'a') {
                        $any = $selCount -gt 0
                        foreach ($it in $items) { $it.Selected = -not $any }
                        $selCount = if ($any) { 0 } else { $items.Count }
                        Update-MpLabels $items $script:MpW
                        $needFull = $true
                    }
                }
            }

            if (-not $needFull) {
                if ($cursor -lt $offset) {
                    $offset = $cursor; $needFull = $true
                } elseif ($cursor -ge ($offset + $maxRows)) {
                    $offset = $cursor - $maxRows + 1; $needFull = $true
                }
                if (-not $needFull -and $cursor -ne $prev) {
                    Update-MpTwoRows $items $prev $cursor $offset
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}
