<#
.SYNOPSIS
Zwraca nazwy plikow lib/ w poprawnej kolejnosci ladowania (dot-source).
.DESCRIPTION
Kolejnosc ma znaczenie: Format -> Ansi -> Console -> reszta (kazda kolejna
biblioteka moze polegac na poprzednich). To jedyne miejsce gdzie ta lista jest
zdefiniowana -- uzywane przez Manager.ps1 oraz bootstrap workera w Watch-Farm.ps1.
Dodanie nowej biblioteki = jeden wpis tutaj, oba miejsca dostaja go automatycznie.

Lista NIE zawiera 'LoadOrder.ps1' -- ten plik jest ladowany jawnie zanim
wywolasz Get-LibLoadOrder, wiec ponowne dot-source'owanie byloby zbedne.
.EXAMPLE
. (Join-Path $LibDir 'LoadOrder.ps1')
foreach ($f in (Get-LibLoadOrder)) { . (Join-Path $LibDir $f) }
#>
function Get-LibLoadOrder {
    return @(
        "Format.ps1",
        "Ansi.ps1",
        "Console.ps1",
        "Config.ps1",
        "Runtime.ps1",
        "Dialog.ps1",
        "ShellMetadata.ps1",
        "Whisper.ps1",
        "Picker.ps1",
        "MultiPicker.ps1",
        "Dashboard.ps1",
        "Farm.ps1"
    )
}
