function Get-PortableExtractor {
    <#
    .SYNOPSIS Zwraca samowystarczalny scriptblock (do Start-Job) rozpakowujacy portable dana zaleznosc do runtime\.
    .DESCRIPTION Scriptblock przyjmuje (zipPath, runtimeDir), uzywa wylacznie cmdletow i .NET (bez klas/funkcji zewnetrznych), wiec dziala w obcym runspace zadania. Zwraca $true przy sukcesie.
    .PARAMETER Name Nazwa komponentu: 'Python' | 'ffmpeg' | 'mkvmerge'.
    .EXAMPLE $sb = Get-PortableExtractor -Name 'Python'
    #>
    param([string]$Name)

    switch ($Name) {
        'Python' {
            return {
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
        }
        'ffmpeg' {
            return {
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
        }
        'mkvmerge' {
            return {
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
        }
    }
    return $null
}
