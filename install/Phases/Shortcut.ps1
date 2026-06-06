function Invoke-Shortcut {
    param([string]$InstallDir, [switch]$NoShortcut)

    Write-Step "[5/5] Tworzenie skrótów..."

    if ($NoShortcut) {
        Write-Skip "NoShortcut — pominięto"
        return
    }

    try {
        $shortcutPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Zarządzanie transkrypcją.lnk"
        $managerPath  = Join-Path $InstallDir "Manager.ps1"
        $newArgs      = "-ExecutionPolicy Bypass -File `"$managerPath`""
        $wsh          = New-Object -ComObject WScript.Shell

        $existed     = Test-Path $shortcutPath
        $needsUpdate = $true

        if ($existed) {
            $existing = $wsh.CreateShortcut($shortcutPath)
            if ($existing.Arguments -eq $newArgs -and $existing.WorkingDirectory -eq $InstallDir) {
                $needsUpdate = $false
            }
        }

        if ($existed -and -not $needsUpdate) {
            Write-Skip "Skrót już istnieje i wskazuje na $InstallDir (bez zmian)"
            return
        }

        $sc = $wsh.CreateShortcut($shortcutPath)
        $sc.TargetPath       = "powershell.exe"
        $sc.Arguments        = $newArgs
        $sc.WorkingDirectory = $InstallDir
        $sc.Description      = "Transcription Manager"
        $sc.WindowStyle      = 1
        $sc.Save()

        if ($existed) {
            Write-OK "Skrót zaktualizowany (wskazywał na inny folder)"
        } else {
            Write-OK "Skrót Start Menu utworzony: 'Zarządzanie transkrypcją'"
        }
    } catch {
        Write-Missing "Nie udało się utworzyć skrótu: $_"
    }
}
