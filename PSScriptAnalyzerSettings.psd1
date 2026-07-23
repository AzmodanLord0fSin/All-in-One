@{
    # Geprueft wird gegen Windows PowerShell 5.1 und PowerShell 7 — das Skript
    # soll auf beiden laufen. Die frueheren Get-WmiObject-Aufrufe taten das nicht.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Die Oberflaeche baut Steuerelemente in Schleifen; Variablen wie $header
        # oder $tip werden bewusst nur zugewiesen und dem Formular uebergeben.
        'PSUseDeclaredVarsMoreThanAssignments'
    )

    Rules = @{
        PSUseCompatibleCmdlets = @{
            Compatibility = @('desktop-5.1.14393.206-windows', 'core-6.1.0-windows')
        }
    }
}
