$script:FarmHeartbeatTimeoutSec = 120

<#
.SYNOPSIS Zwraca PSCustomObject ze sciezkami podfolderow kolejki.
#>
function Get-FarmPaths {
    param([string]$QueuePath)
    return [PSCustomObject]@{
        Root    = $QueuePath
        Todo    = Join-Path $QueuePath "todo"
        Claimed = Join-Path $QueuePath "claimed"
        Done    = Join-Path $QueuePath "done"
        Failed  = Join-Path $QueuePath "failed"
        Workers = Join-Path $QueuePath "workers"
    }
}

<#
.SYNOPSIS Tworzy podfoldery kolejki jesli brak. Zwraca $true gdy kolejka osiagalna.
#>
function Initialize-FarmQueue {
    param([string]$QueuePath)
    if (-not $QueuePath) { return $false }
    $p = Get-FarmPaths $QueuePath
    try {
        foreach ($d in @($p.Root, $p.Todo, $p.Claimed, $p.Done, $p.Failed, $p.Workers)) {
            if (-not (Test-Path $d)) {
                New-Item -ItemType Directory -Path $d -Force -EA Stop | Out-Null
            }
        }
        return $true
    } catch {
        return $false
    }
}

<#
.SYNOPSIS Generuje unikalny id zlecenia: yyyyMMdd_HHmmss + 4-znakowy sufiks hex.
#>
function New-FarmJobId {
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $suffix = ([guid]::NewGuid().ToString('N')).Substring(0, 4)
    return "${stamp}_${suffix}"
}

<#
.SYNOPSIS Zapisuje deskryptor zlecenia job-<id>.json do folderu todo\.
.PARAMETER QueuePath Sciezka kolejki
.PARAMETER Source Pelna sciezka UNC do pliku zrodlowego
.PARAMETER Output Folder docelowy wynikow (osiagalny sieciowo)
.OUTPUTS Id utworzonego zlecenia (string).
#>
function Write-FarmJob {
    param(
        [string]$QueuePath,
        [string]$Source,
        [string]$Output,
        [string]$Language = "Polish",
        [string]$Model = "medium",
        [string]$Fp16 = "True"
    )
    $p  = Get-FarmPaths $QueuePath
    $id = New-FarmJobId
    $job = [PSCustomObject]@{
        id        = $id
        source    = $Source
        output    = $Output
        language  = $Language
        model     = $Model
        fp16      = $Fp16
        createdBy = $env:COMPUTERNAME
        createdAt = (Get-Date -Format 's')
    }
    $dest = Join-Path $p.Todo "job-$id.json"
    $job | ConvertTo-Json -Depth 5 | Set-Content -Path $dest -Encoding UTF8
    return $id
}

