# CLAUDE.md

Kontekst projektu dla przyszłych sesji Claude Code (i deweloperów). Czytaj na początku każdej sesji.

## Co to jest

PowerShell TUI do pracy z transkrypcjami nagrań:
1. **Whisper** generuje SRT/VTT z plików wideo (`New-Transcription.ps1`)
2. **mkvmerge** wpina rozdziały (XML Matroska Chapters) do MKV bez ponownego kodowania (`Add-Chapters.ps1`)
3. **Farma** rozdziela transkrypcje na wiele maszyn przez kolejkę na wspólnym folderze (`Send-FarmJobs.ps1`, `Start-FarmWorker.ps1`, `Watch-Farm.ps1`)

Cała aplikacja to PowerShell 5.1 + Windows Forms (do dialogów folderu) + native cmd-line tools (whisper, mkvmerge). Brak zależności od PowerShell 7.

## Struktura

```
src/
├── Manager.ps1              # entry point — dot-source'uje lib/, pokazuje menu
├── lib/                     # współdzielone helpery (KOLEJNOŚĆ ŁADOWANIA WAŻNA)
│   ├── Format.ps1           # 1. Fit, Format-Size/Time, NaturalSort, DurationToSeconds
│   ├── Ansi.ps1             # 2. ESC, Get-AnsiFg/Bg, Wrap-Ansi, Build-Row (+ VT enable)
│   ├── Console.ps1          # 3. Get-ConsoleWidth, Show-Header, Ask-TakNie, Ask-Choice
│   ├── Config.ps1           # 4. Read-Config, Save-Config, Update-Config (JSON)
│   ├── Runtime.ps1          # 5. Get-RuntimeManifest, Resolve-Tool, Initialize-RuntimePath (portable runtime)
│   ├── Dialog.ps1           # 6. Open-FolderDialog, Select-Folder (System.Windows.Forms)
│   ├── ShellMetadata.ps1    # 7. Get-ShellDurations, Read-FileSafe
│   ├── Whisper.ps1          # 8. Start-WhisperJob, Finalize-WhisperJob, New-WhisperState
│   ├── Picker.ps1           # 9. Show-Picker (single-select + nawigacja po katalogach)
│   ├── MultiPicker.ps1      # 10. Show-MultiPicker (multi-select, Spacja zaznacza)
│   ├── Dashboard.ps1        # 11. Render-Dashboard, View-Logs, Get-WhisperProgressSec
│   ├── Farm.ps1             # 12. kolejka farmy — claim/heartbeat/reclaim zleceń na wspólnym folderze
│   └── LoadOrder.ps1        # ładowany jawnie PIERWSZY: Get-LibLoadOrder — kolejność ładowania powyższych
└── Scripts/
    ├── New-Transcription.ps1   # whisper + dashboard z live progress
    ├── Add-Chapters.ps1        # XML -> MKV przez mkvmerge
    ├── Send-FarmJobs.ps1       # farma: zlecanie zadań do kolejki (todo\)
    ├── Start-FarmWorker.ps1    # farma: worker — zatrzaskuje i wykonuje zlecenia
    └── Watch-Farm.ps1          # farma: monitor kolejki + workerów + reclaim zombie
```

Pakowanie do instalatora: `build/` (`Build-Installer.ps1`, `installer-main.ps1`) + workflow CI `.github/workflows/release.yml`.

`wiki/` — osobne repo git (`wiki/.git/`) wskazujące na `Transcription-manager.wiki.git`. Ignorowane przez główne repo (`.gitignore`). Pushuj osobno z poziomu IDE lub `cd wiki && git push`.

