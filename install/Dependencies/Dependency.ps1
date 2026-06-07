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

    [bool] InstallPortable([string]$RuntimeDir) {
        Write-Host "        [FAIL] $($this.GetType().Name) nie wspiera trybu portable" -ForegroundColor Red
        return $false
    }

    [string] GetPortableZipUrl() { return $null }

    [string] GetPortableTempPath() { return "" }

    [bool] InstallFromZip([string]$ZipPath, [string]$RuntimeDir) {
        return $this.InstallPortable($RuntimeDir)
    }

    [hashtable] ManifestEntry([string]$Mode, [string]$RuntimeDir, [string]$InstallDir) {
        if ($Mode -eq 'portable') {
            return @{ mode = 'portable'; path = $this.Command }
        }
        return @{ mode = 'system'; path = $this.Command }
    }

    [string] RelPath([string]$FullPath, [string]$InstallDir) {
        $root = $InstallDir.TrimEnd('\')
        if ($FullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $FullPath.Substring($root.Length).TrimStart('\')
        }
        return $FullPath
    }
}
