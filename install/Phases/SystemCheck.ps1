function Invoke-SystemCheck {
    Write-Step "[1/5] Sprawdzanie systemu..."

    $winVer = [System.Environment]::OSVersion.Version
    if ($winVer.Major -lt 10) {
        Write-Missing "Wymagany Windows 10 lub nowszy (masz: $winVer)"
        exit 1
    }
    Write-OK "Windows $($winVer.Major).$($winVer.Minor) build $($winVer.Build)"
    Write-OK "PowerShell $($PSVersionTable.PSVersion)"

    if (Test-Command "winget") {
        Write-OK "winget (Microsoft Package Manager)"
    } else {
        Write-Skip "winget nieobecny — niektóre zależności trzeba zainstalować ręcznie"
        Write-Info "Pobierz App Installer z Microsoft Store, lub: https://aka.ms/getwinget"
    }
}
