#Requires -Version 5.1
<#
    AllInOne.Core — plattformneutrale Logik.

    Dieses Modul enthaelt bewusst KEINEN WinForms-, Registry- oder CIM-Code.
    Alles hier ist reine Rechnung auf Ein- und Ausgabewerten und laeuft damit
    auf Windows, macOS und Linux — und ist ohne Windows testbar.

    Plattformabhaengige Sonden liegen in AllInOne.Windows.psm1.
#>

Set-StrictMode -Version Latest

function Get-DefaultConfig {
    <#
    .SYNOPSIS
        Liefert die Standardkonfiguration als PSCustomObject.
    .DESCRIPTION
        Dient als Basis fuer Import-ToolConfig. Jeder Wert, den config.json
        nicht setzt, kommt von hier. Pfade sind absichtlich leer: ein leerer
        Pfad markiert ein Werkzeug als "nicht konfiguriert" und deaktiviert
        dessen Schaltflaeche, statt beim Klick ins Leere zu laufen.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    [PSCustomObject]@{
        Window = [PSCustomObject]@{
            Title        = 'All-in-One — Toolbox'
            ButtonWidth  = 170
            ButtonHeight = 26
            Margin       = 14
            Spacing      = 4
            HeaderHeight = 20
            GroupGap     = 12
            MaxColumn    = 340
        }
        Paths  = [PSCustomObject]@{
            CCleaner      = ''
            DeviceCleanup = ''
            SnapShot      = ''
            Vnc           = ''
            TimeServerReg = ''
        }
        Network = [PSCustomObject]@{
            ShareUnc    = ''
            DriveLetter = 'Y'
        }
        Report = [PSCustomObject]@{
            OutputPath = ''
        }
    }
}

function Merge-ConfigObject {
    <#
    .SYNOPSIS
        Legt eine Benutzerkonfiguration ueber die Standardwerte.
    .DESCRIPTION
        Rekursiv, aber bewusst konservativ: es werden ausschliesslich Schluessel
        uebernommen, die in den Standardwerten existieren. Tippfehler in
        config.json erzeugen so keine stillen Geisterwerte, sondern werden
        ignoriert und ueber -WarningAction sichtbar gemacht.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Default,
        [Parameter()][PSObject]$Override
    )

    $result = [PSCustomObject]@{}
    foreach ($property in $Default.PSObject.Properties) {
        $result | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
    }
    if ($null -eq $Override) { return $result }

    foreach ($property in $Override.PSObject.Properties) {
        $name = $property.Name
        if (-not $Default.PSObject.Properties.Name.Contains($name)) {
            Write-Warning "Unbekannter Konfigurationsschluessel wird ignoriert: '$name'"
            continue
        }
        $defaultValue = $Default.$name
        if ($defaultValue -is [PSCustomObject] -and $property.Value -is [PSObject] -and $property.Value -isnot [string]) {
            $result.$name = Merge-ConfigObject -Default $defaultValue -Override $property.Value
        }
        else {
            $result.$name = $property.Value
        }
    }
    return $result
}

function Import-ToolConfig {
    <#
    .SYNOPSIS
        Laedt config.json und mischt sie ueber die Standardwerte.
    .DESCRIPTION
        Fehlt die Datei, gelten die Standardwerte — das Skript startet also auch
        ohne Konfiguration und zeigt die betroffenen Schaltflaechen deaktiviert an.
        Ist die Datei vorhanden aber kaputt, wird bewusst geworfen: eine stillschweigend
        ignorierte Konfiguration ist schlimmer als ein klarer Abbruch.
    .PARAMETER Path
        Pfad zur config.json.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $default = Get-DefaultConfig
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Verbose "Keine Konfiguration unter '$Path' — verwende Standardwerte."
        return $default
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Verbose "Konfiguration '$Path' ist leer — verwende Standardwerte."
        return $default
    }

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Konfiguration '$Path' ist kein gueltiges JSON: $($_.Exception.Message)"
    }

    return Merge-ConfigObject -Default $default -Override $parsed
}

