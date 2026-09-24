# =====================================================================
#  EmiProcess.psm1 - Procesos: consumo de RAM, telemetria y bloqueo
# =====================================================================

# Procesos que jamas se tocan (sistema, seguridad, sesion, ESET).
$script:CriticalProcs = @(
    'system','idle','registry','memory compression','smss','csrss','wininit','winlogon','services',
    'lsass','lsaiso','fontdrvhost','dwm','sihost','shellexperiencehost','explorer','ctfmon',
    'runtimebroker','taskhostw','searchhost','startmenuexperiencehost','audiodg','conhost',
    'ekrn','egui','eset','esets','msmpeng','mssense','securityhealthservice','securityhealthsystray',
    'nissrv','wscsvc','svchost','powershell','pwsh','wudfhost','spoolsv','dllhost','sppsvc'
)

# Procesos de telemetria o recoleccion de datos.
$script:TelemetryProcs = @(
    @{ N='compattelrunner'; W='Telemetria de compatibilidad de Microsoft' }
    @{ N='devicecensus';    W='Inventario del equipo enviado a Microsoft' }
    @{ N='dmclient';        W='Cliente de comentarios y diagnostico' }
    @{ N='wsqmcons';        W='Programa de mejora de la experiencia (CEIP)' }
    @{ N='diagtrack';       W='Servicio de telemetria DiagTrack' }
    @{ N='inventory';       W='Recoleccion de inventario' }
    @{ N='sihclient';       W='Cliente de mantenimiento remoto' }
    @{ N='wermgr';          W='Envio de informes de errores' }
    @{ N='werfault';        W='Envio de informes de errores' }
    @{ N='officeclicktorun';W='Telemetria y actualizador de Office' }
    @{ N='msoia';           W='Telemetria de Office' }
    @{ N='onedrivestandaloneupdater'; W='Actualizador de OneDrive' }
    @{ N='gamebarpresencewriter';     W='Presencia de Xbox Game Bar' }
    @{ N='yourphone';       W='Vinculo con el telefono' }
    @{ N='phoneexperiencehost'; W='Vinculo con el telefono' }
    # --- Procesos modernos (AI, Edge, Update) ---
    @{ N='msedge';          W='Edge: telemetria y recoleccion de datos' }
    @{ N='mousocoreworker'; W='Windows Update telemetry worker' }
    @{ N='aiappcam';        W='Windows AI camera processing' }
    @{ N='recall';          W='Recall snapshot capture' }
)

# Procesos pesados que casi nunca hacen falta en segundo plano.
$script:HeavyOptional = @(
    @{ N='spotify';        W='Spotify' }
    @{ N='discord';        W='Discord' }
    @{ N='steam';          W='Steam' }
    @{ N='epicgameslauncher'; W='Epic Games Launcher' }
    @{ N='eadesktop';      W='EA Desktop' }
    @{ N='teams';          W='Microsoft Teams' }
    @{ N='ms-teams';       W='Microsoft Teams' }
    @{ N='slack';          W='Slack' }
    @{ N='skype';          W='Skype' }
    @{ N='zoom';           W='Zoom' }
    @{ N='dropbox';        W='Dropbox' }
    @{ N='googledrivefs';  W='Google Drive' }
    @{ N='onedrive';       W='OneDrive' }
    @{ N='ccxprocess';     W='Adobe Creative Cloud' }
    @{ N='adobeipcbroker'; W='Adobe IPC' }
    @{ N='acrotray';       W='Adobe Acrobat' }
    @{ N='nvcontainer';    W='NVIDIA Container' }
    @{ N='razer';          W='Razer Synapse' }
    @{ N='icue';           W='Corsair iCUE' }
    @{ N='lghub';          W='Logitech G HUB' }
    @{ N='widgets';        W='Widgets de Windows' }
    @{ N='widgetservice';  W='Servicio de Widgets' }
    @{ N='msedgewebview2'; W='WebView2 (widgets y apps embebidas)' }
    @{ N='searchapp';      W='Busqueda de Windows (interfaz)' }
    @{ N='wpscloudsvr';    W='WPS Office nube' }
    @{ N='utorrent';       W='uTorrent' }
    @{ N='qbittorrent';    W='qBittorrent' }
    # --- Procesos modernos (Win11Debloat) ---
    @{ N='clipchamp';      W='Clipchamp video editor' }
    @{ N='mspaint';        W='Paint 3D' }
    @{ N='yourphone';      W='Phone Link sync' }
)

function Test-EmiCriticalProc {
    param([string] $Name)
    $n = "$Name".ToLower()
    foreach ($c in $script:CriticalProcs) { if ($n -eq $c) { return $true } }
    return $false
}

