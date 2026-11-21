# =====================================================================
#  EmiProcess.psm1 - Procesos: consumo de RAM, telemetria y bloqueo
# =====================================================================

# Procesos que jamas se tocan (sistema, seguridad, sesion, instaladores,
# audio, touchpad, ESET). Se comparan por nombre exacto, sin '.exe'.
$script:CriticalProcs = @(
    'system','idle','registry','memory compression','secure system','smss','csrss','wininit','winlogon',
    'services','lsass','lsaiso','lsm','fontdrvhost','dwm','sihost','shellexperiencehost','explorer','ctfmon',
    'runtimebroker','taskhostw','searchhost','searchindexer','startmenuexperiencehost','audiodg','conhost',
    'textinputhost','lockapp','logonui','userinit','consent','credentialuibroker','useroobebroker',
    'applicationframehost','dashost','wmiprvse','aggregatorhost','sgrmbroker',
    'msiexec','tiworker','trustedinstaller','wuauclt','mousocoreworker','usocoreworker',
    'ekrn','egui','eset','esets','msmpeng','mssense','mpdefendercoreservice','mpcopyaccelerator',
    'nissrv','securityhealthservice','securityhealthsystray','securityhealthhost','smartscreen','wscsvc',
    'svchost','powershell','pwsh','wudfhost','spoolsv','dllhost','sppsvc',
    'nvdisplay.container','rtkaudusvc64','rtkauduservice64','rtkaudioservice64','rthdvcpl',
    'syntpenh','syntphelper','etdctrl','etdctrlhelper','etdservice'
)

# Procesos de telemetria o recoleccion de datos. Solo procesos cuyo unico
# trabajo es recoger o enviar datos: nada de navegadores, Windows Update,
# Office ni actualizadores, porque esta categoria es la unica a la que se
# le puede cortar Internet. (msedge, mousocoreworker, officeclicktorun,
# sihclient, yourphone y phoneexperiencehost estaban aqui: ver la
# auditoria de sistema, EmiProcess.psm1:22-33.)
$script:TelemetryProcs = @(
    @{ N='compattelrunner'; W='Telemetria de compatibilidad de Microsoft' }
    @{ N='devicecensus';    W='Inventario del equipo enviado a Microsoft' }
    @{ N='dmclient';        W='Cliente de comentarios y diagnostico' }
    @{ N='wsqmcons';        W='Programa de mejora de la experiencia (CEIP)' }
    @{ N='diagtrack';       W='Servicio de telemetria DiagTrack' }
    @{ N='wermgr';          W='Envio de informes de errores' }
    @{ N='werfault';        W='Envio de informes de errores' }
    @{ N='msoia';           W='Telemetria de Office' }
    @{ N='gamebarpresencewriter';     W='Presencia de Xbox Game Bar' }
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
    @{ N='teams';          W='Microsoft Teams (clasico)' }
    @{ N='ms-teams';       W='Microsoft Teams' }
    @{ N='slack';          W='Slack' }
    @{ N='skype';          W='Skype' }
    @{ N='zoom';           W='Zoom' }
    @{ N='dropbox';        W='Dropbox (deja de sincronizar hasta reabrirlo)' }
    @{ N='googledrivefs';  W='Google Drive (deja de sincronizar hasta reabrirlo)' }
    @{ N='onedrive';       W='OneDrive (deja de sincronizar hasta reabrirlo)' }
    @{ N='ccxprocess';     W='Adobe Creative Cloud' }
    @{ N='adobeipcbroker'; W='Adobe IPC' }
    @{ N='acrotray';       W='Adobe Acrobat' }
    @{ N='nvcontainer';    W='NVIDIA Container' }
    @{ N='razer synapse 3'; W='Razer Synapse' }
    @{ N='razerappengine'; W='Razer Synapse' }
    @{ N='icue';           W='Corsair iCUE' }
    @{ N='lghub';          W='Logitech G HUB' }
    @{ N='widgets';        W='Widgets de Windows' }
    @{ N='widgetservice';  W='Servicio de Widgets' }
    @{ N='searchapp';      W='Busqueda de Windows (interfaz)' }
    @{ N='wpscloudsvr';    W='WPS Office nube' }
    @{ N='utorrent';       W='uTorrent' }
    @{ N='qbittorrent';    W='qBittorrent' }
    @{ N='clipchamp';      W='Clipchamp video editor' }
    @{ N='phoneexperiencehost'; W='Enlace Movil (deja de avisar del telefono)' }
    @{ N='yourphone';      W='Enlace Movil (deja de avisar del telefono)' }
)

