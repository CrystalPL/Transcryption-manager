$script:PickerW           = 80
$script:PickerItemListRow = 11

function Format-PickerFileLabel {
    param($Item, [int]$Width)
    $sfxLen = 39
    $nmW    = [Math]::Max(10, $Width - 5 - $sfxLen)
    $nm     = $Item.RawName
    if ($nm.Length -gt $nmW) { $nm = $nm.Substring(0, $nmW - 3) + "..." }
    $Item.Label = "     " + $nm.PadRight($nmW) +
                  "  " + $Item.RawSize.PadLeft(9) +
                  "  " + $Item.RawDate + " " + $Item.RawTime +
                  "  " + $Item.RawDur.PadLeft(8)
}

function Update-PickerLabels {
    param([System.Collections.ArrayList]$Items, [int]$Width)
    foreach ($it in $Items) {
        if ($it.Type -eq 'File') { Format-PickerFileLabel $it $Width }
    }
}

function Build-PickerItemAnsi {
    param($Item, [bool]$Cursor, [int]$Width)
    $line = Fit $Item.Label $Width
    if ($Cursor) {
        $bg = if ($Item.Type -eq 'File') { 'DarkGreen' } else { 'DarkBlue' }
        return Wrap-Ansi $line 'White' $bg
    }
    $fg = switch ($Item.Type) {
        'Parent' { 'DarkYellow' }
        'Dir'    { 'Yellow' }
        default  { 'Gray' }
    }
    return Wrap-Ansi $line $fg
}

function Render-Picker {
    param(
        $Krok, $Tytul, $CurrentPath, $ExtLabel,
        $Items, [int]$Cursor, [int]$Offset, [int]$MaxRows
    )
    $script:PickerW = Get-ConsoleWidth
    $w = $script:PickerW; $b = "-" * ($w - 4)

    [Console]::CursorVisible = $false
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$script:ESC[H")

    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  | $Tytul  $Krok" $w) 'Cyan') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  +$b+" $w) 'DarkCyan') + "`n")
    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Wybierz plik strzalkami i Enter, Backspace = wyzej, Esc = anuluj" $w) 'White') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit ("  " + "-" * ($w - 2)) $w) 'DarkGray') + "`n")
    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Katalog : $CurrentPath" $w) 'White') + "`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  Filtr   : $ExtLabel" $w) 'Yellow') + "`n")
    [void]$sb.Append("`n")
    $script:PickerItemListRow = 11

    $visCount = [Math]::Min($Items.Count - $Offset, $MaxRows)
    for ($i = 0; $i -lt $visCount; $i++) {
        [void]$sb.Append((Build-PickerItemAnsi $Items[$Offset + $i] (($Offset + $i) -eq $Cursor) $w) + "`n")
    }
    for ($i = $visCount; $i -lt $MaxRows; $i++) { [void]$sb.Append((Fit "" $w) + "`n") }

    [void]$sb.Append("`n")
    [void]$sb.Append((Wrap-Ansi (Fit "  [gora/dol] nawigacja   [Enter] wejdz/wybierz   [Backspace] wroc   [Esc] anuluj" $w) 'DarkGray'))
    [void]$sb.Append("$script:ESC[J")
    [Console]::Write($sb.ToString())
}

function Update-PickerTwoRows {
    param($Items, [int]$OldIdx, [int]$NewIdx, [int]$Offset)
    $w = $script:PickerW
    $oldRow = $script:PickerItemListRow + ($OldIdx - $Offset)
    $newRow = $script:PickerItemListRow + ($NewIdx - $Offset)
    $frame  = "$script:ESC[$($oldRow + 1);1H" + (Build-PickerItemAnsi $Items[$OldIdx] $false $w) +
              "$script:ESC[$($newRow + 1);1H" + (Build-PickerItemAnsi $Items[$NewIdx] $true $w)
    [Console]::Write($frame)
}

