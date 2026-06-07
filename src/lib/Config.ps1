<#
.SYNOPSIS Wczytuje konfiguracje z pliku JSON. Zwraca pusty PSCustomObject jesli brak.
#>
function Read-Config {
    param(
        [string]$Path,
        [hashtable]$Default = @{}
    )
    if (Test-Path $Path) {
        try {
            return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {}
    }
    return [PSCustomObject]$Default
}

<#
.SYNOPSIS Zapisuje hashtable jako JSON do pliku.
#>
function Save-Config {
    param(
        [string]$Path,
        [hashtable]$Data
    )
    try {
        $dir = Split-Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        [PSCustomObject]$Data | ConvertTo-Json -Depth 10 | Set-Content $Path -Encoding UTF8
    } catch {
        Write-Host "  [!] Nie udalo sie zapisac konfiguracji: $_" -ForegroundColor DarkYellow
    }
}

<#
.SYNOPSIS Aktualizuje pojedyncza wartosc w konfiguracji (zachowuje pozostale).
#>
function Update-Config {
    param(
        [string]$Path,
        [string]$Key,
        $Value
    )
    $cfg = Read-Config -Path $Path -Default @{}
    $ht  = @{}
    foreach ($p in $cfg.PSObject.Properties) { $ht[$p.Name] = $p.Value }
    $ht[$Key] = $Value
    Save-Config -Path $Path -Data $ht
}
