function Get-InstallMode {
    <#
    .SYNOPSIS Pyta o jeden globalny tryb instalacji wszystkich zaleznosci: portable albo systemowo.
    .DESCRIPTION Zwraca 'portable' (calosc w folderze instalacji, nie rusza systemu, latwo usunac) albo 'system' (winget/pip, globalnie). Bez sesji interaktywnej zwraca 'portable'.
    .EXAMPLE $mode = Get-InstallMode
    #>
    $interactive = $true
    try { $interactive = [Environment]::UserInteractive } catch {}
    if (-not $interactive) { return 'portable' }

    $opts = @(
        'Portable  - calosc w folderze instalacji (nie rusza systemu, latwo usunac)',
        'Systemowo - przez winget/pip, dostepne globalnie w systemie'
    )
    $sel = Ask-Choice -Question 'Jak zainstalowac zaleznosci?' -Options $opts -Default 0
    if ($sel -eq 1) { return 'system' } else { return 'portable' }
}

function Get-DepTasks {
    <#
    .SYNOPSIS Buduje liste zadan instalacji wg jednego globalnego trybu; 'reuse' dla zaleznosci juz obecnych w wybranym trybie.
    .PARAMETER Ctx Kontekst instalacji (Deps, PortablePresent, Total).
    .EXAMPLE $tasks = Get-DepTasks -Ctx $ctx
    #>
    param([hashtable]$Ctx)
    $deps = $Ctx.Deps
    $portablePresent = $Ctx.PortablePresent

    $allPresent = $true
    foreach ($dep in $deps) {
        if (-not ($dep.Test() -or $portablePresent[$dep.Name])) { $allPresent = $false; break }
    }

    $tasks = @()
    if ($allPresent) {
        Write-Step "[4/$($Ctx.Total)] Zaleznosci aktualne"
        foreach ($dep in $deps) { $tasks += @{ Dep = $dep; Mode = 'reuse'; ZipDest = $null } }
        return $tasks
    }

    Write-Step "[4/$($Ctx.Total)] Instalowanie zaleznosci..."
    $mode = Get-InstallMode
    foreach ($dep in $deps) {
        $presentInMode = if ($mode -eq 'portable') { $portablePresent[$dep.Name] } else { $dep.Test() }
        $taskMode = if ($presentInMode) { 'reuse' } else { $mode }
        $tasks += @{ Dep = $dep; Mode = $taskMode; ZipDest = $null }
    }
    return $tasks
}
