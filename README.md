# All-in-One

Ein Werkzeugkasten für den Windows-Arbeitsplatz-Support: häufige Handgriffe — Systembericht,
RDP- und Autologon-Status, Netzlaufwerk verbinden, Standardwerkzeuge starten — liegen auf je
einer Schaltfläche in einem WinForms-Fenster.

[![CI](https://github.com/AzmodanLord0fSin/All-in-One/actions/workflows/ci.yml/badge.svg)](https://github.com/AzmodanLord0fSin/All-in-One/actions/workflows/ci.yml)

---

## Herkunft

Die erste Fassung entstand 2023 im Helpdesk-Alltag und wurde beim Jobwechsel eingefroren —
mit toten Funktionsaufrufen, handgezählten Pixelkoordinaten und einem Klartextpasswort in
der Kommandozeile. 2026 überarbeitet: Logik von der Oberfläche getrennt, getestet, unter CI
gestellt. Was der Umbau im Einzelnen geändert hat, steht in [CHANGELOG.md](CHANGELOG.md).

## Schnellstart

```powershell
git clone https://github.com/AzmodanLord0fSin/All-in-One.git
cd All-in-One
Copy-Item config.example.json config.json   # Pfade eintragen
powershell.exe -ExecutionPolicy Bypass -File .\AllInOne.ps1
```

Ohne `config.json` startet das Fenster trotzdem — Werkzeuge ohne hinterlegten Pfad erscheinen
dann deaktiviert und erklären per Tooltip, welcher Schlüssel fehlt.

Die Anordnung lässt sich ohne Windows und ohne Fenster prüfen:

```console
$ pwsh -File ./AllInOne.ps1 -WhatIfLayout
Anordnung: 382 x 268 Pixel, 14 Elemente

Kind   Group     Label                    X   Y Width Height
----   -----     -----                    -   - ----- ------
Header Diagnose  Diagnose                14  14   170     20
Button Diagnose  Systembericht           14  38   170     26
...
```

## Aufbau

| Datei | Inhalt | Läuft auf |
|---|---|---|
| `AllInOne.ps1` | Werkzeugliste, Oberfläche, Aktionen | Windows |
| `src/AllInOne.Core.psm1` | Anordnung, Konfiguration, Berichtsformat — reine Rechnung | überall |
| `src/AllInOne.Windows.psm1` | Registry-, CIM- und Prozesszugriffe | Windows |
| `tests/AllInOne.Core.Tests.ps1` | 26 Pester-Tests der Kernlogik | überall |

Die Trennung hat einen praktischen Grund: Alles, was Windows braucht, liegt in genau einer
Datei. Der Rest ist ohne Windows testbar — und wird in CI auf Linux, macOS und Windows
gegen PowerShell 7 sowie gegen Windows PowerShell 5.1 geprüft.

## Ein Werkzeug hinzufügen

Ein Eintrag in `$Tools` in [`AllInOne.ps1`](AllInOne.ps1) — Position und Fenstergröße
berechnen sich daraus:

```powershell
[PSCustomObject]@{
    Group        = 'Werkzeuge'      # bündelt unter dieser Überschrift
    Label        = 'Mein Werkzeug'  # Beschriftung
    RequiresPath = 'MeinTool'       # optional: Schlüssel unter Paths in config.json
    Action       = { Invoke-ConfiguredTool 'MeinTool' }
}
```

Vorher standen hier 17 Aufrufe mit von Hand gezählten X/Y-Werten. Eine Schaltfläche
verschieben hieß: alle darunter neu rechnen.

## Konfiguration

`config.json` (Vorlage: `config.example.json`) ist per `.gitignore` ausgeschlossen — lokale
Pfade und Servernamen gehören nicht ins Repository. Unbekannte Schlüssel werden ignoriert
und gemeldet, kaputtes JSON bricht mit klarer Meldung ab statt still Standardwerte zu nehmen.

## Entwicklung

```powershell
Invoke-Pester ./tests                                                  # Tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1   # Linter
```

Beides läuft auch auf macOS und Linux. Stand der letzten lokalen Prüfung: 26 Tests grün,
0 Linter-Befunde bei Severity `Error` und `Warning`.

## Grenzen

- **Die Oberfläche braucht Windows.** `System.Windows.Forms` gibt es unter PowerShell 7 auf
  macOS und Linux nicht. Dort funktionieren Tests und `-WhatIfLayout`, nicht das Fenster.
- **Nicht auf echter Hardware verifiziert.** Der Umbau wurde gegen Parser, Linter und
  Testsuite geprüft, nicht auf einem Windows-Rechner im Betrieb. Registry- und CIM-Pfade
  sind ungetestet.
- **Kein Ersatz für Verwaltungswerkzeuge.** Das hier ist eine Klick-Abkürzung für einen
  Einzelarbeitsplatz, keine Flottenverwaltung.

## Lizenz

[MIT](LICENSE)