function Test-EmiCriticalProc {
    param([string] $Name)
    $n = "$Name".ToLower()
    if ($n.EndsWith('.exe')) { $n = $n.Substring(0, $n.Length - 4) }
    foreach ($c in $script:CriticalProcs) { if ($n -eq $c) { return $true } }
    return $false
}

function Find-EmiProcEntry {
    <#  Busca un nombre de proceso en una lista por nombre EXACTO (sin
        distinguir mayusculas). Antes se usaba -like "*nombre*", con lo que
        'msedge' tambien atrapaba 'msedgewebview2'.  #>
    param([string] $Name, [object[]] $List)
    $n = "$Name".ToLower()
    if ($n.EndsWith('.exe')) { $n = $n.Substring(0, $n.Length - 4) }
    foreach ($e in $List) { if ($n -eq $e.N) { return $e } }
    return $null
}

function Test-EmiTelemetryProc {
    param([string] $Name)
    return [bool](Find-EmiProcEntry -Name $Name -List $script:TelemetryProcs)
}

function Get-EmiProcClass {
    <#  Clasifica un proceso: Sistema, Telemetria, Prescindible o Normal.
        Recommended es solo una pista en la lista: nada sale marcado.  #>
    param([string] $Name, [long] $Ram = 0)
    if (Test-EmiCriticalProc $Name) {
        return [pscustomobject]@{ Category='Sistema'; Why='Necesario para Windows o el antivirus'; Recommended=$false; Locked=$true }
    }
    $tel = Find-EmiProcEntry -Name $Name -List $script:TelemetryProcs
    if ($tel) { return [pscustomobject]@{ Category='Telemetria'; Why=$tel.W; Recommended=$true; Locked=$false } }
    $hv = Find-EmiProcEntry -Name $Name -List $script:HeavyOptional
    if ($hv) { return [pscustomobject]@{ Category='Prescindible'; Why=$hv.W; Recommended=($Ram -ge 150MB); Locked=$false } }
    return [pscustomobject]@{ Category='Normal'; Why=''; Recommended=$false; Locked=$false }
}

function Test-EmiProcSessionAllowed {
    <#  Solo se tocan procesos de la sesion actual o de la sesion 0
        (servicios y tareas del sistema). Nunca los de otro usuario con
        sesion abierta (cambio rapido de usuario, escritorio remoto).  #>
    param([int] $SessionId, [int] $Current = ([Diagnostics.Process]::GetCurrentProcess().SessionId))
    return ($SessionId -eq 0 -or $SessionId -eq $Current)
}

function Get-EmiProcessItems {
    <#  Procesos agrupados por nombre con RAM total y clasificacion. #>
    param([int] $MinMB = 5)

    $mySession = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $groups = Get-Process -ErrorAction SilentlyContinue |
              Where-Object { Test-EmiProcSessionAllowed -SessionId $_.SessionId -Current $mySession } |
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
        $cls = Get-EmiProcClass -Name $g.Name -Ram $g.Ram
        $why = $cls.Why

        $it = New-Object EmiItem
        $it.Name        = $g.Name
        $it.Detail      = if ($why) { $why } else { $g.Path }
        $it.Path        = $g.Path
        $it.Tag         = $g.Name
        $it.Size        = $g.Ram
        $it.SizeText    = Format-EmiSize $g.Ram
        $it.Category    = $cls.Category
        $it.Status      = "$($g.Count) proc."
        $it.Locked      = $cls.Locked
        $it.Recommended = $cls.Recommended
        $it.Selected    = $false   # nada preseleccionado: lo elige el usuario
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
        $mySession = [Diagnostics.Process]::GetCurrentProcess().SessionId
        $all   = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
        $procs = @($all | Where-Object { Test-EmiProcSessionAllowed -SessionId $_.SessionId -Current $mySession })
        if ($all.Count -gt $procs.Count) {
            Write-EmiLog "'$Name': $($all.Count - $procs.Count) proceso(s) de otra sesion de usuario no se tocan." Warn
        }
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
    $exeName = [IO.Path]::GetFileNameWithoutExtension($ExePath)
    if (Test-EmiCriticalProc $exeName) {
        Write-EmiLog 'Proceso critico: no se bloquea.' Warn; return $false
    }
    # Solo se corta Internet a la categoria Telemetria. Bloquear un navegador,
    # Windows Update u Office por haberlo seleccionado para cerrarlo los
    # dejaba sin red (auditoria de sistema, EmiToolkit.ps1:1033-1038).
    if (-not (Test-EmiTelemetryProc $exeName)) {
        Write-EmiLog "'$exeName' no es telemetria: se cierra, pero no se le corta Internet." Warn; return $false
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
