#Requires -Version 5.1
<#
    Tests fuer die plattformneutrale Logik.

    Diese Datei laeuft bewusst auf jeder Plattform — sie fasst weder Registry
    noch CIM noch WinForms an. Genau dafuer wurde die Logik aus der Oberflaeche
    herausgeloest.
#>

BeforeAll {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) (Join-Path 'src' 'AllInOne.Core.psm1')
    Import-Module $modulePath -Force

    function Get-TestTool {
        param([string]$Group, [string]$Label, [string]$RequiresPath)
        $tool = [PSCustomObject]@{ Group = $Group; Label = $Label }
        if ($PSBoundParameters.ContainsKey('RequiresPath')) {
            $tool | Add-Member -NotePropertyName RequiresPath -NotePropertyValue $RequiresPath
        }
        return $tool
    }

    function Test-RectOverlap {
        param($A, $B)
        $xOverlap = ($A.X -lt ($B.X + $B.Width))  -and ($B.X -lt ($A.X + $A.Width))
        $yOverlap = ($A.Y -lt ($B.Y + $B.Height)) -and ($B.Y -lt ($A.Y + $A.Height))
        return ($xOverlap -and $yOverlap)
    }
}

Describe 'Get-ToolLayout' {

    Context 'Grundlegende Anordnung' {
        BeforeAll {
            $script:tools = @(
                Get-TestTool -Group 'Diagnose'  -Label 'A'
                Get-TestTool -Group 'Diagnose'  -Label 'B'
                Get-TestTool -Group 'Werkzeuge' -Label 'C'
            )
            $script:layout = Get-ToolLayout -Tool $script:tools
        }

        It 'erzeugt je Werkzeug eine Schaltflaeche' {
            @($script:layout.Items | Where-Object Kind -EQ 'Button').Count | Should -Be 3
        }

        It 'erzeugt je Gruppe genau eine Ueberschrift' {
            @($script:layout.Items | Where-Object Kind -EQ 'Header').Count | Should -Be 2
        }

        It 'behaelt die Reihenfolge der Gruppen nach erstem Auftreten bei' {
            $headers = @($script:layout.Items | Where-Object Kind -EQ 'Header' | ForEach-Object Label)
            $headers[0] | Should -Be 'Diagnose'
            $headers[1] | Should -Be 'Werkzeuge'
        }

        It 'behaelt die Reihenfolge der Werkzeuge innerhalb einer Gruppe bei' {
            $labels = @($script:layout.Items | Where-Object { $_.Kind -eq 'Button' -and $_.Group -eq 'Diagnose' } | ForEach-Object Label)
            $labels -join ',' | Should -Be 'A,B'
        }
    }

    Context 'Ueberschneidungsfreiheit' {
        It 'platziert keine zwei Elemente uebereinander' {
            $tools = 1..12 | ForEach-Object { Get-TestTool -Group "G$([math]::Floor($_ / 4))" -Label "T$_" }
            $items = @((Get-ToolLayout -Tool $tools).Items)

            for ($i = 0; $i -lt $items.Count; $i++) {
                for ($j = $i + 1; $j -lt $items.Count; $j++) {
                    Test-RectOverlap $items[$i] $items[$j] |
                        Should -BeFalse -Because "'$($items[$i].Label)' und '$($items[$j].Label)' duerfen sich nicht ueberlappen"
                }
            }
        }

        It 'haelt alle Elemente innerhalb der gemeldeten Flaeche' {
            $tools  = 1..9 | ForEach-Object { Get-TestTool -Group "G$([math]::Floor($_ / 3))" -Label "T$_" }
            $layout = Get-ToolLayout -Tool $tools
            foreach ($item in $layout.Items) {
                ($item.X + $item.Width)  | Should -BeLessOrEqual $layout.Width
                ($item.Y + $item.Height) | Should -BeLessOrEqual $layout.Height
            }
        }
    }

    Context 'Spaltenumbruch' {
        It 'beginnt eine neue Spalte, wenn die Hoehenschranke ueberschritten wird' {
            $tools  = 1..6 | ForEach-Object { Get-TestTool -Group "G$_" -Label "T$_" }
            $layout = Get-ToolLayout -Tool $tools -MaxColumn 150
            $spalten = @($layout.Items | ForEach-Object X | Sort-Object -Unique)
            $spalten.Count | Should -BeGreaterThan 1
        }

        It 'bleibt einspaltig, wenn alles hineinpasst' {
            $tools  = 1..3 | ForEach-Object { Get-TestTool -Group 'G' -Label "T$_" }
            $layout = Get-ToolLayout -Tool $tools -MaxColumn 4000
            @($layout.Items | ForEach-Object X | Sort-Object -Unique).Count | Should -Be 1
        }

        It 'erzeugt keine leeren Spalten, wenn eine Gruppe allein zu hoch ist' {
            # Regressionsschutz: ohne die "Spalte ist ohnehin leer"-Bedingung
            # wuerde eine ueberlange Gruppe endlos umbrechen.
            $tools  = 1..20 | ForEach-Object { Get-TestTool -Group 'Riesig' -Label "T$_" }
            $layout = Get-ToolLayout -Tool $tools -MaxColumn 100
            @($layout.Items | ForEach-Object X | Sort-Object -Unique).Count | Should -Be 1
        }
    }

    Context 'Randfaelle' {
        It 'kommt mit einer leeren Werkzeugliste zurecht' {
            $layout = Get-ToolLayout -Tool @()
            @($layout.Items).Count | Should -Be 0
            $layout.Width  | Should -BeGreaterThan 0
            $layout.Height | Should -BeGreaterThan 0
        }

        It 'weist unsinnige Masse ab' {
            { Get-ToolLayout -Tool @() -ButtonWidth 5 } | Should -Throw
        }
    }
}

