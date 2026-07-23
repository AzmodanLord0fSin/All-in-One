#Requires -Version 5.1
<#
    AllInOne.Windows — plattformabhaengige Sonden.

    Alles, was Registry, CIM oder Windows-Binaries braucht, liegt hier und nur hier.
    Get-WmiObject ist durchgehend durch Get-CimInstance ersetzt: WMI-Cmdlets wurden
    in PowerShell 6 entfernt, CIM laeuft ab 3.0 und damit auch unter 5.1.
#>

Set-StrictMode -Version Latest

function Test-WindowsPlatform {
    <#
    .SYNOPSIS
        Prueft, ob die Sitzung auf Windows laeuft.
    .DESCRIPTION
        Die automatische Variable $IsWindows existiert erst ab PowerShell 6.
        Statt sie abzufragen wird die Edition geprueft: "Desktop" ist immer
        Windows PowerShell 5.1 und damit per Definition Windows. Fuer alles
        andere entscheidet die Laufzeit selbst.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)
}

function Assert-WindowsPlatform {
    [CmdletBinding()]
    param([string]$Feature = 'Diese Funktion')
    if (-not (Test-WindowsPlatform)) {
        throw "$Feature setzt Windows voraus und ist auf dieser Plattform nicht verfuegbar."
    }
}

function Get-RdpStatus {
    <#
    .SYNOPSIS
        Liest den RDP-Zustand aus der Registry.
    .DESCRIPTION
        Ersetzt die frueheren verschachtelten MessageBox-Aufrufe: die Funktion
        liefert jetzt ein Objekt zurueck, die Anzeige entscheidet die Oberflaeche.
        Fehlende Registry-Pfade werden abgefangen statt zu werfen.
    .OUTPUTS
        PSCustomObject mit Enabled, NlaRequired und Summary.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Assert-WindowsPlatform -Feature 'Die RDP-Pruefung'

    $serverKey = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
    $tcpKey    = 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

    $denyValue = $null
    if (Test-Path -LiteralPath $serverKey) {
        $denyValue = (Get-ItemProperty -LiteralPath $serverKey -ErrorAction SilentlyContinue).fDenyTSConnections
    }
    $nlaValue = $null
    if (Test-Path -LiteralPath $tcpKey) {
        $nlaValue = (Get-ItemProperty -LiteralPath $tcpKey -ErrorAction SilentlyContinue).UserAuthentication
    }

    $enabled = ($denyValue -eq 0)
    $nla     = ($nlaValue -eq 1)

    if (-not $enabled) {
        $summary = 'RDP ist deaktiviert.'
    }
    elseif ($nla) {
        $summary = 'RDP ist aktiv — nur Verbindungen mit Netzwerkebenen-Authentifizierung (NLA).'
    }
    else {
        $summary = 'RDP ist aktiv — NLA ist nicht erzwungen.'
    }

    [PSCustomObject]@{
        Enabled     = $enabled
        NlaRequired = $nla
        Summary     = $summary
    }
}

function Get-AutologonStatus {
    <#
    .SYNOPSIS
        Liest die Autologon-Konfiguration aus Winlogon.
    .DESCRIPTION
        Das gespeicherte Klartextpasswort (DefaultPassword) wird bewusst NICHT
        gelesen und NICHT angezeigt. Fuer die Frage "ist Autologon aktiv und fuer
        wen" reichen die beiden anderen Werte; das Passwort auszulesen erzeugt nur
        Risiko ohne Nutzen.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Assert-WindowsPlatform -Feature 'Die Autologon-Pruefung'

    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    if (-not (Test-Path -LiteralPath $key)) {
        return [PSCustomObject]@{ Enabled = $false; UserName = ''; Domain = ''; Summary = 'Winlogon-Schluessel nicht gefunden.' }
    }

    $props    = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    $enabled  = ($props.AutoAdminLogon -eq '1')
    $userName = [string]$props.DefaultUserName
    $domain   = [string]$props.DefaultDomainName

    if ($enabled) {
        $who = if ([string]::IsNullOrWhiteSpace($domain)) { $userName } else { "$domain\$userName" }
        $summary = "Autologon ist aktiv fuer: $who"
    }
    else {
        $summary = 'Autologon ist nicht aktiv.'
    }

    [PSCustomObject]@{
        Enabled  = $enabled
        UserName = $userName
        Domain   = $domain
        Summary  = $summary
    }
}

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Sammelt Systeminformationen ueber CIM.
    .DESCRIPTION
        Rueckgabe ist ein geordnetes Dictionary aus Abschnitten. Die Formatierung
        uebernimmt Format-SystemReport im Core-Modul — dadurch bleibt das Einsammeln
        frei von Darstellungslogik.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    Assert-WindowsPlatform -Feature 'Die Systemabfrage'

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue

    $system = [ordered]@{
        'Rechnername'    = if ($cs) { $cs.Name } else { 'unbekannt' }
        'Domaene'        = if ($cs) { $cs.Domain } else { 'unbekannt' }
        'Hersteller'     = if ($cs) { $cs.Manufacturer } else { 'unbekannt' }
        'Modell'         = if ($cs) { $cs.Model } else { 'unbekannt' }
        'Arbeitsspeicher' = if ($cs -and $cs.TotalPhysicalMemory) { '{0:N1} GB' -f ($cs.TotalPhysicalMemory / 1GB) } else { 'unbekannt' }
        'Betriebssystem' = if ($os) { $os.Caption } else { 'unbekannt' }
        'Version'        = if ($os) { $os.Version } else { 'unbekannt' }
        'Architektur'    = if ($os) { $os.OSArchitecture } else { 'unbekannt' }
        'Letzter Start'  = if ($os -and $os.LastBootUpTime) { $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm') } else { 'unbekannt' }
    }

    $network = [ordered]@{}
    $adapters = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction SilentlyContinue)
    if ($adapters.Count -eq 0) {
        $network['Adapter'] = 'keine aktiven Adapter gefunden'
    }
    else {
        foreach ($adapter in $adapters) {
            $ip = if ($adapter.IPAddress) { $adapter.IPAddress -join ', ' } else { 'keine' }
            $network[[string]$adapter.Description] = "$ip  (MAC $($adapter.MACAddress), DHCP $($adapter.DHCPEnabled))"
        }
    }

    $disk = [ordered]@{}
    foreach ($volume in @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction SilentlyContinue)) {
        $free  = '{0:N1} GB' -f ($volume.FreeSpace / 1GB)
        $total = '{0:N1} GB' -f ($volume.Size / 1GB)
        $disk[[string]$volume.DeviceID] = "$free frei von $total"
    }
    if ($disk.Count -eq 0) { $disk['Laufwerke'] = 'keine lokalen Laufwerke gefunden' }

    return [ordered]@{
        'System'    = $system
        'Netzwerk'  = $network
        'Datentraeger' = $disk
    }
}

