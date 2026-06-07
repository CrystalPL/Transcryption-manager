function Write-DepsRow {
    param([hashtable]$Row, [bool]$IsSelected, [int]$Width, [hashtable]$Labels)
    $marker   = if ($IsSelected) { "> " } else { "  " }
    $name     = $Row.Dep.Name.PadRight(12)
    $stateStr = if ($Row.Detected) { "wykryto" } elseif ($Row.HasPortable) { "portable" } else { "brak" }
    $state    = $stateStr.PadRight(10)
    $mode     = $Labels[$Row.Modes[$Row.Idx]]
    $modeStr  = "[ <- $($mode.PadRight(16)) -> ]"
    $line     = "  $marker $name  $state  $modeStr"
    $color    = if ($IsSelected) { 'Cyan' } else { 'White' }
    Write-Host $line.PadRight($Width - 1) -ForegroundColor $color -NoNewline
    Write-Host ""
}

function Show-DepsConfig {
    param([object[]]$Deps, [hashtable]$PortablePresent = @{})

    $labels = @{ reuse = 'Zachowaj'; system = 'Systemowo'; portable = 'Portable' }

    $rows = @()
    foreach ($dep in $Deps) {
        $detected  = $dep.Test()
        $hasPortable = $PortablePresent[$dep.Name] -eq $true
        $modes = if ($dep.SupportsPortable) {
            if ($hasPortable -or $detected) { @('reuse', 'system', 'portable') } else { @('system', 'portable') }
        } else {
            if ($detected) { @('reuse', 'system') } else { @('system') }
        }
        $rows += @{ Dep = $dep; Detected = $detected; HasPortable = $hasPortable; Modes = $modes; Idx = 0 }
    }

    $sel = 0
    $w   = [Console]::WindowWidth
    $sep = "  " + ("-" * ([Math]::Min($w - 4, 58)))

    Write-Host ""
    Write-Host "  Konfiguracja zaleznosci:" -ForegroundColor Cyan
    Write-Host "  (strzalki gora/dol: wybierz   lewo/prawo: zmien tryb   Enter: zatwierdz)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("  {0,-14}  {1,-10}  {2}" -f "Komponent", "Status", "Tryb instalacji") -ForegroundColor DarkGray
    Write-Host $sep -ForegroundColor DarkGray

    $dataRow = [Console]::CursorTop
    for ($i = 0; $i -lt $rows.Count; $i++) { Write-Host "" }
    Write-Host $sep -ForegroundColor DarkGray

    for ($i = 0; $i -lt $rows.Count; $i++) {
        [Console]::SetCursorPosition(0, $dataRow + $i)
        Write-DepsRow $rows[$i] ($i -eq $sel) $w $labels
    }
    [Console]::SetCursorPosition(0, $dataRow + $rows.Count + 1)

    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') { break }

        $prevSel = $sel
        if ($k.Key -eq 'UpArrow')    { $sel = [Math]::Max(0, $sel - 1) }
        if ($k.Key -eq 'DownArrow')  { $sel = [Math]::Min($rows.Count - 1, $sel + 1) }
        if ($k.Key -eq 'LeftArrow') {
            $rows[$sel].Idx = ($rows[$sel].Idx - 1 + $rows[$sel].Modes.Count) % $rows[$sel].Modes.Count
        }
        if ($k.Key -eq 'RightArrow') {
            $rows[$sel].Idx = ($rows[$sel].Idx + 1) % $rows[$sel].Modes.Count
        }

        if ($prevSel -ne $sel) {
            [Console]::SetCursorPosition(0, $dataRow + $prevSel)
            Write-DepsRow $rows[$prevSel] $false $w $labels
        }
        [Console]::SetCursorPosition(0, $dataRow + $sel)
        Write-DepsRow $rows[$sel] $true $w $labels
        [Console]::SetCursorPosition(0, $dataRow + $rows.Count + 1)
    }

    Write-Host ""
    $result = [System.Collections.ArrayList]::new()
    foreach ($r in $rows) {
        [void]$result.Add(@{ Dep = $r.Dep; Mode = $r.Modes[$r.Idx]; ZipDest = $null })
    }
    return $result
}

