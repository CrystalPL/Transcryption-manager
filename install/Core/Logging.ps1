function Write-Step    { param($Msg) Write-Host "`n  $Msg" -ForegroundColor Cyan }
function Write-OK      { param($Msg) Write-Host "        [OK]   $Msg" -ForegroundColor Green }
function Write-Skip    { param($Msg) Write-Host "        [--]   $Msg" -ForegroundColor DarkYellow }
function Write-Missing { param($Msg) Write-Host "        [BRAK] $Msg" -ForegroundColor Red }
function Write-Info    { param($Msg) Write-Host "        $Msg"        -ForegroundColor DarkGray }

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}