Każdy `Scripts/*.ps1` zakłada że wszystkie `lib/*` są już załadowane (dot-source'owane przez Manager.ps1). Nigdy nie uruchamiaj `New-Transcription.ps1` bezpośrednio — tylko przez Managera.

## Farma transkrypcji (kolejka na wspólnym folderze)

Tryb rozproszony: wiele maszyn LAN dzieli wspólny folder (UNC) jako kolejkę.
- `Send-FarmJobs.ps1` — główny komp pisze deskryptory `job-<id>.json` do `todo\`.
- `Start-FarmWorker.ps1` — worker atomowo zatrzaskuje zlecenie (`Move-Item` todo→claimed),
  odpala whispera, odświeża heartbeat co ~10s, wynik → `done\`/`failed\`.
- `Watch-Farm.ps1` — monitor: liczniki + tabela workerów + cykliczny reclaim (>120s = zombie).

Folder kolejki: `todo/claimed/done/failed/workers`. Atomowość claim oparta na atomowym
rename SMB (przegrany dostaje wyjątek na `Move-Item`, bierze następne). Config:
`Farm.config.json` (gitignore), env-override `TRANSCRIPTION_FARM_DIR` → `queuePath`.
Wspólna logika whispera w `lib/Whisper.ps1` (`Start-WhisperJob`/`Finalize-WhisperJob`).
Monitor uruchamia lokalnego workera jako OSOBNY PROCES (komunikacja przez `workers\*.json`).

## Krytyczne ograniczenia PowerShell 5.1

To NIE działa (PS7-only syntax):
- Ternary `$x ? 'a' : 'b'` → użyj `if ($x) { 'a' } else { 'b' }`
- Null-coalescing `$x ?? 'default'` → użyj `if ($null -eq $x) { 'default' } else { $x }`
- `ConvertFrom-Json -AsHashtable` → konwertuj PSCustomObject ręcznie pętlą po PSObject.Properties
- Pipeline chain `||` `&&` → użyj `; if ($?) { ... }` lub osobnych linii
- `?.` null-conditional → ręczny `if ($x) { $x.Foo }`

UTF-16 LE BOM przy `Out-File` / `Set-Content` bez `-Encoding UTF8` to klasyczny bug — zawsze ustaw encoding.

## Rendering UI — wzorce krytyczne dla braku migania

### 1. Cały frame jako jeden Write

`Write-Host` w PS 5.1 idzie przez pipeline (format → output → host) = ~5ms per call. Przy 30 liniach to 150ms na klatkę = miganie i lag.

Wzorzec używany w `Render-FullMulti`, `Render-Dashboard`, `View-Logs`:

```powershell
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("$script:ESC[H")                          # kursor home
[void]$sb.Append((Wrap-Ansi (Fit "..." $w) 'Cyan') + "`n") # każda linia z kolorem ANSI
# ... więcej Append
[void]$sb.Append("$script:ESC[J")                          # clear to end of screen
[Console]::Write($sb.ToString())                           # JEDEN syscall
```

### 2. NIGDY Clear-Host w pętli renderu

`Clear-Host` (lub ANSI `[2J`) powoduje czarny błysk. Zamiast tego:
- `Clear-Host` RAZ przed pętlą (czysty start)
- W pętli: `[H]` (cursor home) + każda linia `Fit`-owana do `$w` znaków (nadpisuje stare znaki) + `[J]` na końcu (czyści resztę)

Wyjątek: **detekcja resize wymaga `Clear-Host`** — bo nowe (szersze) linie nie nadpiszą starych (węższych) znaków po prawej. Każda funkcja UI musi mieć:

```powershell
$lastW = [Console]::WindowWidth; $lastH = [Console]::WindowHeight
while ($true) {
    $w = [Console]::WindowWidth; $h = [Console]::WindowHeight
    if ($w -ne $lastW -or $h -ne $lastH) {
        $lastW = $w; $lastH = $h
        Clear-Host  # JEDYNE miejsce gdzie wolno
    }
    # render
}
```

### 3. Partial updates (np. ruch kursora w pickerze)

Gdy zmienia się tylko jedna/dwie linie, NIE renderuj całego frame'a. Pozycjonuj kursor ANSI:

```powershell
$frame = "$script:ESC[$($oldRow + 1);1H" + (Build-ItemAnsi $items[$old] $false $w) +
         "$script:ESC[$($newRow + 1);1H" + (Build-ItemAnsi $items[$new] $true  $w)
[Console]::Write($frame)
```

ANSI rows są 1-indexed, dlatego `+1`.

### 4. Coalesce powtórzeń klawiszy

Trzymanie strzałki = 30 keystroke/s. Każdy osobno = render za render. Wzorzec:

```powershell
$k = [Console]::ReadKey($true)
$repeat = 1
if ($k.Key -eq 'UpArrow' -or $k.Key -eq 'DownArrow') {
    while ([Console]::KeyAvailable) {
        $next = [Console]::ReadKey($true)
        if ($next.Key -eq $k.Key) { $repeat++ } else { break }
    }
}
# potem: $cursor += $repeat (z wrap-around)
```

Bez tego: 5 sekund przytrzymania = 5 sekund renderowania PO puszczeniu klawisza.

### 5. Polling pattern (key + resize)

```powershell
while (-not [Console]::KeyAvailable) {
    Start-Sleep -Milliseconds 30
    $nw = [Console]::WindowWidth
    if ($nw -ne $lastW) { ... resize handling ... }
    if ($needFull) { Render-Whatever; $needFull = $false }
}
$k = [Console]::ReadKey($true)
```

30ms = responsywne, nie zżera CPU. `[Console]::WindowWidth` to tani property read — nie ma sensu ograniczać.

## Procesy zewnętrzne — pułapki

### `Register-ObjectEvent` NIE DZIAŁA w pętlach

Eventy `OutputDataReceived` kolejkują się ale **wykonują dopiero gdy PowerShell yielduje**. `Start-Sleep` tego nie robi. Loop z pollingiem = eventy nigdy nie wystrzelą = puste logi.

Działa: `Start-Process -RedirectStandardOutput $file -RedirectStandardError $errFile`. Plik jest pisany przez child process bezpośrednio, nasz PS tylko czyta.

### cmd.exe + polskie znaki = trouble

Pierwsza próba używała `.cmd` wrapper z `Set-Content -Encoding ASCII` — polskie znaki w ścieżce (`Zajęcia`) były zamieniane na `?`, cmd nie znajdował pliku. Lekcja: jeśli musisz cmd, zapisz bat jako `[System.Text.Encoding]::Default` (system ANSI code page) albo użyj UTF-8 + `chcp 65001` na początku. Lepiej: pomiń cmd wrapper całkowicie, używaj `Start-Process`.

### PYTHONUNBUFFERED dla whispera

Python domyślnie buforuje stdout gdy stdout nie jest TTY. Whisper przez subprocess = buforowanie = log pusty do końca procesu = brak live progress.

Ustaw przed odpaleniem whispera:
```powershell
$env:PYTHONUNBUFFERED = "1"
$env:PYTHONIOENCODING = "utf-8"
```

Child process dziedziczy env vars rodzica.

### `Start-Process` nie pozwala stdout i stderr do tego samego pliku

File lock conflict. Rozwiązanie: dwa pliki (`*.log` i `*.log.err`), wszystkie funkcje czytające log (Get-WhisperProgressSec, View-Logs) muszą czytać oba i sklejać. Po zakończeniu procesu Finalize-WhisperJob dokleja `.err` do `.log` i usuwa `.err`.

### File locking podczas live read

`[System.IO.File]::ReadAllText()` rzuca exception jeśli plik jest otwarty na zapis przez inny proces. W `Read-FileSafe`:

```powershell
$fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
$sr = New-Object System.IO.StreamReader($fs)
$content = $sr.ReadToEnd()
$sr.Close(); $fs.Close()
```

`FileShare.ReadWrite` = "ja chcę tylko czytać, inni mogą sobie pisać do woli".

## Konwencje kodu

### Naming
- **Verb-Noun** zgodnie z PS approved verbs (Get-Verb żeby sprawdzić): `New-Transcription`, `Add-Chapters`, `Show-Picker`, nie `getConfig`/`doWhisper`/`makeAnsi`.
- **Polskie nazwy plików** dozwolone w nazwach skryptów (`Tworzenie transkrypcji.config.json`) — wpisują się w UI po polsku. Ale **nazwy funkcji i zmiennych — angielskie** (`$selectedFiles`, nie `$wybraneFile`).
- **Skrypty PowerShellowe — `.ps1`**, biblioteki też `.ps1` (nie `.psm1`, bo dot-source'ujemy zamiast importowania jako moduły).

### Polskie znaki TAK — ale TYLKO z UTF-8 BOM

Pliki `.ps1` **MUSZĄ być zapisane z UTF-8 BOM** (bajty `EF BB BF` na początku). Bez BOM PS 5.1 czyta plik jako CP1250 (systemowy code page polskiego Windowsa), wszystkie znaki spoza ASCII stają się krzakami (`â€"`, `Ã¦`).

**Sprawdzenie czy BOM jest:**
```powershell
$bytes = [System.IO.File]::ReadAllBytes("plik.ps1")[0..2]
($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
# Powinno: "EF BB BF"
```

**Dodanie BOM:**
```powershell
$content = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($true))
```

**UWAGA — Edit/Write tool sandboxa zapisuje bez BOM!** Jeśli edytujesz pliki przez te narzędzia, po każdej edycji **musisz ponownie dodać BOM** powyższym kodem PowerShell. To krytyczne.

**Konsola też potrzebuje UTF-8** — Manager.ps1 ustawia na początku:
```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
$OutputEncoding           = [System.Text.UTF8Encoding]::new()
```

To naprawia rendering polskich znaków w nazwach plików (np. `Zajęcia kontaktowe`) przy listowaniu w pickerze.

Skoro mamy BOM, wszystkie znaki Unicode działają (em-dash `—`, strzałki `→` itp.). Emoji w terminalach Windows Terminal i IntelliJ Terminal — tak; stary conhost — tylko monochromatyczne.

### Comment-based help

Każda publiczna funkcja ma blok `<# .SYNOPSIS ... .PARAMETER ... .EXAMPLE ... #>` — działa `Get-Help Show-Picker -Full`.

### Brak komentarzy

**Nie dodawaj żadnych komentarzy w kodzie** — ani `# co robi linia`, ani `# dlaczego`. Kod ma mówić sam za siebie przez nazwy. Jedyny wyjątek: `<# .SYNOPSIS ... #>` bloki help dla publicznych funkcji (bo działają z `Get-Help`).

### Ścieżki — używaj `$PSCommandPath` nie `$PSScriptRoot`

`$PSScriptRoot` bywa pusty zależnie od sposobu wywołania. `$PSCommandPath` zawsze ma pełną ścieżkę aktualnego pliku:

```powershell
$ScriptDir = Split-Path $PSCommandPath -Parent
$ProjectRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent
```

## Workspace dev environment vs produkcja

Skrypty mają DWA tryby przechowywania configów/wyników:

| Tryb | Kiedy | Lokalizacja |
|---|---|---|
| **Produkcyjny** | Po instalacji przez `install.ps1`, uruchomienie ze skrótu Start Menu | Folder instalacji (default `C:\Transkrypcja\`, ale `install.ps1 -InstallDir D:\X` da `D:\X\`) |
| **Dev (workspace)** | Uruchomienie z IntelliJ przez Run config | `$PROJECT_DIR$\.workspace\` |

Mechanizm: env vars czytane przez skrypty, w innym wypadku relatywnie do **lokalizacji skryptu** (`$PSCommandPath`):

```powershell
$ProjectRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent
# Scripts/New-Transcription.ps1 -> .. -> Scripts/ -> .. -> root instalacji

$ConfigDir  = if ($env:TRANSCRIPTION_CONFIG_DIR) { $env:TRANSCRIPTION_CONFIG_DIR } else { $ProjectRoot }
$LogsRoot   = if ($env:TRANSCRIPTION_LOGS_DIR)   { $env:TRANSCRIPTION_LOGS_DIR }   else { Join-Path $ProjectRoot "logi" }
$DefaultOut = if ($env:TRANSCRIPTION_OUTPUT_DIR) { $env:TRANSCRIPTION_OUTPUT_DIR } else { Join-Path $ProjectRoot "Wyniki" }
$RuntimeFile = if ($env:TRANSCRIPTION_RUNTIME_FILE) { $env:TRANSCRIPTION_RUNTIME_FILE } else { Join-Path $ProjectRoot "runtime.json" }
$FarmDir    = if ($env:TRANSCRIPTION_FARM_DIR)   { $env:TRANSCRIPTION_FARM_DIR }   else { $cfg.queuePath }
```

**NIE hardkoduj `C:\Transkrypcja` jako fallback** — install.ps1 ma flagę `-InstallDir`, user może mieć aplikację gdziekolwiek.

IntelliJ run config (`.idea/runConfigurations/Manager.xml`) ustawia env vars inline w `SCRIPT_TEXT` przez `$env:...='...'` przed `Start-Process`.

`.workspace/` jest w gitignore (poza `.gitkeep`) — configs, logi, wyniki nie są commitowane.

Aktualne env-vary nadpisujące domyślne ścieżki:
- `TRANSCRIPTION_CONFIG_DIR` → katalog configów (default: root instalacji)
- `TRANSCRIPTION_LOGS_DIR` → katalog logów (default: `<root>\logi`)
- `TRANSCRIPTION_OUTPUT_DIR` → katalog wyników (default: `<root>\Wyniki`)
- `TRANSCRIPTION_RUNTIME_FILE` → ścieżka `runtime.json` (default: `<root>\runtime.json`)
- `TRANSCRIPTION_FARM_DIR` → folder kolejki farmy, nadpisuje `queuePath` z `Farm.config.json`

**Dodawanie kolejnych env vars** — dla nowego ustawienia konfiguracyjnego:
1. Skrypt: `$X = if ($env:TRANSCRIPTION_X) { $env:TRANSCRIPTION_X } else { default }`
2. IntelliJ run config: dodaj `<env name="TRANSCRIPTION_X" value="..." />`
3. CLAUDE.md: dodaj do tabeli wyżej

## Konfiguracja per-skrypt

Każdy Script ma swój config obok pliku w `src/`:
- `New-Transcription.config.json` (lastSourceDir, lastOutputDir, fp16)
- `Add-Chapters.config.json` (lastVideoDir, lastXmlDir)

Funkcje z `Config.ps1`:
- `Read-Config -Path $cfg -Default @{...}` — zwraca PSCustomObject, fallback default
- `Save-Config -Path $cfg -Data @{...}` — pełny overwrite
- `Update-Config -Path $cfg -Key 'x' -Value $v` — tylko jeden klucz, reszta zachowana

## Runtime portable / manifest ścieżek

Instalator pozwala wybrać per narzędzie (Python, Whisper, ffmpeg, mkvmerge) tryb
**systemowy** (winget/pip, jak dotąd) albo **portable** (do `runtime\` w folderze
instalacji). Ścieżki zapamiętane są w `runtime.json` w roocie instalacji:

- `mode: "portable"` → ścieżka **relatywna do roota** (`runtime\...`), liczona z `$PSCommandPath`.
- `mode: "system"`   → goła nazwa polecenia (`ffmpeg`), rozwiązywana przez PATH.

`src/lib/Runtime.ps1` (ładowana w Managerze po `Config.ps1`):
- `Get-RuntimeManifest` — czyta `runtime.json` (lub `$env:TRANSCRIPTION_RUNTIME_FILE`). Brak → `$null`.
- `Initialize-RuntimePath` — dopisuje katalogi portable na początek `$env:PATH` (whisper
  odpala ffmpeg przez subprocess i znajduje go po PATH — dlatego prepend, nie przepisywanie skryptów).

Brak `runtime.json` = pełna wsteczna kompatybilność (stare instalacje działają po staremu).
`runtime.json` i `runtime/` są w gitignore. Manifest zapisywany z `-Encoding UTF8`.

## Dashboard whispera — jak działa progress

1. Whisper z `--verbose True` wypisuje segmenty: `[00:05:42.500 --> 00:05:47.000]  tekst...`
2. Regex `'-->\s+(\d+(?::\d+)+\.\d+)\]'` wyciąga **końcowe** timestampy
3. Ostatni timestamp → sekundy przez `Convert-DurationToSeconds`
4. `% = sec_done / total_duration * 100` (total z Shell.Application Get-Details)
5. ETA = `elapsed * (100 - pct) / pct`

Cap progress na 99% w czasie pracy, 100% dopiero gdy `Process.HasExited` i `ExitCode -eq 0`.

Whisper na początku ~5s ładuje model — w tym czasie log pusty, progress = 0%. Normalne.

## Dodawanie nowej opcji menu

1. W `src/Scripts/` stwórz `New-CośTam.ps1` — może używać wszystkich funkcji z `lib/`
2. W `Manager.ps1` w `Show-MainMenu` dodaj wpis menu
3. W `switch ($c)` dodaj case wywołujący `Invoke-Script "New-CośTam.ps1"`

Wzorzec dla skryptu:

```powershell
# 1. Sprawdź zewnętrzne narzędzia
function Test-Tool { try { tool --help 2>&1 | Out-Null; return $LASTEXITCODE -eq 0 } catch { return $false } }
if (-not (Test-Tool)) { Show-Header...; Read-Host; return }

# 2. Wczytaj config
$ConfigPath = Join-Path (Split-Path $PSCommandPath -Parent | Split-Path -Parent) "Nazwa.config.json"
$cfg = Read-Config -Path $ConfigPath -Default @{ ... }

# 3. Etapy w pętli "z opcją cofnięcia" jeśli więcej niż 1 step:
while ($true) {
    # KROK 1: Show-Header + Select-Folder / Show-Picker / ...
    # KROK 2: ...
    # Podsumowanie + T/W/Q (start/wróć/anuluj)
    if ($decision -eq 'start') { break }
    if ($decision -eq 'cancel') { return }
}

# 4. Logika
# 5. Read-Host na końcu żeby user widział wyniki przed powrotem do menu
```

## Testowanie

Nie ma test framework'u (Pester nie był setupowany). Testy manualne:

1. **Manager (dev)** — uruchom Run config "Manager" z IntelliJ (ustawia env vars workspace) lub:
   ```powershell
   $env:TRANSCRIPTION_CONFIG_DIR = "$PWD\.workspace"
   . .\src\Manager.ps1
   ```
2. **Picker** — `Show-Picker -StartPath C:\` w shellu z załadowanym lib/
3. **Multi-picker** — to samo z `Show-MultiPicker`
3. **Dashboard** — uruchom `New-Transcription.ps1` na 2-3 krótkich plikach (30s każdy), zobacz czy progress się aktualizuje
4. **Install** — `.\install.ps1 -SkipDownload` na czystej VM (Windows Sandbox świetny do tego)

Częste regresje:
- Miganie po zmianie renderera (czy `[2J` się przypadkiem nie wkradł)
- Lag przy holdowaniu strzałki (czy coalesce nadal działa)
- Encoding polskich znaków w configu (czy `-Encoding UTF8` jest wszędzie)
- File locking gdy whisper aktywny (czy `Read-FileSafe` używane wszędzie)

## Debugowanie

Trace co PowerShell wykonuje:
```powershell
Set-PSDebug -Trace 1
# ... uruchom skrypt
Set-PSDebug -Off
```

Verbose process output (gdy whisper się wykrzacza):
```powershell
$env:PYTHONUNBUFFERED = "1"
& whisper "plik.mp4" --verbose True 2>&1 | Tee-Object -FilePath debug.log
```

Sprawdź czy ANSI VT mode włączony:
```powershell
. .\src\lib\Ansi.ps1
[Console]::Write("$([char]27)[31mtest$([char]27)[0m`n")
# Jeśli widzisz literalny "ESC[31mtest" zamiast czerwonego "test" — VT nie działa
```

## TODO / pomysły na rozwój

- Pester testy dla `Format.ps1` (najłatwiejsze do testowania — czyste funkcje)
- Auto-update przez `update.ps1` (git pull lub re-download ZIP, zachowując configi)
- Wsparcie dla Whisper.cpp (szybsze, mniejsze VRAM) jako alternatywny backend
- Eksport rozdziałów do innych formatów (FCPXML dla Final Cut, YouTube chapter syntax)
- Streamowanie odpowiedzi z LLM-ów (Claude/Gemini wspierają SSE) zamiast czekać na pełną odpowiedź
- Drag-and-drop plików na Manager.ps1 (PowerShell może odbierać argumenty)
- GUI fallback (Windows Forms) dla nie-terminalowych userów

## Read-Host pollution — KRYTYCZNE

PowerShell funkcja **zwraca cały pipeline output**, nie tylko `return`. `Read-Host` w funkcji bez przypisania zwraca string do pipeline'a — pollutuje return value funkcji.

```powershell
function Foo {
    Read-Host "naciśnij Enter"      # ZŁE — zwracana wartość trafia do output
    return $null
}
$result = Foo
# $result = @("", $null) zamiast $null
```

**Fix**: zawsze prefiksuj `$null = ` lub `[void]`:

```powershell
function Foo {
    $null = Read-Host "naciśnij Enter"   # ✓
    return $null
}
```

To samo dotyczy każdego cmdlet z return value (np. `New-Item`, `Add-Member`) — albo użyj `| Out-Null`, albo `$null = `, albo `[void](...)`. Nie polegaj na `if (-not $result)` gdy funkcja może zwrócić `@("", $null)` — jest truthy.

## Architektura i SOLID

Projekt stosuje **Single Responsibility** dosłownie — jeden plik, jedna odpowiedzialność. Struktury folderów grupują rzeczy po **concern** (rzecz którą plik załatwia), nie po typie pliku.

### Struktura `install/`

```
install/
├── Core/                      # primitives uzywane przez wszystko
│   ├── Logging.ps1           # Write-OK/Skip/Missing/Info, Test-Command
│   └── UI.ps1                # Ask-YN, Show-Header, Get-InstallDir, Show-Summary
├── Dependencies/              # klasy zaleznosci (1 plik = 1 klasa)
│   ├── Dependency.ps1        # abstract base
│   ├── PythonDependency.ps1
│   ├── PipDependency.ps1
│   ├── FfmpegDependency.ps1
│   ├── MkvmergeDependency.ps1
│   └── WhisperDependency.ps1
└── Phases/                    # workflow steps
    ├── Install.ps1
    ├── SystemCheck.ps1
    ├── CopyApp.ps1
    ├── Dependencies.ps1
    └── Shortcut.ps1
```

### Reguły SOLID i czystego kodu

- **S**: każdy plik ma JEDNĄ odpowiedzialność — jeśli musisz pisać "i" w opisie, rozdziel.
- **O**: nowa zależność → nowy plik w `Dependencies/` (autodiscovery przez `Get-ChildItem -Filter *Dependency.ps1`), bez edycji `Phases/Dependencies.ps1`.
- **L**: `Install()` i `Test()` zawsze zwracają `[bool]`, nigdy nie throw — nie łam kontraktu.
- **I**: klasa `Dependency` ma tylko `Test` i `Install`. YAGNI.
- **D**: `Phases/Dependencies.ps1` operuje na abstrakcji `Dependency`, nie na konkretnych klasach.
- **Plik = jedna eksportowana rzecz**, nazwa pliku == nazwa eksportu.
- Nie twórz `Utils/`, `Helpers/`, `Misc/` — to znak że nie wiesz po co plik istnieje.
- Entrypoint (`install.ps1`) to indeks kroków, nie implementacja.

### Reguła workflow: `git add` po każdej zmianie, commit tylko na żądanie

Po każdej operacji write/edit/move/delete plików — bez wyjątku — wykonaj:

```powershell
git add .
```

**Nigdy nie commituj samodzielnie.** Commit tylko gdy user wprost o to poprosi.

Powodów kilka:
- IDE pokazuje status (added/modified) — wiesz dokładnie co poszło i czy nic się nie zgubiło.
- `git diff --cached` pokazuje to co poleci na commit, łatwiej review przed `git commit`.
- W razie rozwałki łatwo wrócić do ostatniego dodanego stanu przez `git reset --hard`.
- Nieotrackowane pliki nie są zauważane przez większość narzędzi git (linters, hooks, gh CLI).

Wyjątek: jeśli świadomie testujesz coś co później ma być wyrzucone — ZRÓB osobny stash zamiast nie-stage'owania.

## Ważne — czego NIE robić

- **NIE używać Register-ObjectEvent** do capture stdout w pętlach pollujących
- **NIE używać cmd.exe wrappers** z polskimi znakami w ścieżkach
- **NIE używać `Clear-Host` w pętli renderu** (tylko raz przed lub przy resize)
- **NIE używać `Write-Host` w hot path** renderu (każdy `Write-Host` = pipeline overhead)
- **NIE importować lib/ jako `.psm1` moduł** — komplikacje z scope'em, dot-source jest prostszy
- **NIE zapisywać plików .ps1 bez UTF-8 BOM** — PS 5.1 przeczyta je w CP1250 i wszystkie polskie/unicode znaki staną się krzakami
- **NIE używać PS 7 syntax** (ternary, `??`, `?.`) — projekt musi działać na czystym Win10/11
- **NIE commitować `*.config.json`** — są w gitignore, mają lokalne ścieżki użytkownika

## Pipeline release i folder `build/`

Workflow `.github/workflows/release.yml` (runs-on `windows-latest`, Windows PowerShell 5.1)
odpala się na dwa triggery z różnym zakresem pracy.

### Co robi workflow

**Przy każdym pushu do `master`:**
1. `git describe --tags` → wersja (fallback `v0.0.0-<rev-count>-g<sha>`).
2. `Compress-Archive -Path src -DestinationPath src.zip`.
3. Buduje installer prerelease przez `build/Build-Installer.ps1` (URL do konkretnego tagu).
4. `gh release create <tag> ... --prerelease` — prerelease z `installer.ps1` + `src.zip`.

**Dodatkowo przy pushu tagu `v*` (np. `v1.2.3`):**
5. Buduje installer latest przez `build/Build-Installer.ps1` (URL do `releases/latest`).
6. Usuwa wszystkie pośrednie prereleasy + tagi pasujące do `v1.2.3-N-gabcdef` (poprzedni cykl).
7. `gh release create/upload latest` — stały Release `latest` dla one-linera
   `irm .../releases/latest/download/installer.ps1 | iex`.

`GH_TOKEN` = `${{ secrets.GITHUB_TOKEN }}`, `permissions: contents: write`.

### Folder `build/`

| Plik | Odpowiedzialność |
|---|---|
| `build/Build-Installer.ps1` | Skleja (konkatenacja z markerami `# === <relpath> ===`) nagłówek + `install/Core/*` + `install/Dependencies/*` (Dependency.ps1 pierwszy) + `install/Phases/*` + `build/installer-main.ps1` w jeden `installer.ps1`. Podstawia `@@TM_VERSION@@`/`@@TM_SRC_URL@@`. **Zapisuje wynik z UTF-8 BOM** (`[System.IO.File]::WriteAllText(... UTF8Encoding($true))`) — bez tego PS 5.1 zepsuje polskie znaki w komunikatach installera. Fail builda gdy brak pliku, zostały `@@`, lub błąd `PSParser::Tokenize`. |
| `build/installer-main.ps1` | „Ogon" doklejany na koniec `installer.ps1`: pobiera `$script:TM_SRC_URL` do TEMP, `Expand-Archive`, znajduje katalog z `src/`, woła `Invoke-Install`. NIE dot-source'uje `install/` (definicje są inline po konkatenacji). |

### Orkiestracja: `Invoke-Install`

`install/Phases/Install.ps1` zawiera `Invoke-Install -RepoRoot -InstallDir [-NoShortcut]
[-NoDeps] [-LogFile]` — wspólna sekwencja faz (Show-Header → Get-InstallDir →
Invoke-SystemCheck → Invoke-CopyApp → Invoke-Dependencies → Invoke-Shortcut →
Show-Summary). Używana przez `install.ps1` (dev/klon, ładuje `install/` z dysku) i przez
`build/installer-main.ps1` (release, definicje inline). RepoRoot = katalog zawierający `src/`.

`installer.ps1` i `src.zip` są w `.gitignore` (generowane w CI, nie commitowane).

## Linki dokumentacja

- PowerShell 5.1: https://learn.microsoft.com/en-us/powershell/scripting/overview?view=powershell-5.1
- Approved Verbs: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
- Whisper CLI: https://github.com/openai/whisper#command-line-usage
- mkvmerge --chapters: https://mkvtoolnix.download/doc/mkvmerge.html#mkvmerge.description.chapters
- Matroska Chapters XML: https://mkvtoolnix.download/doc/mkvmerge.html#mkvmerge.chapter_files
- winget docs: https://learn.microsoft.com/en-us/windows/package-manager/winget/