function Get-EmiProcessItems {
    <#  Procesos agrupados por nombre con RAM total y clasificacion. #>
    param([int] $MinMB = 5)

    $groups = Get-Process -ErrorAction SilentlyContinue |
              Group-Object -Property ProcessName |
              ForEach-Object {
                  $ram = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum
                  [pscustomobject]@{
                      Name  = $_.Name
                      Count = $_.Count
                      Ram   = [long]$ram
                      Path  = ($_.Group | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path)
                  }
              } | Where-Object { $_.Ram -ge ($MinMB * 1MB) } | Sort-Object Ram -Descending

    $items = New-Object System.Collections.ArrayList
    foreach ($g in $groups) {
        $low  = $g.Name.ToLower()
        $crit = Test-EmiCriticalProc $g.Name

        $cat = 'Normal'; $why = ''; $rec = $false
        $tel = $script:TelemetryProcs | Where-Object { $low -like "*$($_.N)*" } | Select-Object -First 1
        if ($tel) { $cat = 'Telemetria'; $why = $tel.W; $rec = $true }
        else {
            $hv = $script:HeavyOptional | Where-Object { $low -like "*$($_.N)*" } | Select-Object -First 1
            if ($hv) { $cat = 'Prescindible'; $why = $hv.W; $rec = ($g.Ram -ge 150MB) }
        }
        if ($crit) { $cat = 'Sistema'; $why = 'Necesario para Windows o el antivirus'; $rec = $false }

        $it = New-Object EmiItem
        $it.Name        = $g.Name
        $it.Detail      = if ($why) { $why } else { $g.Path }
        $it.Path        = $g.Path
        $it.Tag         = $g.Name
        $it.Size        = $g.Ram
        $it.SizeText    = Format-EmiSize $g.Ram
        $it.Category    = $cat
        $it.Status      = "$($g.Count) proc."
        $it.Locked      = $crit
        $it.Recommended = $rec
        $it.Selected    = $rec
        [void]$items.Add($it)
    }

    $total = ($groups | Measure-Object Ram -Sum).Sum
    Write-EmiLog "$($items.Count) procesos analizados, $(Format-EmiSize $total) de RAM en uso." Ok
    return $items
}

function Get-EmiMemoryStatus {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalKb = $os.TotalVisibleMemorySize
    $freeKb  = $os.FreePhysicalMemory
    $usedKb  = $totalKb - $freeKb
    [pscustomobject]@{
        TotalText = Format-EmiSize ($totalKb * 1KB)
        UsedText  = Format-EmiSize ($usedKb  * 1KB)
        FreeText  = Format-EmiSize ($freeKb  * 1KB)
        Percent   = [math]::Round(($usedKb / $totalKb) * 100, 1)
    }
}

function Stop-EmiProcessByName {
    param([Parameter(Mandatory)][string] $Name)

    if (Test-EmiCriticalProc $Name) { Write-EmiLog "'$Name' es critico: no se toca." Warn; return $false }
    try {
        $procs = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
        if ($procs.Count -eq 0) { return $false }
        $ram = ($procs | Measure-Object WorkingSet64 -Sum).Sum
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-EmiLog "Cerrado '$Name' ($(Format-EmiSize $ram) liberados)." Ok
        return $true
    }
    catch { Write-EmiLog "No se pudo cerrar '$Name': $($_.Exception.Message)" Warn; return $false }
}

function Block-EmiProcessNetwork {
    <#  Crea una regla de firewall de salida que bloquea el ejecutable. #>
    param([Parameter(Mandatory)][string] $ExePath, [string] $Label)

    if (-not (Test-Path -LiteralPath $ExePath)) { return $false }
    if (Test-EmiCriticalProc ([IO.Path]::GetFileNameWithoutExtension($ExePath))) {
        Write-EmiLog 'Proceso critico: no se bloquea.' Warn; return $false
    }

    $name = "EmiToolkit - Bloquear $(if ($Label) { $Label } else { Split-Path $ExePath -Leaf })"
    if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) {
        Write-EmiLog "Ya existe una regla para '$name'." Warn; return $false
    }
    try {
        New-NetFirewallRule -DisplayName $name -Direction Outbound -Action Block -Program $ExePath `
                            -Profile Any -Group 'EmiToolkit' -ErrorAction Stop | Out-Null
        Add-EmiJournalEntry @{ Kind='Firewall'; RuleName=$name; Module='Procesos' }
        Write-EmiLog "Sin acceso a Internet: $(Split-Path $ExePath -Leaf)" Ok
        return $true
    }
    catch { Write-EmiLog "Firewall: $($_.Exception.Message)" Warn; return $false }
}

function Invoke-EmiProcessCleanup {
    <#  Cierra (y opcionalmente bloquea) los procesos indicados. #>
    param([EmiItem[]] $Items, [switch] $BlockNetwork)

    $n = 0; $freed = 0; $i = 0
    foreach ($it in $Items) {
        $i++
        if ($it.Locked) { continue }
        Set-EmiStatus "Cerrando $($it.Name)" ([int](($i / [math]::Max(1, $Items.Count)) * 100))

        $freed += $it.Size
        if (Stop-EmiProcessByName -Name $it.Name) {
            $n++
            $it.Status = 'Cerrado'
            $it.Selected = $false
        }
        if ($BlockNetwork -and $it.Path -and $it.Category -eq 'Telemetria') {
            [void](Block-EmiProcessNetwork -ExePath $it.Path -Label $it.Name)
        }
    }

    Write-EmiLog "$n procesos cerrados, hasta $(Format-EmiSize $freed) de RAM recuperados." Ok
    Set-EmiStatus 'Procesos optimizados' 100
    return $n
}

Export-ModuleMember -Function *-Emi*
