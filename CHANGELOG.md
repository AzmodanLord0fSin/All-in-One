# Änderungen

## 2026 — Überarbeitung

Die Fassung von 2023 lief nie durchgehend fehlerfrei. Der Parser meldete zwar keine
Syntaxfehler, aber eine Reihe von Aufrufen scheiterte erst zur Laufzeit. Der Umbau hat
die Logik von der Oberfläche getrennt, das Verhalten testbar gemacht und die konkreten
Fehler behoben.

### Behobene Fehler aus der Ursprungsfassung

| Stelle | Problem | Behebung |
|---|---|---|
| Schaltflächen `LUGImage`, `szg`, `hn` | riefen nie definierte Funktionen auf → „term is not recognized" beim Klick | Werkzeugliste enthält nur noch tatsächlich vorhandene Aktionen |
| `else { }` ohne `if` | Laufzeitfehler beim Laden | entfernt |
| `$PWStr = = (...)` | doppeltes `=`; Variable vor Zuweisung benutzt | Passwort-Behandlung ersetzt durch `PSCredential` |
| `checkbox1` / `checkbox2` | riefen nie definiertes `checkbox_test` auf | entfernt |
| `$objForm.Controls.Add(...)` | `$objForm` nie erzeugt → Null-Reference | entfernt |
| `Comboboxl`, `$Namel` | Tippfehler → Typ nicht gefunden / stiller `$null` | entfernt |
| Escape-Taste: `$fenster.close` | ohne `()` — Methode wird gelesen, nie gerufen | `$form.Close()` |
| `Font = "Callibri,10"` | Tippfehler → Fallback-Font | „Segoe UI" |

### Sicherheit

- **Netzlaufwerk-Anmeldung.** Vorher wanderte das Passwort als Klartext-Argument durch
  `net use ... /user:name passwort` — jeder lokale Prozessmonitor liest die Kommandozeile
  mit. Jetzt `Get-Credential` + `New-PSDrive`; das Passwort bleibt ein `SecureString`.
- **`ConvertTo-SecureString -AsPlainText`** (von PSScriptAnalyzer als *Error* markiert)
  ersatzlos entfernt.
- **Autologon-Passwort.** Der Registry-Wert `DefaultPassword` wird bewusst nicht mehr
  ausgelesen — für „Autologon aktiv, für wen?" ist er unnötig.
- **AD-Kontonamen** aus Kombinationsfeld und einem Kommentar entfernt. (Zur Historie
  siehe unten.)

### Kompatibilität

- **`Get-WmiObject` → `Get-CimInstance`** (7 Stellen). WMI-Cmdlets wurden in PowerShell 6
  entfernt; die Ursprungsfassung lief damit nur unter Windows PowerShell 5.1. CIM läuft
  auf beiden.
- CI prüft die Kernlogik gegen PowerShell 7 (Linux/macOS/Windows) **und** Windows
  PowerShell 5.1.

### Struktur

- **Automatische Anordnung** statt 17 handgezählter X/Y-Koordinaten. Ein Werkzeug ist
  jetzt ein Listeneintrag; Position und Fenstergröße rechnet `Get-ToolLayout`.
- **Modultrennung:** plattformneutrale Logik (`AllInOne.Core.psm1`) vom Windows-Zugriff
  (`AllInOne.Windows.psm1`) getrennt. Erstere ist ohne Windows testbar.
- **Konfiguration ausgelagert** nach `config.json`; im Code standen vorher fest
  verdrahtete Pfade wie `C:\BEISPIELPFAD\...`.
- **Deaktivierte statt scheiternde Schaltflächen:** fehlt ein Pfad, ist der Knopf grau
  statt beim Klick abzustürzen.
- **26 Pester-Tests** und eine PSScriptAnalyzer-Konfiguration hinzugefügt; beides in CI.

### Offen

- Nicht auf einem Windows-Rechner im Betrieb verifiziert. Registry- und CIM-Pfade
  (`Get-RdpStatus`, `Get-AutologonStatus`, `Get-SystemInfo`, `Connect-NetworkShare`)
  sind gegen Parser und Linter geprüft, aber nicht auf echter Hardware ausgeführt.
- Die AD-Namen stehen weiterhin in den beiden Commits von 2023 (`dcc4036`, `479e256`).
  Sie aus dem aktuellen Stand zu entfernen tilgt sie nicht aus der Historie — dafür
  wäre ein History-Rewrite (`git filter-repo`) plus Force-Push nötig. Bewusst offen
  gelassen als Entscheidung des Repository-Eigentümers.