Describe 'Import-ToolConfig' {

    BeforeAll {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("aio_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:tempDir) { Remove-Item -LiteralPath $script:tempDir -Recurse -Force }
    }

    It 'liefert Standardwerte, wenn keine Datei existiert' {
        $config = Import-ToolConfig -Path (Join-Path $script:tempDir 'gibtsnicht.json')
        $config.Window.ButtonWidth | Should -Be 170
        $config.Paths.CCleaner     | Should -BeNullOrEmpty
    }

    It 'liefert Standardwerte bei leerer Datei' {
        $path = Join-Path $script:tempDir 'leer.json'
        Set-Content -LiteralPath $path -Value '' -Encoding UTF8
        (Import-ToolConfig -Path $path).Window.ButtonWidth | Should -Be 170
    }

    It 'ueberschreibt nur die angegebenen Werte' {
        $path = Join-Path $script:tempDir 'teil.json'
        '{ "Window": { "ButtonWidth": 240 } }' | Set-Content -LiteralPath $path -Encoding UTF8
        $config = Import-ToolConfig -Path $path
        $config.Window.ButtonWidth  | Should -Be 240   # ueberschrieben
        $config.Window.ButtonHeight | Should -Be 26    # Standard bleibt
        $config.Network.DriveLetter | Should -Be 'Y'   # anderer Zweig bleibt
    }

    It 'wirft bei kaputtem JSON statt still Standardwerte zu nehmen' {
        $path = Join-Path $script:tempDir 'kaputt.json'
        '{ "Window": { ' | Set-Content -LiteralPath $path -Encoding UTF8
        { Import-ToolConfig -Path $path } | Should -Throw '*kein gueltiges JSON*'
    }

    It 'ignoriert unbekannte Schluessel und warnt' {
        $path = Join-Path $script:tempDir 'tippfehler.json'
        '{ "Windwo": { "ButtonWidth": 999 } }' | Set-Content -LiteralPath $path -Encoding UTF8
        $config = Import-ToolConfig -Path $path -WarningAction SilentlyContinue
        $config.Window.ButtonWidth | Should -Be 170
        $config.PSObject.Properties.Name | Should -Not -Contain 'Windwo'
    }
}

Describe 'Test-ToolEnabled' {

    BeforeAll {
        $script:config = Get-DefaultConfig
        $script:config.Paths.CCleaner = 'X:\vorhanden\ccleaner.exe'
    }

    It 'aktiviert Werkzeuge ohne Pfadbedarf' {
        Test-ToolEnabled -Tool (Get-TestTool -Group 'G' -Label 'Editor') -Config $script:config | Should -BeTrue
    }

    It 'reicht genau den konfigurierten Pfad an die Pruefung durch' {
        $tool = Get-TestTool -Group 'G' -Label 'CCleaner' -RequiresPath 'CCleaner'
        Test-ToolEnabled -Tool $tool -Config $script:config -TestPath {
            param($p) $p -eq 'X:\vorhanden\ccleaner.exe'
        } | Should -BeTrue
    }

    It 'deaktiviert Werkzeuge mit fehlendem Pfad' {
        $tool = Get-TestTool -Group 'G' -Label 'CCleaner' -RequiresPath 'CCleaner'
        Test-ToolEnabled -Tool $tool -Config $script:config -TestPath {
            param($p) $p -eq 'ein anderer Pfad'
        } | Should -BeFalse
    }

    It 'deaktiviert Werkzeuge mit leerem Pfad, ohne das Dateisystem zu fragen' {
        $tool = Get-TestTool -Group 'G' -Label 'SnapShot' -RequiresPath 'SnapShot'
        Test-ToolEnabled -Tool $tool -Config $script:config -TestPath {
            param($p) throw "Dateisystem darf nicht gefragt werden, wurde aber mit '$p' aufgerufen"
        } | Should -BeFalse
    }

    It 'deaktiviert Werkzeuge mit unbekanntem Pfadschluessel' {
        $tool = Get-TestTool -Group 'G' -Label 'Phantom' -RequiresPath 'GibtEsNicht'
        Test-ToolEnabled -Tool $tool -Config $script:config -WarningAction SilentlyContinue | Should -BeFalse
    }
}

Describe 'Format-SystemReport' {

    BeforeAll {
        $script:facts = [ordered]@{
            'System'   = [ordered]@{ 'Rechnername' = 'PC-01'; 'Betriebssystem' = 'Windows 10 Pro' }
            'Netzwerk' = [ordered]@{ 'Ethernet' = '10.0.0.5' }
            'Leer'     = [ordered]@{}
        }
        $script:report = Format-SystemReport -Fact $script:facts -Title 'Bericht'
    }

    It 'setzt Titel und Unterstreichung an den Anfang' {
        $script:report[0] | Should -Be 'Bericht'
        $script:report[1] | Should -Be '======='
    }

    It 'enthaelt jeden Abschnitt' {
        $script:report | Should -Contain 'System'
        $script:report | Should -Contain 'Netzwerk'
    }

    It 'gibt Werte mit ihren Schluesseln aus' {
        ($script:report -join "`n") | Should -Match 'Rechnername\s+: PC-01'
    }

    It 'richtet Schluessel innerhalb eines Abschnitts buendig aus' {
        $zeilen = @($script:report | Where-Object { $_ -match '^\s+\S.*: ' })
        $positionen = @($zeilen | Where-Object { $_ -match 'PC-01|Windows 10' } | ForEach-Object { $_.IndexOf(':') })
        ($positionen | Sort-Object -Unique).Count | Should -Be 1
    }

    It 'markiert leere Abschnitte statt sie wegzulassen' {
        $script:report | Should -Contain '  (keine Daten)'
    }
}
