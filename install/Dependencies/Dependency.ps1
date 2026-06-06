class Dependency {
    [string] $Name
    [string] $Command
    [bool]   $Required = $true
    [bool]   $SupportsPortable = $false

    [bool] Test() {
        return $null -ne (Get-Command $this.Command -ErrorAction SilentlyContinue)
    }

    [bool] Install() {
        Write-Host "        [FAIL] Klasa $($this.GetType().Name) nie implementuje Install()" -ForegroundColor Red
        return $false
    }

    # Liskov: domyslnie brak wsparcia portable -> zwraca false, nie rzuca.
    # Klasy wspierajace portable nadpisuja.
    [bool] InstallPortable([string]$RuntimeDir) {
        Write-Host "        [FAIL] $($this.GetType().Name) nie wspiera trybu portable" -ForegroundColor Red
        return $false
    }

    # Wpis do runtime.json. portable -> sciezka relatywna do roota instalacji,
    # system -> gola nazwa polecenia (rozwiazywana przez PATH).
    # Bazowa wersja zwraca system; klasy z portable nadpisuja sciezki portable.
    [hashtable] ManifestEntry([string]$Mode, [string]$RuntimeDir, [string]$InstallDir) {
        if ($Mode -eq 'portable') {
            return @{ mode = 'portable'; path = $this.Command }
        }
        return @{ mode = 'system'; path = $this.Command }
    }

    # Helper dla klas pochodnych: zamien absolutna sciezke pliku na relatywna do roota instalacji.
    [string] RelPath([string]$FullPath, [string]$InstallDir) {
        $root = $InstallDir.TrimEnd('\')
        if ($FullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $FullPath.Substring($root.Length).TrimStart('\')
        }
        return $FullPath
    }
}
