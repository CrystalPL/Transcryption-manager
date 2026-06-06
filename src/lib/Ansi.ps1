# Ansi.ps1 -- kody escape do batched output bez migania
# Win10/11 conhost obsluguje natywnie (VirtualTerminalProcessing)

$script:ESC = [char]27

# Wymus wlaczenie VT mode (na wypadek starszego conhostu)
function Enable-VirtualTerminal {
    try {
        if (-not ("Native.VT" -as [type])) {
            Add-Type -Name VT -Namespace Native -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern System.IntPtr GetStdHandle(int nStdHandle);
"@
        }
        $h = [Native.VT]::GetStdHandle(-11)
        $m = 0
        [void][Native.VT]::GetConsoleMode($h, [ref]$m)
        [void][Native.VT]::SetConsoleMode($h, $m -bor 0x0004)
    } catch {}
}

Enable-VirtualTerminal

<#
.SYNOPSIS Zwraca ANSI kod dla koloru tekstu (foreground).
#>
function Get-AnsiFg {
    param([string]$Color)
    switch ($Color) {
        'Black'       { '30' }; 'DarkBlue'    { '34' }; 'DarkGreen'   { '32' }
        'DarkCyan'    { '36' }; 'DarkRed'     { '31' }; 'DarkMagenta' { '35' }
        'DarkYellow'  { '33' }; 'Gray'        { '37' }; 'DarkGray'    { '90' }
        'Blue'        { '94' }; 'Green'       { '92' }; 'Cyan'        { '96' }
        'Red'         { '91' }; 'Magenta'     { '95' }; 'Yellow'      { '93' }
        'White'       { '97' }; default       { '37' }
    }
}

<#
.SYNOPSIS Zwraca ANSI kod dla koloru tla (background).
#>
function Get-AnsiBg {
    param([string]$Color)
    switch ($Color) {
        'Black'       { '40' }; 'DarkBlue'    { '44' }; 'DarkGreen'   { '42' }
        'DarkCyan'    { '46' }; 'DarkRed'     { '41' }; 'DarkMagenta' { '45' }
        'DarkYellow'  { '43' }; 'Gray'        { '47' }; 'DarkGray'    { '100' }
        'Blue'        { '104' }; 'Green'      { '102' }; 'Cyan'       { '106' }
        'Red'         { '101' }; 'Magenta'    { '105' }; 'Yellow'     { '103' }
        'White'       { '107' }; default      { '40' }
    }
}

<#
.SYNOPSIS Owija tekst w sekwencje ANSI kolorow (bez pozycjonowania).
#>
function Wrap-Ansi {
    param([string]$Text, [string]$Fg = 'Gray', [string]$Bg = 'Black')
    $fgC = Get-AnsiFg $Fg
    $bgC = Get-AnsiBg $Bg
    return "$script:ESC[$fgC;${bgC}m$Text$script:ESC[0m"
}
