<#
.SYNOPSIS Konwertuje rozmiar w bajtach na czytelny string (KB/MB/GB).
#>
function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    return "{0:N0} KB" -f ($Bytes / 1KB)
}

<#
.SYNOPSIS Formatuje sekundy jako H..h.M..m.S..s (np. "2h05m12s", "42s").
#>
function Format-Time {
    param([int]$Seconds)
    if ($Seconds -le 0) { return "--" }
    $h = [Math]::Floor($Seconds / 3600)
    $m = [Math]::Floor(($Seconds % 3600) / 60)
    $s = $Seconds % 60
    if ($h -gt 0) { return "{0}h{1:00}m{2:00}s" -f $h, $m, $s }
    if ($m -gt 0) { return "{0}m{1:00}s" -f $m, $s }
    return "${s}s"
}

<#
.SYNOPSIS Klucz sortowania naturalnego: "nr 10" sortuje sie po "nr 2".
.DESCRIPTION Padduje wszystkie sekwencje cyfr zerami do 20 znakow, dzieki czemu
porownanie alfabetyczne daje porzadek liczbowy.
#>
function Get-NaturalSortKey {
    param([string]$Text)
    return [regex]::Replace($Text, '\d+', { param($m) $m.Value.PadLeft(20, '0') })
}

<#
.SYNOPSIS Konwertuje string czasu (HH:MM:SS.ms / MM:SS.ms) na sekundy (int).
.EXAMPLE Convert-DurationToSeconds "00:05:42.500"  # 342
#>
function Convert-DurationToSeconds {
    param([string]$Duration)
    if (-not $Duration) { return 0 }
    $clean = $Duration -replace '[^\d:.]', ''
    $parts = $clean.Split(':')
    $total = 0.0
    foreach ($p in $parts) {
        if ($p -ne '') { $total = $total * 60 + [double]$p }
    }
    return [int]$total
}

<#
.SYNOPSIS Obcina lub padduje string do dokladnie $Length znakow.
#>
function Fit {
    param([string]$Text, [int]$Length)
    if ($Text.Length -gt $Length) { return $Text.Substring(0, $Length) }
    return $Text.PadRight($Length)
}

<#
.SYNOPSIS Wspolna lista rozszerzen plikow wideo obslugiwanych przez aplikacje.
.DESCRIPTION Funkcja (nie zmienna) — odporna na scope niezaleznie od sposobu
uruchomienia skryptu konsumenta. Uzywana przez New-Transcription, Send-FarmJobs,
Add-Chapters do filtrowania w pickerach.
#>
function Get-VideoExtensions {
    return @('.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.m4v',
             '.mpg', '.mpeg', '.ts', '.mts', '.m2ts', '.webm')
}