function Get-ToolLayout {
    <#
    .SYNOPSIS
        Berechnet Position und Groesse aller Schaltflaechen aus der Werkzeugliste.
    .DESCRIPTION
        Ersetzt die frueher von Hand gezaehlten X/Y-Koordinaten. Werkzeuge werden in
        der Reihenfolge ihres ersten Auftretens nach Group gebuendelt, jede Gruppe
        bekommt eine Ueberschrift, und Gruppen fliessen spaltenweise. Passt eine
        Gruppe nicht mehr in die laufende Spalte, beginnt eine neue.

        Rueckgabe ist reine Geometrie — kein WinForms-Objekt. Genau deshalb laesst
        sich die Anordnung ohne Windows testen.
    .PARAMETER Tool
        Werkzeugliste. Jedes Element braucht Group und Label.
    .OUTPUTS
        PSCustomObject mit Items (Label, Group, X, Y, Width, Height, Kind) sowie
        Width und Height des benoetigten Fensterinhalts.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tool,
        [ValidateRange(40, 600)][int]$ButtonWidth = 170,
        [ValidateRange(12, 200)][int]$ButtonHeight = 26,
        [ValidateRange(0, 100)][int]$Margin = 14,
        [ValidateRange(0, 50)][int]$Spacing = 4,
        [ValidateRange(0, 100)][int]$HeaderHeight = 20,
        [ValidateRange(0, 100)][int]$GroupGap = 12,
        [ValidateRange(100, 4000)][int]$MaxColumn = 340
    )

    $items = New-Object System.Collections.Generic.List[object]
    if ($Tool.Count -eq 0) {
        return [PSCustomObject]@{
            Items  = @()
            Width  = ($Margin * 2) + $ButtonWidth
            Height = ($Margin * 2)
        }
    }

    # Gruppen in Reihenfolge des ersten Auftretens — Group-Object sortiert sonst um.
    $groupOrder = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Tool) {
        if (-not $groupOrder.Contains($entry.Group)) { $groupOrder.Add($entry.Group) }
    }

    $x = $Margin
    $y = $Margin
    $maxY = $Margin

    foreach ($groupName in $groupOrder) {
        $members = @($Tool | Where-Object { $_.Group -eq $groupName })
        $blockHeight = $HeaderHeight + $Spacing + ($members.Count * ($ButtonHeight + $Spacing))

        # Spaltenumbruch nur, wenn die Spalte nicht ohnehin leer ist — sonst
        # wuerde eine ueberlange Gruppe endlos neue leere Spalten erzeugen.
        if ($y -ne $Margin -and ($y + $blockHeight) -gt $MaxColumn) {
            $x += $ButtonWidth + $Margin
            $y = $Margin
        }

        $items.Add([PSCustomObject]@{
            Label = $groupName; Group = $groupName; Kind = 'Header'
            X = $x; Y = $y; Width = $ButtonWidth; Height = $HeaderHeight
        })
        $y += $HeaderHeight + $Spacing

        foreach ($member in $members) {
            $items.Add([PSCustomObject]@{
                Label = $member.Label; Group = $groupName; Kind = 'Button'
                X = $x; Y = $y; Width = $ButtonWidth; Height = $ButtonHeight
            })
            $y += $ButtonHeight + $Spacing
        }

        if ($y -gt $maxY) { $maxY = $y }
        $y += $GroupGap
    }

    return [PSCustomObject]@{
        Items  = $items.ToArray()
        Width  = $x + $ButtonWidth + $Margin
        Height = $maxY + $Margin
    }
}

function Test-ToolEnabled {
    <#
    .SYNOPSIS
        Entscheidet, ob ein Werkzeug bedienbar ist.
    .DESCRIPTION
        Werkzeuge ohne RequiresPath sind immer aktiv. Werkzeuge mit RequiresPath
        brauchen einen nicht-leeren, existierenden Pfad. Damit ersetzt eine
        deaktivierte Schaltflaeche den frueheren Laufzeitfehler beim Klick.
    .PARAMETER Tool
        Ein Werkzeugeintrag.
    .PARAMETER Config
        Die geladene Konfiguration.
    .PARAMETER TestPath
        Testfunktion fuer Pfade. Ausschliesslich fuer Tests ueberschreibbar.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][object]$Tool,
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [scriptblock]$TestPath = { param($p) Test-Path -LiteralPath $p }
    )

    if (-not $Tool.PSObject.Properties.Name.Contains('RequiresPath')) { return $true }
    $key = $Tool.RequiresPath
    if ([string]::IsNullOrWhiteSpace($key)) { return $true }

    if (-not $Config.Paths.PSObject.Properties.Name.Contains($key)) {
        Write-Warning "Werkzeug '$($Tool.Label)' verweist auf unbekannten Pfadschluessel '$key'."
        return $false
    }

    $value = $Config.Paths.$key
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    return [bool](& $TestPath $value)
}

function Format-SystemReport {
    <#
    .SYNOPSIS
        Formatiert erhobene Systemfakten als Textbericht.
    .DESCRIPTION
        Bewusst getrennt vom Einsammeln der Daten: das Einsammeln braucht Windows,
        das Formatieren nicht. Dadurch ist die Berichtsform ohne Windows testbar.
    .PARAMETER Fact
        Geordnete Schluessel/Wert-Paare, gruppiert nach Abschnitt.
    .PARAMETER Title
        Ueberschrift des Berichts.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Fact,
        [string]$Title = 'System-Bericht'
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($Title)
    $lines.Add(('=' * $Title.Length))
    $lines.Add('')
    $lines.Add("Erstellt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add('')

    foreach ($section in $Fact.Keys) {
        $lines.Add($section)
        $lines.Add('-' * $section.Length)
        $values = $Fact[$section]
        if ($null -eq $values -or $values.Count -eq 0) {
            $lines.Add('  (keine Daten)')
        }
        else {
            $width = ($values.Keys | Measure-Object -Property Length -Maximum).Maximum
            foreach ($key in $values.Keys) {
                $padded = $key.PadRight($width)
                $lines.Add("  ${padded} : $($values[$key])")
            }
        }
        $lines.Add('')
    }

    return $lines.ToArray()
}

Export-ModuleMember -Function Get-DefaultConfig, Merge-ConfigObject, Import-ToolConfig,
                              Get-ToolLayout, Test-ToolEnabled, Format-SystemReport
