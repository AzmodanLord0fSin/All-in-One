#Requires -Version 5.1
<#
.SYNOPSIS
    All-in-One — Werkzeugkasten fuer den Windows-Arbeitsplatz-Support.

.DESCRIPTION
    Eine WinForms-Oberflaeche, die haeufige Support-Handgriffe auf je eine
    Schaltflaeche legt: Systembericht, RDP- und Autologon-Status, Netzlaufwerk
    verbinden, konfigurierte Werkzeuge starten.

    Die Anordnung wird aus der Werkzeugliste unten berechnet, nicht von Hand
    positioniert. Ein neues Werkzeug ist genau ein Eintrag in $Tools.

    Alle Pfade stehen in config.json (Vorlage: config.example.json). Werkzeuge
    ohne gueltigen Pfad erscheinen deaktiviert statt beim Klick zu scheitern.

.PARAMETER ConfigPath
    Abweichender Pfad zur Konfiguration.

.PARAMETER WhatIfLayout
    Gibt die berechnete Anordnung als Text aus und oeffnet kein Fenster.
    Damit laesst sich die Anordnung auch ohne Windows pruefen.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\AllInOne.ps1

.EXAMPLE
    pwsh -File ./AllInOne.ps1 -WhatIfLayout
    Zeigt die Anordnung als Tabelle — laeuft auf jeder Plattform.

.NOTES
    Die Oberflaeche setzt Windows voraus (System.Windows.Forms).
    Die Logik in src/AllInOne.Core.psm1 ist plattformneutral und getestet.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$WhatIfLayout
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptRoot (Join-Path 'src' 'AllInOne.Core.psm1')) -Force
Import-Module (Join-Path $scriptRoot (Join-Path 'src' 'AllInOne.Windows.psm1')) -Force

if (-not $ConfigPath) { $ConfigPath = Join-Path $scriptRoot 'config.json' }
$Config = Import-ToolConfig -Path $ConfigPath