function Connect-NetworkShare {
    <#
    .SYNOPSIS
        Bindet eine Netzwerkfreigabe als Laufwerk ein.
    .DESCRIPTION
        Nimmt ein PSCredential entgegen, kein Klartextpasswort. Die frueher genutzte
        Aufrufform "net use ... /user:name passwort" schrieb das Passwort in die
        Prozess-Kommandozeile, wo jeder lokale Prozessmonitor es mitliest.
        New-PSDrive uebergibt die Anmeldedaten stattdessen im Prozessspeicher.
    .PARAMETER UncPath
        UNC-Pfad der Freigabe.
    .PARAMETER DriveLetter
        Laufwerksbuchstabe ohne Doppelpunkt.
    .PARAMETER Credential
        Anmeldedaten.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidatePattern('^\\\\')][string]$UncPath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]$')][string]$DriveLetter,
        [Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential
    )

    Assert-WindowsPlatform -Feature 'Das Einbinden von Netzlaufwerken'

    if (-not $PSCmdlet.ShouldProcess("${DriveLetter}: -> $UncPath", 'Netzlaufwerk verbinden')) {
        return [PSCustomObject]@{ Success = $false; Summary = 'Abgebrochen.' }
    }

    if (Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue) {
        Remove-PSDrive -Name $DriveLetter -Force -ErrorAction SilentlyContinue
    }

    try {
        New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $UncPath `
                    -Credential $Credential -Persist -Scope Global -ErrorAction Stop | Out-Null
        return [PSCustomObject]@{ Success = $true; Summary = "${DriveLetter}: ist mit $UncPath verbunden." }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Summary = "Verbinden fehlgeschlagen: $($_.Exception.Message)" }
    }
}

function Start-ConfiguredProcess {
    <#
    .SYNOPSIS
        Startet ein konfiguriertes Programm.
    .DESCRIPTION
        Prueft die Existenz vor dem Start und liefert eine Meldung zurueck, statt
        eine unbehandelte Ausnahme in die Oberflaeche durchschlagen zu lassen.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$ArgumentList
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [PSCustomObject]@{ Success = $false; Summary = 'Kein Pfad konfiguriert.' }
    }
    $isUri = $Path -match '^https?://'
    if (-not $isUri -and -not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{ Success = $false; Summary = "Nicht gefunden: $Path" }
    }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Starten')) {
        return [PSCustomObject]@{ Success = $false; Summary = 'Abgebrochen.' }
    }

    try {
        if ($ArgumentList) { Start-Process -FilePath $Path -ArgumentList $ArgumentList -ErrorAction Stop }
        else               { Start-Process -FilePath $Path -ErrorAction Stop }
        return [PSCustomObject]@{ Success = $true; Summary = "Gestartet: $Path" }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Summary = "Start fehlgeschlagen: $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function Test-WindowsPlatform, Assert-WindowsPlatform, Get-RdpStatus,
                              Get-AutologonStatus, Get-SystemInfo, Connect-NetworkShare,
                              Start-ConfiguredProcess
