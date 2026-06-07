function Invoke-DownloadPhase {
    <#
    .SYNOPSIS Pobiera archiwa portable rownolegle (Start-TrackedJob) z detekcja zastoju i twardym timeoutem.
    .PARAMETER Ctx Kontekst instalacji.
    .PARAMETER Tasks Lista zadan.
    #>
    param([hashtable]$Ctx, [object[]]$Tasks)
    $st = $Ctx.St
    $dlJobs = @{}

    foreach ($t in $Tasks) {
        if ($t.Mode -ne 'portable') { continue }
        $url = $t.Dep.GetPortableZipUrl()
        if (-not $url) { continue }
        $dest = $t.Dep.GetPortableTempPath()
        $t.ZipDest = $dest

        try {
            $req = [System.Net.WebRequest]::Create($url)
            $req.Method = 'HEAD'; $req.Timeout = 8000
            $resp = $req.GetResponse()
            $st[$t.Dep.Name].TotalBytes = $resp.ContentLength
            $resp.Close()
        } catch {}

        $st[$t.Dep.Name].Phase = 'dl'
        Show-DepRow $Ctx $t.Dep.Name

        $captUrl = $url; $captDest = $dest
        $tracked = Start-TrackedJob -ScriptBlock {
            param($u, $d)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            (New-Object System.Net.WebClient).DownloadFile($u, $d)
        } -ArgumentList @($captUrl, $captDest)
        $dlJobs[$t.Dep.Name] = @{ Tracked = $tracked; Dest = $dest; Start = (Get-Date); LastSize = -1L; LastChange = (Get-Date) }
    }

    if ($dlJobs.Count -eq 0) { return }

    $dlStart = Get-Date
    $dlDone  = @{}
    while (@($dlJobs.Keys | Where-Object { -not $dlDone[$_] }).Count -gt 0) {
        $elapsed    = [int]((Get-Date) - $dlStart).TotalSeconds
        $elapsedStr = "{0}:{1:D2}" -f [int]($elapsed / 60), ($elapsed % 60)
        foreach ($nm in @($dlJobs.Keys)) {
            if ($dlDone[$nm]) { continue }
            $info = $dlJobs[$nm]
            $djob = $info.Tracked.Job
            $now  = Get-Date

            if ($djob.State -eq 'Running') {
                $dl  = if (Test-Path $info.Dest) { (Get-Item $info.Dest).Length } else { 0L }
                $tot = $st[$nm].TotalBytes
                $st[$nm].DlBytes = $dl
                $st[$nm].Pct     = if ($tot -gt 0) { [int]($dl * 100 / $tot) } else { 0 }

                if ($dl -ne $info.LastSize) { $info.LastSize = $dl; $info.LastChange = $now }
                $stalled = (($now - $info.LastChange).TotalSeconds) -ge $Ctx.Timeouts.DlStall
                $expired = (($now - $info.Start).TotalSeconds) -ge $Ctx.Timeouts.DlTimeout
                if ($stalled -or $expired) {
                    Stop-TrackedJob -Tracked $info.Tracked
                    $st[$nm].Phase = 'err'
                    $dlDone[$nm] = $true
                }
            } else {
                $null = Receive-Job -Job $djob -ErrorAction SilentlyContinue
                if ($djob.State -eq 'Failed') {
                    $st[$nm].Phase = 'err'
                } else {
                    $dl = if (Test-Path $info.Dest) { (Get-Item $info.Dest).Length } else { $st[$nm].TotalBytes }
                    $st[$nm].DlBytes  = $dl
                    if ($st[$nm].TotalBytes -eq 0L) { $st[$nm].TotalBytes = $dl }
                    $st[$nm].Pct   = 100
                    $st[$nm].Phase = 'wait-in'
                }
                Stop-TrackedJob -Tracked $info.Tracked
                $dlDone[$nm] = $true
            }
            Show-DepRow $Ctx $nm
        }
        [Console]::SetCursorPosition(0, $Ctx.TimerRow)
        Write-Host ("  Czas pobierania: $elapsedStr").PadRight($Ctx.W - 1) -ForegroundColor DarkGray -NoNewline
        Start-Sleep -Milliseconds 300
    }

    [Console]::SetCursorPosition(0, $Ctx.TimerRow)
    Write-Host (" " * ($Ctx.W - 1)) -NoNewline
    [Console]::SetCursorPosition(0, $Ctx.AfterRow)
}