function Format-DownloadSize([long]$bytes) {
    if ($bytes -ge 1MB) { return "{0:F1} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:F0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Render-ProgressRow {
    param([string]$Name, [hashtable]$St, [int]$W)
    $bw    = 20
    $label = ""
    $bar   = "[" + (" " * $bw) + "]"
    $info  = ""
    $color = 'DarkGray'

    switch ($St.Phase) {
        'skip' {
            $label = "Zachowany"
            $bar   = "[" + ("=" * $bw) + "]"
            $color = 'DarkGreen'
        }
        'wait-dl' { $label = "Oczekuje" }
        'wait-in' { $label = "Oczekuje" }
        'dl' {
            $label  = if ($St.DlBytes -gt 0) { "Pobieranie" } else { "Laczenie" }
            $filled = [Math]::Min($bw, [int]($St.Pct * $bw / 100))
            $bar    = "[" + ("=" * $filled) + (" " * ($bw - $filled)) + "]"
            $dlStr  = Format-DownloadSize $St.DlBytes
            $totStr = if ($St.TotalBytes -gt 0) { Format-DownloadSize $St.TotalBytes } else { "??" }
            $info   = " $("{0,3}" -f $St.Pct)%  $("{0,8}" -f $dlStr) / $totStr"
            $color  = 'White'
        }
        'inst' {
            $label   = "Instalowanie"
            $elapsed = if ($St.StartedAt) { [int]((Get-Date) - $St.StartedAt).TotalSeconds } else { 0 }
            $info    = " $($elapsed)s"
            $color   = 'Yellow'
        }
        'pip' {
            $label   = "pip install"
            $elapsed = if ($St.StartedAt) { [int]((Get-Date) - $St.StartedAt).TotalSeconds } else { 0 }
            $min     = [int]($elapsed / 60)
            $sec     = $elapsed % 60
            $timeStr = if ($St.StartedAt) { if ($min -gt 0) { " ${min}m ${sec}s" } else { " ${sec}s" } } else { " ~10-20 min" }
            $pipLine = if ($St.LastLine) { "  $($St.LastLine)" } else { "" }
            $info    = $timeStr + $pipLine
            $color   = 'Yellow'
        }
        'ok' {
            $label  = "Gotowe"
            $bar    = "[" + ("=" * $bw) + "]"
            $sz     = if ($St.TotalBytes -gt 0) { Format-DownloadSize $St.TotalBytes } else { "" }
            $info   = if ($sz) { " $sz" } else { "" }
            $color  = 'Green'
        }
        'err' {
            $label = "Blad!"
            $bar   = "[" + ("!" * $bw) + "]"
            $color = 'Red'
        }
    }

    $line     = "  {0,-10} {1,-12} {2}{3}" -f $Name, $label, $bar, $info
    $rendered = if ($line.Length -gt $W - 1) { $line.Substring(0, $W - 1) } else { $line.PadRight($W - 1) }
    Write-Host $rendered -ForegroundColor $color -NoNewline
    Write-Host ""
}

function Test-RealPython {
    $cmd = Get-Command "python" -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    if ($cmd.Source -like "*\Microsoft\WindowsApps\*") { return $false }
    return $true
}

function Test-AllDepsPresent([string]$InstallDir) {
    $RuntimeDir = Join-Path $InstallDir "runtime"
    $portableExes = @{
        'Python'   = Join-Path $RuntimeDir "python\python.exe"
        'ffmpeg'   = Join-Path $RuntimeDir "ffmpeg\bin\ffmpeg.exe"
        'mkvmerge' = Join-Path $RuntimeDir "mkvtoolnix\mkvmerge.exe"
        'whisper'  = Join-Path $RuntimeDir "python\Scripts\whisper.exe"
    }
    $deps = @([PythonDependency]::new(), [FfmpegDependency]::new(), [MkvmergeDependency]::new(), [WhisperDependency]::new())
    foreach ($d in $deps) {
        $present = (Test-Path $portableExes[$d.Name])
        if (-not $present -and $d.Name -ne 'Python') { $present = $d.Test() }
        if (-not $present -and $d.Name -eq 'Python') { $present = Test-RealPython }
        if (-not $present) { return $false }
    }
    return $true
}

function Invoke-Dependencies {
    param(
        [switch]$NoDeps,
        [string]$InstallDir,
        [string]$LogDir,
        [int]$Total = 5
    )
    if (-not $LogDir) { $LogDir = $env:TEMP }

    $deps = @(
        [PythonDependency]::new(),
        [FfmpegDependency]::new(),
        [MkvmergeDependency]::new(),
        [WhisperDependency]::new()
    )

    $RuntimeDir  = Join-Path $InstallDir "runtime"
    $manifest    = @{}
    $needRuntime = $false

    $portableExePaths = @{
        'Python'   = Join-Path $RuntimeDir "python\python.exe"
        'ffmpeg'   = Join-Path $RuntimeDir "ffmpeg\bin\ffmpeg.exe"
        'mkvmerge' = Join-Path $RuntimeDir "mkvtoolnix\mkvmerge.exe"
        'whisper'  = Join-Path $RuntimeDir "python\Scripts\whisper.exe"
    }
    $portablePresent = @{}
    foreach ($dep in $deps) {
        $exe = $portableExePaths[$dep.Name]
        $portablePresent[$dep.Name] = ($null -ne $exe -and (Test-Path $exe))
    }

    Write-Step "[3/$Total] Sprawdzanie zaleznosci..."
    foreach ($d in $deps) {
        if ($d.Test() -or $portablePresent[$d.Name]) { Write-OK $d.Name } else { Write-Missing $d.Name }
    }

    if (Test-Command "nvidia-smi") {
        try {
            $gpuName = (& nvidia-smi --query-gpu=name --format=csv,noheader | Select-Object -First 1).Trim()
            Write-OK "GPU NVIDIA: $gpuName"
        } catch { Write-OK "GPU NVIDIA wykryta" }
    } else {
        Write-Skip "Brak GPU NVIDIA (CUDA) — Whisper bedzie dzialal na CPU (znacznie wolniej)"
    }

    if ($NoDeps) {
        Write-Step "[4/$Total] Instalacja zaleznosci pominieta (-NoDeps)"
        return
    }

    $autoTasks  = [System.Collections.ArrayList]::new()
    $configDeps = @()
    foreach ($dep in $deps) {
        if ($dep.Test() -or $portablePresent[$dep.Name]) {
            [void]$autoTasks.Add(@{ Dep = $dep; Mode = 'reuse'; ZipDest = $null })
        } else {
            $configDeps += $dep
        }
    }

    if ($configDeps.Count -gt 0) {
        Write-Step "[4/$Total] Instalowanie zaleznosci..."
        $userTasks = Show-DepsConfig $configDeps $portablePresent
        $tasks = @($autoTasks) + @($userTasks)
    } else {
        Write-Step "[4/5] Zaleznosci aktualne"
        $tasks = @($autoTasks)
    }

    $sbPython = {
        param($zipPath, $runtimeDir)
        try {
            $dest = Join-Path $runtimeDir "python"
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Expand-Archive -Path $zipPath -DestinationPath $dest -Force
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

            $pth = Get-ChildItem $dest -Filter "python3*._pth" | Select-Object -First 1
            if ($pth) {
                $lines = [System.IO.File]::ReadAllLines($pth.FullName)
                $out = foreach ($l in $lines) {
                    if ($l.Trim() -eq '#import site') { 'import site' } else { $l }
                }
                [System.IO.File]::WriteAllLines($pth.FullName, $out)
            }

            $py = Join-Path $dest "python.exe"
            if (-not (Test-Path $py)) { return $false }

            $env:PYTHONHOME = $null
            $env:PYTHONPATH = $null
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $getpip = Join-Path $env:TEMP "tm-get-pip.py"
            (New-Object System.Net.WebClient).DownloadFile("https://bootstrap.pypa.io/get-pip.py", $getpip)
            & $py $getpip --no-warn-script-location 2>&1 | Out-Null
            Remove-Item $getpip -Force -ErrorAction SilentlyContinue

            [System.IO.File]::WriteAllText(
                (Join-Path $dest "pip.ini"),
                "[install]`nno-build-isolation = true`n"
            )

            return ((Test-Path (Join-Path $dest "Scripts\pip.exe")) -or
                    (Test-Path (Join-Path $dest "Lib\site-packages\pip")))
        } catch { return $false }
    }

    $sbFfmpeg = {
        param($zipPath, $runtimeDir)
        try {
            $dest    = Join-Path $runtimeDir "ffmpeg"
            $tmp     = Join-Path $env:TEMP "tm-ffmpeg-x"
            if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
            Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            $binSrc  = Get-ChildItem $tmp -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
            if (-not $binSrc) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; return $false }
            $destBin = Join-Path $dest "bin"
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            New-Item -ItemType Directory -Path $destBin -Force | Out-Null
            Copy-Item (Join-Path (Split-Path $binSrc.FullName -Parent) "*.exe") -Destination $destBin -Force
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            return (Test-Path (Join-Path $destBin "ffmpeg.exe"))
        } catch { return $false }
    }

    $sbMkvmerge = {
        param($zipPath, $runtimeDir)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            if (-not $zipPath -or -not (Test-Path $zipPath)) {
                $ver = $null
                try {
                    $resp = Invoke-RestMethod -Uri "https://gitlab.com/api/v4/projects/mbunkus%2Fmkvtoolnix/releases?per_page=1" -UseBasicParsing
                    $tag  = if ($resp -and $resp.Count -gt 0) { $resp[0].tag_name } else { $null }
                    $v    = if ($tag) { $tag -replace '^release-', '' } else { $null }
                    if ($v -match '^\d') { $ver = $v }
                } catch {}
                if (-not $ver) {
                    try {
                        $page = Invoke-WebRequest -Uri "https://mkvtoolnix.download/downloads.html" -UseBasicParsing
                        $m    = [regex]::Match($page.Content, 'mkvtoolnix-64-bit-([\d.]+)\.7z')
                        if ($m.Success) { $ver = $m.Groups[1].Value }
                    } catch {}
                }
                if (-not $ver) { return $false }
                $zipPath = Join-Path $env:TEMP "tm-mkvtoolnix.7z"
                (New-Object System.Net.WebClient).DownloadFile(
                    "https://mkvtoolnix.download/windows/releases/$ver/mkvtoolnix-64-bit-$ver.7z",
                    $zipPath)
            }

            $dest   = Join-Path $runtimeDir "mkvtoolnix"
            $tmpExt = Join-Path $env:SystemDrive "tm-mkv-x"
            $7zrExe = Join-Path $env:TEMP "tm-7zr.exe"

            if (-not (Test-Path $7zrExe)) {
                (New-Object System.Net.WebClient).DownloadFile("https://www.7-zip.org/a/7zr.exe", $7zrExe)
            }
            if (Test-Path $tmpExt) { Remove-Item $tmpExt -Recurse -Force }
            New-Item -ItemType Directory -Path $tmpExt -Force | Out-Null

            & $7zrExe x $zipPath "-o$tmpExt" -y 2>&1 | Out-Null
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item $7zrExe  -Force -ErrorAction SilentlyContinue

            $binSrc = Get-ChildItem $tmpExt -Recurse -Filter "mkvmerge.exe" | Select-Object -First 1
            if (-not $binSrc) { Remove-Item $tmpExt -Recurse -Force -ErrorAction SilentlyContinue; return $false }

            $binDir = Split-Path $binSrc.FullName -Parent
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Copy-Item (Join-Path $binDir "*") -Destination $dest -Recurse -Force
            Remove-Item $tmpExt -Recurse -Force -ErrorAction SilentlyContinue

            return (Test-Path (Join-Path $dest "mkvmerge.exe"))
        } catch { return $false }
    }


    $w   = [Console]::WindowWidth
    $sep = "  " + ("-" * [Math]::Min($w - 4, 62))

    $installTasks = @($tasks | Where-Object { $_.Mode -ne 'reuse' })

    $st       = @{}
    $rowOf    = @{}
    $tableRow = 0
    $timerRow = 0
    $afterRow = [Console]::CursorTop

    if ($installTasks.Count -gt 0) {
        Write-Host ""
        Write-Host "  Instalowanie skladnikow..." -ForegroundColor Cyan
        Write-Host ""
        Write-Host ("  {0,-10} {1,-12}  {2}" -f "Komponent", "Status", "Postep") -ForegroundColor DarkGray
        Write-Host $sep -ForegroundColor DarkGray

        $tableRow = [Console]::CursorTop
        $ri       = 0

        foreach ($t in $installTasks) {
            $st[$t.Dep.Name] = @{ Phase = 'wait-dl'; Pct = 0; DlBytes = 0L; TotalBytes = 0L; StartedAt = $null }
            $rowOf[$t.Dep.Name] = $ri; $ri++
            Write-Host ""
        }

        Write-Host $sep -ForegroundColor DarkGray
        $timerRow = [Console]::CursorTop; Write-Host ""
        $afterRow = [Console]::CursorTop

        foreach ($t in $installTasks) {
            [Console]::SetCursorPosition(0, $tableRow + $rowOf[$t.Dep.Name])
            Render-ProgressRow $t.Dep.Name $st[$t.Dep.Name] $w
        }
        [Console]::SetCursorPosition(0, $afterRow)
    }

    $dlJobs = @{}

    foreach ($t in $tasks) {
        if ($t.Mode -ne 'portable') { continue }
        $url = $t.Dep.GetPortableZipUrl()
        if (-not $url) { continue }
        $dest      = $t.Dep.GetPortableTempPath()
        $t.ZipDest = $dest

        try {
            $req = [System.Net.WebRequest]::Create($url)
            $req.Method = 'HEAD'; $req.Timeout = 8000
            $resp = $req.GetResponse()
            $st[$t.Dep.Name].TotalBytes = $resp.ContentLength
            $resp.Close()
        } catch {}

        $st[$t.Dep.Name].Phase = 'dl'
        [Console]::SetCursorPosition(0, $tableRow + $rowOf[$t.Dep.Name])
        Render-ProgressRow $t.Dep.Name $st[$t.Dep.Name] $w

        $captUrl  = $url
        $captDest = $dest
        $job = Start-Job -ScriptBlock {
            param($u, $d)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            (New-Object System.Net.WebClient).DownloadFile($u, $d)
        } -ArgumentList $captUrl, $captDest
        $dlJobs[$t.Dep.Name] = @{ Job = $job; Dest = $dest }
    }

    if ($dlJobs.Count -gt 0) {
        $dlStart = Get-Date
        $dlDone  = @{}
        while ($dlJobs.Values | Where-Object { $_.Job.State -eq 'Running' }) {
            $elapsed    = [int]((Get-Date) - $dlStart).TotalSeconds
            $elapsedStr = "{0}:{1:D2}" -f [int]($elapsed / 60), ($elapsed % 60)
            foreach ($nm in $dlJobs.Keys) {
                if ($dlDone[$nm]) { continue }
                $djob = $dlJobs[$nm].Job
                if ($djob.State -eq 'Running') {
                    $dl  = if (Test-Path $dlJobs[$nm].Dest) { (Get-Item $dlJobs[$nm].Dest).Length } else { 0L }
                    $tot = $st[$nm].TotalBytes
                    $st[$nm].DlBytes = $dl
                    $st[$nm].Pct     = if ($tot -gt 0) { [int]($dl * 100 / $tot) } else { 0 }
                } else {
                    $null = Receive-Job -Job $djob -ErrorAction SilentlyContinue
                    if ($djob.State -eq 'Failed') {
                        $st[$nm].Phase = 'err'
                    } else {
                        $dl = if (Test-Path $dlJobs[$nm].Dest) { (Get-Item $dlJobs[$nm].Dest).Length } else { $st[$nm].TotalBytes }
                        $st[$nm].DlBytes  = $dl
                        if ($st[$nm].TotalBytes -eq 0L) { $st[$nm].TotalBytes = $dl }
                        $st[$nm].Pct   = 100
                        $st[$nm].Phase = 'wait-in'
                    }
                    Remove-Job -Job $djob -Force
                    $dlDone[$nm] = $true
                }
                [Console]::SetCursorPosition(0, $tableRow + $rowOf[$nm])
                Render-ProgressRow $nm $st[$nm] $w
            }
            [Console]::SetCursorPosition(0, $timerRow)
            Write-Host ("  Czas pobierania: $elapsedStr").PadRight($w - 1) -ForegroundColor DarkGray -NoNewline
            Start-Sleep -Milliseconds 300
        }

        foreach ($nm in $dlJobs.Keys) {
            if ($dlDone[$nm]) { continue }
            $dj = $dlJobs[$nm]
            $null = Receive-Job -Job $dj.Job -ErrorAction SilentlyContinue
            if ($dj.Job.State -eq 'Failed') {
                $st[$nm].Phase = 'err'
            } else {
                $dl = if (Test-Path $dj.Dest) { (Get-Item $dj.Dest).Length } else { $st[$nm].TotalBytes }
                $st[$nm].DlBytes  = $dl
                if ($st[$nm].TotalBytes -eq 0L) { $st[$nm].TotalBytes = $dl }
                $st[$nm].Pct   = 100
                $st[$nm].Phase = 'wait-in'
            }
            Remove-Job -Job $dj.Job -Force
            [Console]::SetCursorPosition(0, $tableRow + $rowOf[$nm])
            Render-ProgressRow $nm $st[$nm] $w
        }

        [Console]::SetCursorPosition(0, $timerRow)
        Write-Host (" " * ($w - 1)) -NoNewline
    }
    [Console]::SetCursorPosition(0, $afterRow)

    $whisperTask = $null

    foreach ($t in $tasks) {
        $dep  = $t.Dep
        $name = $dep.Name
        switch ($t.Mode) {
            'reuse' {
                if ($portablePresent[$dep.Name]) {
                    $manifest[$dep.Command] = $dep.ManifestEntry('portable', $RuntimeDir, $InstallDir)
                    $needRuntime = $true
                } else {
                    $manifest[$dep.Command] = $dep.ManifestEntry('system', $RuntimeDir, $InstallDir)
                }
            }
            'system' {
                $st[$name].Phase     = 'inst'
                $st[$name].StartedAt = Get-Date
                [Console]::SetCursorPosition(0, $tableRow + $rowOf[$name])
                Render-ProgressRow $name $st[$name] $w
                [Console]::SetCursorPosition(0, $afterRow)

                $ok = & { $dep.Install() } 6>$null

                $st[$name].Phase = if ($ok) { 'ok' } else { 'err' }
                [Console]::SetCursorPosition(0, $tableRow + $rowOf[$name])
                Render-ProgressRow $name $st[$name] $w
                [Console]::SetCursorPosition(0, $afterRow)
                if ($ok) { $manifest[$dep.Command] = $dep.ManifestEntry('system', $RuntimeDir, $InstallDir) }
            }
            'portable' {
                if ($name -eq 'whisper') { $whisperTask = $t }
            }
        }
    }

    $portableJobs = @{}
    foreach ($t in $tasks) {
        $dep  = $t.Dep
        $name = $dep.Name
        if ($t.Mode -ne 'portable' -or $name -eq 'whisper') { continue }
        if ($st[$name].Phase -eq 'err') { continue }

        if (-not (Test-Path $RuntimeDir)) { New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null }

        $sb        = $null
        $sbArgList = @()
        if ($name -eq 'Python')   { $sb = $sbPython;   $sbArgList = @($t.ZipDest, $RuntimeDir) }
        if ($name -eq 'ffmpeg')   { $sb = $sbFfmpeg;   $sbArgList = @($t.ZipDest, $RuntimeDir) }
        if ($name -eq 'mkvmerge') { $sb = $sbMkvmerge; $sbArgList = @($t.ZipDest, $RuntimeDir) }
        if (-not $sb) { continue }

        $st[$name].Phase     = 'inst'
        $st[$name].StartedAt = Get-Date
        [Console]::SetCursorPosition(0, $tableRow + $rowOf[$name])
        Render-ProgressRow $name $st[$name] $w

        $portableJobs[$name] = @{ Job = Start-Job -ScriptBlock $sb -ArgumentList $sbArgList; Dep = $dep }
    }
    [Console]::SetCursorPosition(0, $afterRow)

    while ($portableJobs.Values | Where-Object { $_.Job.State -eq 'Running' }) {
        foreach ($nm in $portableJobs.Keys) {
            if ($portableJobs[$nm].Job.State -ne 'Running') { continue }
            [Console]::SetCursorPosition(0, $tableRow + $rowOf[$nm])
            Render-ProgressRow $nm $st[$nm] $w
        }
        [Console]::SetCursorPosition(0, $afterRow)
        Start-Sleep -Milliseconds 400
    }

    foreach ($nm in $portableJobs.Keys) {
        $ij  = $portableJobs[$nm].Job
        $dep = $portableJobs[$nm].Dep
        $result = Receive-Job -Job $ij -ErrorAction SilentlyContinue
        $ok     = ($ij.State -ne 'Failed') -and ($result -eq $true)
        Remove-Job -Job $ij -Force

        $st[$nm].Phase = if ($ok) { 'ok' } else { 'err' }
        [Console]::SetCursorPosition(0, $tableRow + $rowOf[$nm])
        Render-ProgressRow $nm $st[$nm] $w

        if ($ok) {
            $manifest[$dep.Command] = $dep.ManifestEntry('portable', $RuntimeDir, $InstallDir)
            $needRuntime = $true
        }
    }
    [Console]::SetCursorPosition(0, $afterRow)

    if ($whisperTask) {
        $dep  = $whisperTask.Dep
        $name = $dep.Name
        if (-not (Test-Path $RuntimeDir)) { New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null }
        $pyExe     = Join-Path $RuntimeDir "python\python.exe"
        $portablePy = Test-Path $pyExe
        if (-not $portablePy) {
            $pyCmd = Get-Command "python" -ErrorAction SilentlyContinue
            if ($pyCmd -and $pyCmd.Source -notlike "*\Microsoft\WindowsApps\*") {
                $pyExe = $pyCmd.Source
            }
        }

        if (-not (Test-Path $pyExe)) {
            $st[$name].Phase = 'err'
        } else {
            $st[$name].Phase     = 'pip'
            $st[$name].StartedAt = Get-Date
            [Console]::SetCursorPosition(0, $tableRow + $rowOf[$name])
            Render-ProgressRow $name $st[$name] $w
            [Console]::SetCursorPosition(0, $afterRow)

            if (-not (Test-Path $LogDir)) {
                New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction SilentlyContinue | Out-Null
            }
            if (-not (Test-Path $LogDir)) { $LogDir = $env:TEMP }
            $pipLog    = Join-Path $LogDir "pip-whisper.log"
            $savedHome = $env:PYTHONHOME; $savedPath = $env:PYTHONPATH
            $env:PYTHONHOME       = $null; $env:PYTHONPATH = $null
            $env:PYTHONUNBUFFERED = '1';   $env:PYTHONIOENCODING = 'utf-8'

            Add-Content -Path $pipLog -Value "`n=== $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) ===" -Encoding UTF8 -ErrorAction SilentlyContinue
            Add-Content -Path $pipLog -Value "Python: $pyExe" -Encoding UTF8 -ErrorAction SilentlyContinue

            $setupOut = "$pipLog.setup"; $setupErr = "$pipLog.setup.err"
            $setupProc = Start-Process -FilePath $pyExe `
                -ArgumentList @('-m', 'pip', 'install', '--upgrade', 'setuptools', 'wheel', '--no-warn-script-location') `
                -RedirectStandardOutput $setupOut -RedirectStandardError $setupErr `
                -NoNewWindow -PassThru
            $setupProc.WaitForExit()
            $env:PYTHONHOME = $savedHome; $env:PYTHONPATH = $savedPath
            Add-Content -Path $pipLog -Value "setuptools exit=$($setupProc.ExitCode)" -Encoding UTF8 -ErrorAction SilentlyContinue
            foreach ($tf in @($setupOut, $setupErr)) {
                if (Test-Path $tf) {
                    $tc = Get-Content $tf -Raw -ErrorAction SilentlyContinue
                    if ($tc) { Add-Content -Path $pipLog -Value $tc -Encoding UTF8 -ErrorAction SilentlyContinue }
                    Remove-Item $tf -Force -ErrorAction SilentlyContinue
                }
            }

            if ($setupProc.ExitCode -gt 0) {
                $st[$name].Phase = 'err'
            } else {
                $installArgs = @('-m', 'pip', 'install', '--upgrade', '--no-build-isolation', 'openai-whisper', '--no-warn-script-location')
                Add-Content -Path $pipLog -Value "`n--- whisper pip: $($installArgs -join ' ') ---" -Encoding UTF8 -ErrorAction SilentlyContinue

                $captPy   = $pyExe
                $captLog  = $pipLog
                $captArgs = $installArgs
                $pipJob = Start-Job -ScriptBlock {
                    param($py, $log, $installArgs)
                    $env:PYTHONHOME      = $null
                    $env:PYTHONPATH      = $null
                    $env:PYTHONUNBUFFERED = '1'
                    $env:PYTHONIOENCODING = 'utf-8'
                    try {
                        $pyVer  = & $py --version 2>&1
                        $pipVer = & $py -m pip --version 2>&1
                        Add-Content -Path $log -Value "python: $pyVer" -Encoding UTF8 -ErrorAction SilentlyContinue
                        Add-Content -Path $log -Value "pip: $pipVer" -Encoding UTF8 -ErrorAction SilentlyContinue
                        Add-Content -Path $log -Value "start: $((Get-Date).ToString('HH:mm:ss'))" -Encoding UTF8 -ErrorAction SilentlyContinue

                        & $py @installArgs 2>&1 | ForEach-Object {
                            Add-Content -Path $log -Value "$_" -Encoding UTF8 -ErrorAction SilentlyContinue
                        }

                        $ec = if ($null -eq $LASTEXITCODE) { 1 } else { $LASTEXITCODE }
                        Add-Content -Path $log -Value "end: $((Get-Date).ToString('HH:mm:ss'))  exit=$ec" -Encoding UTF8 -ErrorAction SilentlyContinue
                        return $ec
                    } catch {
                        Add-Content -Path $log -Value "EXCEPTION: $_" -Encoding UTF8 -ErrorAction SilentlyContinue
                        return 1
                    }
                } -ArgumentList $captPy, $captLog, $captArgs

                while ($pipJob.State -eq 'Running') {
                    try {
                        $fs  = [System.IO.File]::Open($pipLog, 'Open', 'Read', 'ReadWrite')
                        $sr  = New-Object System.IO.StreamReader($fs)
                        $raw = $sr.ReadToEnd()
                        $sr.Close(); $fs.Close()
                        $idx = $raw.LastIndexOf('--- whisper pip')
                        $pip = if ($idx -ge 0) { $raw.Substring($idx) } else { '' }
                        $ll  = ($pip -split "`n" | Where-Object {
                            $l = $_.Trim()
                            $l -ne '' -and
                            -not $l.StartsWith('---') -and
                            -not $l.StartsWith('Successfully uninstalled') -and
                            -not $l.StartsWith('Uninstalling ') -and
                            -not $l.StartsWith('Found existing installation') -and
                            -not $l.StartsWith('DEPRECATION') -and
                            -not $l.StartsWith('WARNING')
                        } | Select-Object -Last 1)
                        if ($ll) { $st[$name].LastLine = $ll.Trim() }
                    } catch {}

                    [Console]::SetCursorPosition(0, $tableRow + $rowOf[$name])
                    Render-ProgressRow $name $st[$name] $w
                    [Console]::SetCursorPosition(0, $afterRow)
                    Start-Sleep -Milliseconds 300
                }

                $jobResult = @(Receive-Job $pipJob -ErrorAction SilentlyContinue)
                Remove-Job $pipJob -Force
                $rawEc = $jobResult | Where-Object { $_ -is [int] } | Select-Object -Last 1
                $ec = if ($null -eq $rawEc) { 1 } else { [int]$rawEc }

                $scriptsDir = Join-Path (Split-Path $pyExe -Parent) "Scripts"
                $whisperExe = Join-Path $scriptsDir "whisper.exe"
                if (-not (Test-Path $whisperExe)) {
                    $wCmd = Get-Command "whisper" -ErrorAction SilentlyContinue
                    if ($wCmd) { $whisperExe = $wCmd.Source }
                }
                Add-Content -Path $pipLog -Value "whisper.exe: $(if ($whisperExe -and (Test-Path $whisperExe)) { 'OK' } else { 'brak' })" -Encoding UTF8 -ErrorAction SilentlyContinue

                $whisperOk  = ($ec -eq 0) -and $whisperExe -and (Test-Path $whisperExe)
                $st[$name].Phase = if ($whisperOk) { 'ok' } else { 'err' }
            }
        }

        [Console]::SetCursorPosition(0, $tableRow + $rowOf[$name])
        Render-ProgressRow $name $st[$name] $w
        [Console]::SetCursorPosition(0, $afterRow)

        if ($null -ne $pipLog -and (Test-Path $pipLog)) {
            Write-Host "    Log pip: $pipLog" -ForegroundColor DarkGray
        }

        if ($st[$name].Phase -eq 'err' -and $null -ne $pipLog -and (Test-Path $pipLog)) {
            $tail = Get-Content $pipLog -Tail 20 -ErrorAction SilentlyContinue
            if ($tail) {
                Write-Host ""
                foreach ($line in $tail) { Write-Host "    $line" -ForegroundColor DarkGray }
            }
        }

        if ($st[$name].Phase -eq 'ok') {
            $modelsDir   = Join-Path $InstallDir "models"
            New-Item -ItemType Directory -Force -Path $modelsDir -ErrorAction SilentlyContinue | Out-Null
            $modelLogErr = Join-Path $LogDir "whisper-model.err"
            $modelScript = Join-Path $env:TEMP "tm-model-dl.py"
            Set-Content -Path $modelScript -Value "import whisper; whisper.load_model('medium', download_root=r'$modelsDir')" -Encoding UTF8

            $st[$name].Phase     = 'inst'
            $st[$name].LastLine  = "Pobieranie modelu medium (~1.5 GB)..."
            $st[$name].StartedAt = Get-Date
            [Console]::SetCursorPosition(0, $tableRow + $rowOf[$name])
            Render-ProgressRow $name $st[$name] $w
            [Console]::SetCursorPosition(0, $afterRow)

            $modelProc = Start-Process -FilePath $pyExe -ArgumentList @($modelScript) `
                -RedirectStandardError $modelLogErr -NoNewWindow -PassThru -ErrorAction SilentlyContinue

            if ($modelProc) {
                while (-not $modelProc.HasExited) {
                    try {
                        $fs  = [System.IO.File]::Open($modelLogErr, 'Open', 'Read', 'ReadWrite')
                        $sr  = New-Object System.IO.StreamReader($fs)
                        $raw = $sr.ReadToEnd()
                        $sr.Close(); $fs.Close()
                        $ll  = ($raw -split "`r") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1
                        if ($ll) { $st[$name].LastLine = $ll.Trim() }
                    } catch {}
                    [Console]::SetCursorPosition(0, $tableRow + $rowOf[$name])
                    Render-ProgressRow $name $st[$name] $w
                    [Console]::SetCursorPosition(0, $afterRow)
                    Start-Sleep -Milliseconds 500
                }
                $modelProc.WaitForExit()
            }

            Remove-Item $modelScript -Force -ErrorAction SilentlyContinue
            $st[$name].Phase = 'ok'
            [Console]::SetCursorPosition(0, $tableRow + $rowOf[$name])
            Render-ProgressRow $name $st[$name] $w
            [Console]::SetCursorPosition(0, $afterRow)

            if ($portablePy) {
                $manifest[$dep.Command] = $dep.ManifestEntry('portable', $RuntimeDir, $InstallDir)
                $needRuntime = $true
            } else {
                $manifest[$dep.Command] = $dep.ManifestEntry('system', $RuntimeDir, $InstallDir)
            }
        }
    }

    Write-Host ""

    if ($manifest.Count -gt 0) {
        $runtimeFile = Join-Path $InstallDir "runtime.json"
        [PSCustomObject]$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $runtimeFile -Encoding UTF8
        if ($installTasks.Count -gt 0) { Write-OK "Zapisano manifest: $runtimeFile" }
    }

    if (-not $needRuntime) {
        Write-Host "`n  UWAGA: narzedzia systemowe moga wymagac restartu PowerShella," -ForegroundColor Yellow
        Write-Host "         zeby pojawily sie w PATH." -ForegroundColor Yellow
    }
}
