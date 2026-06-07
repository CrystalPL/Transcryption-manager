function Save-RuntimeManifest {
    <#
    .SYNOPSIS Zapisuje runtime.json z mapy manifestu i pokazuje ostrzezenie o PATH gdy nic portable nie zainstalowano.
    .PARAMETER Ctx Kontekst instalacji.
    .PARAMETER InstallTaskCount Liczba zadan innych niz 'reuse' (do komunikatu).
    #>
    param([hashtable]$Ctx, [int]$InstallTaskCount)
    if ($Ctx.Manifest.Count -gt 0) {
        $runtimeFile = Join-Path $Ctx.InstallDir "runtime.json"
        [PSCustomObject]$Ctx.Manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $runtimeFile -Encoding UTF8
        if ($InstallTaskCount -gt 0) { Write-OK "Zapisano manifest: $runtimeFile" }
    }

    if (-not $Ctx.NeedRuntime) {
        Write-Host "`n  UWAGA: narzedzia systemowe moga wymagac restartu PowerShella," -ForegroundColor Yellow
        Write-Host "         zeby pojawily sie w PATH." -ForegroundColor Yellow
    }
}
