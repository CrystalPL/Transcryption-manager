# Transcription Manager

Aplikacja PowerShell do automatycznego tworzenia transkrypcji nagrań i wpinania rozdziałów do plików MKV.

## Co potrafi

- **Generuje transkrypcje** (`.srt`, `.vtt`, `.txt`) z plików wideo używając Whispera
- **Wpina rozdziały XML** do plików MKV bez ponownego kodowania

## Instalacja

Otwórz **PowerShell** i wklej:

```powershell
irm https://raw.githubusercontent.com/CrystalPL/Transcription-manager/master/install.ps1 | iex
```

Instalator zapyta gdzie zainstalować aplikację (domyślnie `C:\Transkrypcja`), sprawdzi czego brakuje, doinstaluje brakujące programy i doda skrót do menu Start.

## Wymagania

- Windows 10 lub 11
- Połączenie z internetem (do pobrania zależności)
- Karta NVIDIA z min. 4 GB VRAM (opcjonalnie — bez niej Whisper działa na CPU, ale wolniej)

Instalator sam zadba o resztę. Aplikacja jest przetestowana z następującymi wersjami:

| Składnik | Wersja |
|---|---|
| Python | 3.14 |
| pip | 26.1 |
| openai-whisper | 20250625 |
| PyTorch (CUDA 12.6) | 2.12 |
| ffmpeg | 8.x (build październik 2025) |
| MKVToolNix | 98.0 |

Instalator pobiera najnowsze dostępne wersje, więc Twoje będą wyższe albo równe — to OK.

## Jak używać

Wciśnij **klawisz Windows** i wpisz **Zarządzanie transkrypcją** → uruchom.

Pojawi się menu z dwiema opcjami:

### 1. Tworzenie transkrypcji

1. Wybierz folder z nagraniami
2. Zaznacz pliki strzałkami i Spacją (lub `A` żeby wszystkie)
3. Wybierz folder docelowy
4. Potwierdź → na ekranie pojawi się dashboard z postępem dla każdego pliku

Możesz wcisnąć numer pliku (1-9) żeby zobaczyć live logi Whispera w trakcie pracy. `Esc` cofa do dashboardu.

Wyniki (`.srt`, `.vtt`, `.txt`, `.json`) trafiają do folderu docelowego, w podfolderze nazwanym jak plik źródłowy.

### 2. Dodawanie rozdziałów do nagrania

1. Wybierz plik MKV/MP4 do którego dodajesz rozdziały
2. Wybierz plik XML z rozdziałami (format Matroska Chapters)
3. Aplikacja stworzy nowy plik z dopiskiem `- timeline.mkv`
4. Opcjonalnie: zastąp oryginał nowym plikiem

Plik XML możesz wygenerować dowolnym narzędziem AI z transkrypcji `.srt` (np. ChatGPT, Claude, Gemini).

## Aktualizacja

Ponowne uruchomienie instalatora podmieni pliki aplikacji, zachowując Twoje konfiguracje i wyniki:

```powershell
irm https://raw.githubusercontent.com/CrystalPL/Transcription-manager/master/install.ps1 | iex
```

## Odinstalowanie

Z folderu instalacji uruchom:

```powershell
C:\Transkrypcja\uninstall.ps1
```

(albo z innego folderu jeśli zainstalowałeś gdzie indziej)

Usuwa aplikację i skrót Start Menu. Nie usuwa Python/ffmpeg/MKVToolNix — mogłyby być używane przez inne programy. Pyta osobno o usunięcie folderów z wynikami transkrypcji i logami.

## Pomoc

Coś nie działa? Otwórz [Issue na GitHubie](https://github.com/CrystalPL/Transcription-manager/issues).
