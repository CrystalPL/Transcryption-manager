function Invoke-ReuseSystemPhase {
    <#
    .SYNOPSIS Obsluguje zadania 'reuse' (wpis manifestu) i 'system' (instalacja przez klase). Zwraca zadanie whispera-portable do osobnej fazy.
    .PARAMETER Ctx Kontekst instalacji.
    .PARAMETER Tasks Lista zadan.
    #>
    param([hashtable]$Ctx, [object[]]$Tasks)
    $st = $Ctx.St
    $whisperTask = $null

    foreach ($t in $Tasks) {
        $dep = $t.Dep; $name = $dep.Name
        switch ($t.Mode) {
            'reuse' {
                if ($Ctx.PortablePresent[$dep.Name]) {
                    $Ctx.Manifest[$dep.Command] = $dep.ManifestEntry('portable', $Ctx.RuntimeDir, $Ctx.InstallDir)
                    $Ctx.NeedRuntime = $true
                } else {
                    $Ctx.Manifest[$dep.Command] = $dep.ManifestEntry('system', $Ctx.RuntimeDir, $Ctx.InstallDir)
                }
            }
            'system' {
                $st[$name].Phase = 'inst'; $st[$name].StartedAt = Get-Date
                Show-DepRow $Ctx $name
                $ok = & { $dep.Install() } 6>$null
                $st[$name].Phase = if ($ok) { 'ok' } else { 'err' }
                Show-DepRow $Ctx $name
                if ($ok) { $Ctx.Manifest[$dep.Command] = $dep.ManifestEntry('system', $Ctx.RuntimeDir, $Ctx.InstallDir) }
            }
            'portable' {
                if ($name -eq 'whisper') { $whisperTask = $t }
            }
        }
    }
    return $whisperTask
}

function Invoke-PortableExtractPhase {
    <#
    .SYNOPSIS Rozpakowuje portable Python/ffmpeg/mkvmerge w tle (Start-TrackedJob) z twardym timeoutem.
    .PARAMETER Ctx Kontekst instalacji.
    .PARAMETER Tasks Lista zadan.
    #>
    param([hashtable]$Ctx, [object[]]$Tasks)
    $st = $Ctx.St
    $portableJobs = @{}

    foreach ($t in $Tasks) {
        $dep = $t.Dep; $name = $dep.Name
        if ($t.Mode -ne 'portable' -or $name -eq 'whisper') { continue }
        if ($st[$name].Phase -eq 'err') { continue }

        if (-not (Test-Path $Ctx.RuntimeDir)) { New-Item -ItemType Directory -Path $Ctx.RuntimeDir -Force | Out-Null }

        $sb = Get-PortableExtractor -Name $name
        if (-not $sb) { continue }

        $st[$name].Phase = 'inst'; $st[$name].StartedAt = Get-Date
        Show-DepRow $Ctx $name

        $portableJobs[$name] = @{ Tracked = (Start-TrackedJob -ScriptBlock $sb -ArgumentList @($t.ZipDest, $Ctx.RuntimeDir)); Dep = $dep; Start = (Get-Date) }
    }
    [Console]::SetCursorPosition(0, $Ctx.AfterRow)

    $portDone = @{}
    while (@($portableJobs.Keys | Where-Object { -not $portDone[$_] }).Count -gt 0) {
        foreach ($nm in @($portableJobs.Keys)) {
            if ($portDone[$nm]) { continue }
            $pj  = $portableJobs[$nm]
            $ij  = $pj.Tracked.Job
            $dep = $pj.Dep

            if ($ij.State -eq 'Running') {
                if ((((Get-Date) - $pj.Start).TotalSeconds) -ge $Ctx.Timeouts.Extract) {
                    Stop-TrackedJob -Tracked $pj.Tracked
                    $st[$nm].Phase = 'err'
                    $portDone[$nm] = $true
                }
            } else {
                $result = Receive-Job -Job $ij -ErrorAction SilentlyContinue
                $ok     = ($ij.State -ne 'Failed') -and ($result -eq $true)
                Stop-TrackedJob -Tracked $pj.Tracked
                $st[$nm].Phase = if ($ok) { 'ok' } else { 'err' }
                if ($ok) {
                    $Ctx.Manifest[$dep.Command] = $dep.ManifestEntry('portable', $Ctx.RuntimeDir, $Ctx.InstallDir)
                    $Ctx.NeedRuntime = $true
                }
                $portDone[$nm] = $true
            }
            Show-DepRow $Ctx $nm
        }
        Start-Sleep -Milliseconds 400
    }
    [Console]::SetCursorPosition(0, $Ctx.AfterRow)
}