<#
.SYNOPSIS Czyta deskryptor zlecenia z pliku (Read-FileSafe na wypadek blokady).
.OUTPUTS PSCustomObject zlecenia lub $null gdy bledny/pusty.
#>
function Read-FarmJob {
    param([string]$Path)
    $raw = Read-FileSafe $Path
    if (-not $raw) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

<#
.SYNOPSIS Atomowo zatrzaskuje pierwsze wolne zlecenie z todo\ (Move-Item do claimed\).
.DESCRIPTION Rename na SMB jest atomowy: dokladnie jeden worker wygrywa, przegrany
dostaje wyjatek (plik zniknal) i probuje nastepne. Zwraca PSCustomObject zlecenia
(z dopisanym polem ClaimedPath = sciezka w claimed\) albo $null gdy brak zadan.
.PARAMETER QueuePath Sciezka kolejki
#>
function Invoke-FarmClaim {
    param([string]$QueuePath)
    $p = Get-FarmPaths $QueuePath
    $jobs = @(Get-ChildItem -Path $p.Todo -Filter "job-*.json" -File -EA SilentlyContinue |
        Sort-Object { Get-NaturalSortKey $_.Name })
    foreach ($f in $jobs) {
        $dest = Join-Path $p.Claimed $f.Name
        try {
            Move-Item -Path $f.FullName -Destination $dest -EA Stop
        } catch {
            continue
        }
        $job = Read-FarmJob $dest
        if ($null -eq $job) {
            $errPath = (Join-Path $p.Failed $f.Name)
            try { Move-Item -Path $dest -Destination $errPath -Force -EA Stop } catch {}
            Set-Content -Path ($errPath + ".error") -Value "Niepoprawny JSON zlecenia." -Encoding UTF8 -EA SilentlyContinue
            continue
        }
        $job | Add-Member -NotePropertyName ClaimedPath -NotePropertyValue $dest -Force
        return $job
    }
    return $null
}

<#
.SYNOPSIS Odswieza heartbeat zatrzasnietego zlecenia (timestamp w pliku .heartbeat).
.PARAMETER QueuePath Sciezka kolejki
.PARAMETER JobId Id zlecenia
#>
function Update-FarmHeartbeat {
    param([string]$QueuePath, [string]$JobId)
    $p = Get-FarmPaths $QueuePath
    $hb = Join-Path $p.Claimed "job-$JobId.heartbeat"
    try {
        Set-Content -Path $hb -Value (Get-Date -Format 'o') -Encoding UTF8 -EA Stop
    } catch {}
}

<#
.SYNOPSIS Zapisuje status workera do workers\<maszyna>.json (dla monitora).
.PARAMETER QueuePath Sciezka kolejki
.PARAMETER CurrentFile Aktualnie przetwarzany plik (nazwa) lub ""
.PARAMETER Progress Procent postepu (0-100)
.PARAMETER Status Tekstowy status: "idle" / "working" / "stopped"
#>
function Update-FarmWorkerStatus {
    param(
        [string]$QueuePath,
        [string]$CurrentFile = "",
        [int]$Progress = 0,
        [string]$Status = "idle"
    )
    $p = Get-FarmPaths $QueuePath
    $rec = [PSCustomObject]@{
        machine     = $env:COMPUTERNAME
        status      = $Status
        currentFile = $CurrentFile
        progress    = $Progress
        heartbeat   = (Get-Date -Format 'o')
    }
    $dest = Join-Path $p.Workers "$($env:COMPUTERNAME).json"
    try {
        $rec | ConvertTo-Json -Depth 5 | Set-Content -Path $dest -Encoding UTF8 -EA Stop
    } catch {}
}

<#
.SYNOPSIS Przenosi przeterminowane zlecenia z claimed\ z powrotem do todo\.
.DESCRIPTION Skanuje claimed\, jesli .heartbeat starszy niz prog (lub brak) -- uznaje
workera za martwego, czysci heartbeat i wraca job do todo\. Zwraca liczbe odzyskanych.
.PARAMETER QueuePath Sciezka kolejki
#>
function Invoke-FarmReclaim {
    param([string]$QueuePath)
    $p = Get-FarmPaths $QueuePath
    $reclaimed = 0
    $jobs = @(Get-ChildItem -Path $p.Claimed -Filter "job-*.json" -File -EA SilentlyContinue)
    foreach ($f in $jobs) {
        $hb = Join-Path $p.Claimed ($f.BaseName + ".heartbeat")
        $stale = $true
        if (Test-Path $hb) {
            $ageSec = ((Get-Date) - (Get-Item $hb).LastWriteTime).TotalSeconds
            if ($ageSec -le $script:FarmHeartbeatTimeoutSec) { $stale = $false }
        }
        if (-not $stale) { continue }
        $dest = Join-Path $p.Todo $f.Name
        try {
            Move-Item -Path $f.FullName -Destination $dest -EA Stop
            if (Test-Path $hb) { Remove-Item $hb -Force -EA SilentlyContinue }
            Write-FarmLog $QueuePath "Reclaim: $($f.Name) (zombie >${script:FarmHeartbeatTimeoutSec}s)"
            $reclaimed++
        } catch {
        }
    }
    return $reclaimed
}

<#
.SYNOPSIS Zwraca liczniki zadan w kolejce: todo/claimed/done/failed.
#>
function Get-FarmCounts {
    param([string]$QueuePath)
    $p = Get-FarmPaths $QueuePath
    return [PSCustomObject]@{
        Todo    = @(Get-ChildItem -Path $p.Todo    -Filter "job-*.json" -File -EA SilentlyContinue).Count
        Claimed = @(Get-ChildItem -Path $p.Claimed -Filter "job-*.json" -File -EA SilentlyContinue).Count
        Done    = @(Get-ChildItem -Path $p.Done    -Filter "job-*.json" -File -EA SilentlyContinue).Count
        Failed  = @(Get-ChildItem -Path $p.Failed  -Filter "job-*.json" -File -EA SilentlyContinue).Count
    }
}

<#
.SYNOPSIS Zapisuje zdarzenie do farm.log w folderze kolejki (append, UTF-8).
.PARAMETER QueuePath Sciezka kolejki
.PARAMETER Message Tresc zdarzenia
#>
function Write-FarmLog {
    param([string]$QueuePath, [string]$Message)
    $logPath = Join-Path $QueuePath "farm.log"
    $line    = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$($env:COMPUTERNAME)] $Message"
    try { Add-Content -Path $logPath -Value $line -Encoding UTF8 -EA Stop } catch {}
}

<#
.SYNOPSIS Czyta wpisy workers\*.json, dolicza wiek heartbeatu w sekundach.
.OUTPUTS Tablica PSCustomObject (machine, status, currentFile, progress, AgeSec).
#>
function Get-FarmWorkers {
    param([string]$QueuePath)
    $p = Get-FarmPaths $QueuePath
    $out = @()
    $files = @(Get-ChildItem -Path $p.Workers -Filter "*.json" -File -EA SilentlyContinue)
    foreach ($f in $files) {
        $rec = $null
        $raw = Read-FileSafe $f.FullName
        if ($raw) { try { $rec = $raw | ConvertFrom-Json } catch {} }
        if ($null -eq $rec) { continue }
        $age = 9999
        if ($rec.heartbeat) {
            try { $age = [int]((Get-Date) - [datetime]$rec.heartbeat).TotalSeconds } catch {}
        }
        $out += [PSCustomObject]@{
            Machine     = $rec.machine
            Status      = $rec.status
            CurrentFile = $rec.currentFile
            Progress    = [int]$rec.progress
            AgeSec      = $age
        }
    }
    return @($out | Sort-Object Machine)
}
