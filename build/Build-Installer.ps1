#Requires -Version 5.1
<#
.SYNOPSIS Buduje samowystarczalny installer.ps1 z install/ + build/installer-main.ps1.
.PARAMETER Version Wersja wstrzykiwana jako $script:TM_VERSION (np. v1.2.3-5-gabc123).
.PARAMETER SrcUrl URL do src.zip wstrzykiwany jako $script:TM_SRC_URL.
.PARAMETER OutFile Ścieżka wyjściowa (domyślnie installer.ps1 w roocie repo).
.EXAMPLE build/Build-Installer.ps1 -Version v0.0.0-test -SrcUrl http://x/src.zip
#>
param(
    [Parameter(Mandatory = $true)] [string] $Version,
    [Parameter(Mandatory = $true)] [string] $SrcUrl,
    [string] $OutFile = "installer.ps1"
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path $PSCommandPath -Parent | Split-Path -Parent
$installDir = Join-Path $repoRoot "install"
$buildDir   = Join-Path $repoRoot "build"

function Get-RelPath {
    param([string]$Full)
    $root = $repoRoot.TrimEnd('\')
    if ($Full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Full.Substring($root.Length).TrimStart('\').Replace('\', '/')
    }
    return (Split-Path $Full -Leaf)
}

$files = New-Object System.Collections.Generic.List[string]

Get-ChildItem (Join-Path $installDir "Core") -Filter *.ps1 | Sort-Object Name |
    ForEach-Object { $files.Add($_.FullName) }

$files.Add((Join-Path $installDir "Dependencies\Dependency.ps1"))
Get-ChildItem (Join-Path $installDir "Dependencies") -Filter "*Dependency.ps1" |
    Where-Object { $_.Name -ne "Dependency.ps1" } | Sort-Object Name |
    ForEach-Object { $files.Add($_.FullName) }

Get-ChildItem (Join-Path $installDir "DependencyInstall") -Filter *.ps1 | Sort-Object Name |
    ForEach-Object { $files.Add($_.FullName) }

Get-ChildItem (Join-Path $installDir "Phases") -Filter *.ps1 | Sort-Object Name |
    ForEach-Object { $files.Add($_.FullName) }

$files.Add((Join-Path $buildDir "installer-main.ps1"))

foreach ($f in $files) {
    if (-not (Test-Path $f)) { throw "Brak pliku do sklejenia: $f" }
}

$header = @"
#Requires -Version 5.1
# ============================================================================
#  Transcription Manager -- samowystarczalny installer (generated)
#  Wersja: @@TM_VERSION@@
#  NIE EDYTUJ RECZNIE -- generowany przez build/Build-Installer.ps1
# ============================================================================
`$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Add-Type -AssemblyName System.Windows.Forms
`$script:TM_VERSION = "@@TM_VERSION@@"
`$script:TM_SRC_URL = "@@TM_SRC_URL@@"
"@

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine($header)
[void]$sb.AppendLine("")

foreach ($f in $files) {
    $rel = Get-RelPath $f
    [void]$sb.AppendLine("# === $rel ===")
    $content = [System.IO.File]::ReadAllText($f, [System.Text.UTF8Encoding]::new($false))
    [void]$sb.AppendLine($content)
    [void]$sb.AppendLine("")
}

$out = $sb.ToString()
$out = $out.Replace('@@TM_VERSION@@', $Version).Replace('@@TM_SRC_URL@@', $SrcUrl)

if ($out -match '@@') {
    throw "Pozostaly niepodmienione placeholdery @@...@@ w wyniku."
}

$err = $null
[void][System.Management.Automation.PSParser]::Tokenize($out, [ref]$err)
if ($err.Count -gt 0) {
    $msg = ($err | ForEach-Object { "L$($_.Token.StartLine): $($_.Message)" }) -join "; "
    throw "Bledy skladniowe w zbudowanym installerze: $msg"
}

$safe = New-Object System.Text.StringBuilder ($out.Length * 2)
foreach ($c in $out.ToCharArray()) {
    if ([int]$c -gt 127) { [void]$safe.Append('$([char]' + [int]$c + ')') }
    else                  { [void]$safe.Append($c) }
}
$out = $safe.ToString()

$outFull = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $repoRoot $OutFile }
[System.IO.File]::WriteAllText($outFull, $out, [System.Text.UTF8Encoding]::new($false))

$bytes = [System.IO.File]::ReadAllBytes($outFull)[0..2]
$bom = ($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
Write-Host "Zbudowano: $outFull (BOM=$bom, wersja=$Version)" -ForegroundColor Green
