# Runtime.ps1 -- rozwiazywanie sciezek do narzedzi (portable vs system) z runtime.json
# Wsteczna kompatybilnosc: brak manifestu -> fallback do Get-Command / golej nazwy.

<#
.SYNOPSIS Zwraca root instalacji (src/lib -> src -> root).
#>
function Get-RuntimeRoot {
    # lib/Runtime.ps1 -> lib -> src -> root instalacji
    return (Split-Path $PSCommandPath -Parent | Split-Path -Parent | Split-Path -Parent)
}

<#
.SYNOPSIS Sciezka do runtime.json (env override w trybie dev, inaczej root instalacji).
#>
function Get-RuntimeManifestPath {
    if ($env:TRANSCRIPTION_RUNTIME_FILE) { return $env:TRANSCRIPTION_RUNTIME_FILE }
    return (Join-Path (Get-RuntimeRoot) "runtime.json")
}

<#
.SYNOPSIS Czyta runtime.json i zwraca hashtable { tool -> @{ mode; path } }. Brak pliku -> $null.
#>
function Get-RuntimeManifest {
    $path = Get-RuntimeManifestPath
    if (-not (Test-Path $path)) { return $null }
    try {
        $json = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
    # PS 5.1: ConvertFrom-Json zwraca PSCustomObject -> konwersja recznie petla.
    $ht = @{}
    foreach ($p in $json.PSObject.Properties) {
        $entry = @{}
        foreach ($q in $p.Value.PSObject.Properties) { $entry[$q.Name] = $q.Value }
        $ht[$p.Name] = $entry
    }
    return $ht
}

<#
.SYNOPSIS Dopisuje katalogi portable narzedzi na POCZATEK $env:PATH procesu. Wolane raz na starcie.
#>
function Initialize-RuntimePath {
    $manifest = Get-RuntimeManifest
    if (-not $manifest) { return }

    $root = Get-RuntimeRoot
    $prepend = @()
    foreach ($name in $manifest.Keys) {
        $entry = $manifest[$name]
        if ($entry.mode -ne 'portable') { continue }
        $full = Join-Path $root $entry.path
        $dir  = Split-Path $full -Parent
        if ($dir -and (Test-Path $dir) -and ($prepend -notcontains $dir)) {
            $prepend += $dir
        }
    }
    if ($prepend.Count -gt 0) {
        $env:PATH = ($prepend -join ';') + ';' + $env:PATH
    }
}