#region Aktionen
function Show-Result {
    param([string]$Message, [string]$Title = 'All-in-One')
    if ($WhatIfLayout) { Write-Output "[$Title] $Message"; return }
    [System.Windows.Forms.MessageBox]::Show($Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Invoke-SystemReport {
    $facts  = Get-SystemInfo
    $report = Format-SystemReport -Fact $facts -Title 'All-in-One - Systembericht'

    $target = $Config.Report.OutputPath
    if ([string]::IsNullOrWhiteSpace($target)) {
        $name   = 'PC-Info_{0}_{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd_HHmm')
        $target = Join-Path ([System.IO.Path]::GetTempPath()) $name
    }

    $report | Set-Content -LiteralPath $target -Encoding UTF8
    Show-Result "Bericht geschrieben nach:`n$target" 'Systembericht'
    Start-Process -FilePath 'notepad.exe' -ArgumentList $target
}

function Invoke-ConnectShare {
    $share = $Config.Network.ShareUnc
    if ([string]::IsNullOrWhiteSpace($share)) {
        Show-Result 'In config.json ist unter Network.ShareUnc keine Freigabe hinterlegt.' 'Netzlaufwerk'
        return
    }
    # Get-Credential statt eigenem Passwortfeld: das Passwort bleibt ein
    # SecureString und wandert nie durch eine Kommandozeile.
    $cred = Get-Credential -Message "Anmeldedaten fuer $share"
    if (-not $cred) { return }

    $result = Connect-NetworkShare -UncPath $share -DriveLetter $Config.Network.DriveLetter `
                                   -Credential $cred -Confirm:$false
    Show-Result $result.Summary 'Netzlaufwerk'
}

function Invoke-ConfiguredTool {
    param([Parameter(Mandatory)][string]$Key)
    $result = Start-ConfiguredProcess -Path $Config.Paths.$Key -Confirm:$false
    if (-not $result.Success) { Show-Result $result.Summary 'Werkzeug' }
}

function Invoke-TimeServerImport {
    $regFile = $Config.Paths.TimeServerReg
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Registry-Datei importieren?`n$regFile`n`nDas veraendert die Registry dieses Rechners.",
        'Zeitserver setzen',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $result = Start-ConfiguredProcess -Path (Join-Path $env:WINDIR 'regedit.exe') `
                                      -ArgumentList @('/s', $regFile) -Confirm:$false
    Show-Result $result.Summary 'Zeitserver'
}
#endregion

#region Werkzeugliste
# Ein Werkzeug = ein Eintrag. Group bestimmt die Buendelung, die Reihenfolge hier
# bestimmt die Reihenfolge im Fenster. RequiresPath verweist auf einen Schluessel
# unter Paths in config.json; fehlt der Pfad, wird die Schaltflaeche deaktiviert.
# Frueher standen hier 17 Aufrufe mit handgezaehlten X/Y-Werten — ein Button
# verschieben hiess: alle darunter neu rechnen.
$Tools = @(
    [PSCustomObject]@{ Group = 'Diagnose'; Label = 'Systembericht';    Action = { Invoke-SystemReport } }
    [PSCustomObject]@{ Group = 'Diagnose'; Label = 'RDP-Status';       Action = { Show-Result (Get-RdpStatus).Summary 'RDP' } }
    [PSCustomObject]@{ Group = 'Diagnose'; Label = 'Autologon-Status'; Action = { Show-Result (Get-AutologonStatus).Summary 'Autologon' } }

    [PSCustomObject]@{ Group = 'Netzwerk'; Label = 'Netzlaufwerk verbinden'; Action = { Invoke-ConnectShare } }

    [PSCustomObject]@{ Group = 'Werkzeuge'; Label = 'Editor'; Action = { Start-ConfiguredProcess -Path (Join-Path $env:WINDIR 'System32\notepad.exe') -Confirm:$false | Out-Null } }
    [PSCustomObject]@{ Group = 'Werkzeuge'; Label = 'CCleaner';         RequiresPath = 'CCleaner';      Action = { Invoke-ConfiguredTool 'CCleaner' } }
    [PSCustomObject]@{ Group = 'Werkzeuge'; Label = 'DeviceCleanup';    RequiresPath = 'DeviceCleanup'; Action = { Invoke-ConfiguredTool 'DeviceCleanup' } }
    [PSCustomObject]@{ Group = 'Werkzeuge'; Label = 'SnapShot';         RequiresPath = 'SnapShot';      Action = { Invoke-ConfiguredTool 'SnapShot' } }
    [PSCustomObject]@{ Group = 'Werkzeuge'; Label = 'VNC installieren'; RequiresPath = 'Vnc';           Action = { Invoke-ConfiguredTool 'Vnc' } }

    [PSCustomObject]@{ Group = 'System'; Label = 'Zeitserver setzen'; RequiresPath = 'TimeServerReg'; Action = { Invoke-TimeServerImport } }
)
#endregion

#region Anordnung
$w = $Config.Window
$layout = Get-ToolLayout -Tool $Tools `
    -ButtonWidth $w.ButtonWidth -ButtonHeight $w.ButtonHeight -Margin $w.Margin `
    -Spacing $w.Spacing -HeaderHeight $w.HeaderHeight -GroupGap $w.GroupGap -MaxColumn $w.MaxColumn

if ($WhatIfLayout) {
    Write-Output "Anordnung: $($layout.Width) x $($layout.Height) Pixel, $($layout.Items.Count) Elemente"
    Write-Output ''
    $layout.Items | Format-Table Kind, Group, Label, X, Y, Width, Height -AutoSize
    return
}
#endregion

#region Oberflaeche
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = $w.Title
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9)
$form.ClientSize      = New-Object System.Drawing.Size($layout.Width, ($layout.Height + 28))

$byLabel = @{}
foreach ($tool in $Tools) { $byLabel[$tool.Label] = $tool }

foreach ($item in $layout.Items) {
    if ($item.Kind -eq 'Header') {
        $header           = New-Object System.Windows.Forms.Label
        $header.Text      = $item.Label
        $header.Location  = New-Object System.Drawing.Point($item.X, $item.Y)
        $header.Size      = New-Object System.Drawing.Size($item.Width, $item.Height)
        $header.Font      = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
        $header.ForeColor = [System.Drawing.SystemColors]::GrayText
        $form.Controls.Add($header)
        continue
    }

    $tool    = $byLabel[$item.Label]
    $enabled = Test-ToolEnabled -Tool $tool -Config $Config

    $button          = New-Object System.Windows.Forms.Button
    $button.Text     = $item.Label
    $button.Location = New-Object System.Drawing.Point($item.X, $item.Y)
    $button.Size     = New-Object System.Drawing.Size($item.Width, $item.Height)
    $button.Enabled  = $enabled
    if (-not $enabled) {
        $tip = New-Object System.Windows.Forms.ToolTip
        $tip.SetToolTip($button, "Kein gueltiger Pfad in config.json unter Paths.$($tool.RequiresPath)")
    }

    # GetNewClosure friert $action pro Durchlauf ein. Ohne das zeigen am Ende
    # alle Schaltflaechen auf das zuletzt zugewiesene Werkzeug.
    # Jede Aktion faengt ihre eigenen Fehler ab: ein kaputtes Werkzeug darf
    # nicht das ganze Fenster mitreissen.
    $action = $tool.Action
    $button.Add_Click({
        try { & $action }
        catch { Show-Result "Fehler: $($_.Exception.Message)" 'All-in-One' }
    }.GetNewClosure())

    $form.Controls.Add($button)
}

$configNote = if (Test-Path -LiteralPath $ConfigPath) { $ConfigPath } else { 'Standardwerte (keine config.json)' }
$status           = New-Object System.Windows.Forms.Label
$status.Text      = "Konfiguration: $configNote"
$status.Location  = New-Object System.Drawing.Point($w.Margin, $layout.Height)
$status.Size      = New-Object System.Drawing.Size(($layout.Width - (2 * $w.Margin)), 20)
$status.ForeColor = [System.Drawing.SystemColors]::GrayText
$form.Controls.Add($status)

# Escape schliesst das Fenster. Frueher stand hier $fenster.close ohne Klammern —
# das liest die Methode nur aus und ruft sie nie auf.
$form.KeyPreview = $true
$form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $form.Close() } }.GetNewClosure())

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
$form.Dispose()
#endregion
