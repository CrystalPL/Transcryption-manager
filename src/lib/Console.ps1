function Get-ConsoleWidth {
    return [Math]::Max(72, [Console]::WindowWidth - 1)
}

<#
.SYNOPSIS Rysuje naglowek aplikacji z tytulem i opcjonalnym podtytulem.
#>
function Show-Header {
    param(
        [string]$Title,
        [string]$Krok = "",
        [string]$Subtitle = ""
    )
    $w = Get-ConsoleWidth
    $b = "-" * ($w - 4)
    Clear-Host
    Write-Host ""
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host (Fit "  | $Title  $Krok" $w) -ForegroundColor Cyan
    Write-Host (Fit "  +$b+" $w) -ForegroundColor DarkCyan
    Write-Host ""
    if ($Subtitle) {
        Write-Host (Fit "  $Subtitle" $w) -ForegroundColor White
        Write-Host (Fit ("  " + "-" * ($w - 2)) $w) -ForegroundColor DarkGray
    }
    Write-Host ""
}

<#
.SYNOPSIS Interaktywne pytanie T/N. Enter = wybor domyslny.
#>
function Ask-TakNie {
    param(
        [string]$Question,
        [bool]$DefaultYes = $true   # zachowane dla kompatybilnosci, nie uzywane
    )
    Write-Host ""
    Write-Host "  $Question [T/N] " -ForegroundColor Yellow -NoNewline
    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = [char]::ToLower($k.KeyChar)
        if ($c -eq 't' -or $c -eq 'y') { Write-Host "Tak" -ForegroundColor Green; return $true  }
        if ($c -eq 'n')                 { Write-Host "Nie" -ForegroundColor Red;   return $false }
    }
}

<#
.SYNOPSIS Czyta decyzje z ekranu podsumowania: T/Enter=start, W=back, Q/Esc=cancel.
.DESCRIPTION Blokuje az do nacisniecia rozpoznanego klawisza. Zwraca string
'start' | 'back' | 'cancel'. Pozostale klawisze ignorowane.
#>
function Read-StartBackCancel {
    $decision = $null
    while (-not $decision) {
        $k = [Console]::ReadKey($true)
        $c = [char]::ToLower($k.KeyChar)
        if ($c -eq 't' -or $k.Key -eq 'Enter') { $decision = 'start'  }
        elseif ($c -eq 'w')                     { $decision = 'back'   }
        elseif ($c -eq 'q' -or $k.Key -eq 'Escape') { $decision = 'cancel' }
    }
    return $decision
}