<#
.SYNOPSIS Pokazuje interaktywny picker plikow z nawigacja po katalogach.
.PARAMETER StartPath Folder startowy
.PARAMETER Title Tytul okna
.PARAMETER Krok Etykieta etapu np "[1/2]"
.PARAMETER Extensions Filtruj po rozszerzeniach @('.mkv', '.mp4')
.PARAMETER ExtensionsLabel Etykieta filtra do wyswietlenia
.OUTPUTS Pelna sciezka wybranego pliku, lub $null gdy Esc
#>
function Show-Picker {
    param(
        [string]$StartPath,
        [string]$Title,
        [string]$Krok,
        [string[]]$Extensions,
        [string]$ExtensionsLabel
    )

    $currentPath = $StartPath
    Clear-Host

    try {
        [Console]::CursorVisible = $false
        while ($true) {
            $script:PickerW = Get-ConsoleWidth

            $items  = [System.Collections.ArrayList]@()
            $parent = Split-Path $currentPath -Parent

            if ($parent -and $parent -ne $currentPath) {
                [void]$items.Add([PSCustomObject]@{
                    Label = "  ^  ..  (katalog nadrzedny)"
                    Type  = 'Parent'; Path = $parent
                })
            }

            try {
                Get-ChildItem -Path $currentPath -Directory -EA Stop |
                    Sort-Object { Get-NaturalSortKey $_.Name } |
                    ForEach-Object {
                        [void]$items.Add([PSCustomObject]@{
                            Label = "  [DIR]  $($_.Name)"
                            Type  = 'Dir'; Path = $_.FullName
                        })
                    }
            } catch {}

            try {
                $pliki  = Get-ChildItem -Path $currentPath -File -EA Stop
                if ($Extensions.Count -gt 0) {
                    $pliki = $pliki | Where-Object { $Extensions -contains $_.Extension.ToLower() }
                }
                $sorted = @($pliki | Sort-Object { Get-NaturalSortKey $_.Name })

                if ($sorted.Count -gt 0) {
                    $durs = Get-ShellDurations $currentPath ($sorted | ForEach-Object { $_.Name })
                    foreach ($f in $sorted) {
                        $it = [PSCustomObject]@{
                            Label   = ""
                            Type    = 'File'
                            Path    = $f.FullName
                            RawName = $f.Name
                            RawSize = Format-Size $f.Length
                            RawDate = $f.LastWriteTime.ToString("dd.MM.yyyy")
                            RawTime = $f.LastWriteTime.ToString("HH:mm")
                            RawDur  = if ($durs[$f.Name]) { $durs[$f.Name] } else { "" }
                        }
                        Format-PickerFileLabel $it $script:PickerW
                        [void]$items.Add($it)
                    }
                }
            } catch {}

            $cursor   = 0
            $offset   = 0
            $maxRows  = [Math]::Max(5, [Console]::WindowHeight - 14)
            $lastW    = $script:PickerW
            $needFull = $true

            while ($true) {
                while (-not [Console]::KeyAvailable) {
                    Start-Sleep -Milliseconds 30
                    $nw = Get-ConsoleWidth
                    if ($nw -ne $lastW) {
                        $script:PickerW = $nw; $lastW = $nw
                        Update-PickerLabels $items $nw
                        $maxRows = [Math]::Max(5, [Console]::WindowHeight - 14)
                        $needFull = $true
                    }
                    if ($needFull) {
                        Render-Picker $Krok $Title $currentPath $ExtensionsLabel $items $cursor $offset $maxRows
                        $needFull = $false
                    }
                }

                $k       = [Console]::ReadKey($true)
                $prevSel = $cursor
                $action  = $null
                $actionPath = $null

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
                            $cursor = if ($cursor -gt 0) { $cursor - 1 } else { [Math]::Max(0, $items.Count - 1) }
                        }
                    }
                    'DownArrow' {
                        for ($r = 0; $r -lt $repeat; $r++) {
                            $cursor = if ($cursor -lt $items.Count - 1) { $cursor + 1 } else { 0 }
                        }
                    }
                    'Enter' {
                        if ($items.Count -gt 0) {
                            $it = $items[$cursor]
                            $actionPath = $it.Path
                            $action = if ($it.Type -eq 'File') { 'Pick' } else { 'Nav' }
                        }
                    }
                    'Backspace' {
                        if ($parent -and $parent -ne $currentPath) {
                            $actionPath = $parent; $action = 'Nav'
                        }
                    }
                    'Escape' { $action = 'Cancel' }
                }

                if ($action) { break }

                if ($cursor -lt $offset) {
                    $offset = $cursor; $needFull = $true
                } elseif ($cursor -ge ($offset + $maxRows)) {
                    $offset = $cursor - $maxRows + 1; $needFull = $true
                }

                if (-not $needFull -and $cursor -ne $prevSel -and $items.Count -gt 0) {
                    Update-PickerTwoRows $items $prevSel $cursor $offset
                }
            }

            switch ($action) {
                'Pick'   { return $actionPath }
                'Cancel' { return $null }
                'Nav'    { $currentPath = $actionPath }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}
