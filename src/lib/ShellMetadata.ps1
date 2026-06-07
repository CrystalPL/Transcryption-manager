<#
.SYNOPSIS Zwraca hashtable: nazwaPliku -> dlugosc (string "HH:MM:SS").
.PARAMETER DirPath Folder w ktorym sa pliki
.PARAMETER FileNames Lista nazw plikow (bez sciezki)
#>
function Get-ShellDurations {
    param(
        [string]$DirPath,
        [string[]]$FileNames
    )
    $result = @{}
    try {
        $shellApp = New-Object -ComObject Shell.Application
        $shellDir = $shellApp.Namespace($DirPath)

        $durIdx = 27   # typowy default
        for ($i = 0; $i -lt 350; $i++) {
            $pn = $shellDir.GetDetailsOf($null, $i)
            if ($pn -eq "Length" -or $pn -match "^D.ugo") { $durIdx = $i; break }
        }

        foreach ($nm in $FileNames) {
            $item = $shellDir.ParseName($nm)
            if ($item) {
                $raw = ($shellDir.GetDetailsOf($item, $durIdx)).Trim()
                $result[$nm] = if ($raw) { $raw } else { "" }
            } else {
                $result[$nm] = ""
            }
        }
    } catch {}
    return $result
}

<#
.SYNOPSIS Bezpiecznie odczytuje plik nawet jesli inny proces aktualnie do niego pisze.
#>
function Read-FileSafe {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object System.IO.StreamReader($fs)
        $content = $sr.ReadToEnd()
        $sr.Close(); $fs.Close()
        return $content
    } catch { return "" }
}
