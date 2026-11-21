# =====================================================================
#  EmiTweaks.psm1 - Optimizacion de Windows 11
#  Transparencia y animaciones solo como opcionales: nunca en modo basico.
# =====================================================================

$HKCU_ADV     = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$HKCU_CDM     = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$HKCU_SEARCH  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'
$HKLM_POL_WS  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
$HKLM_POL_EXP = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'

function Get-EmiTweaks {
    <#  Catalogo de optimizaciones. Recommended = se aplica en modo basico. #>
    @(
        [pscustomobject]@{ Id='Widgets';    Name='Quitar Widgets de la barra de tareas';       Info='Libera RAM del proceso Widgets.exe';                 Recommended=$true }
        [pscustomobject]@{ Id='Copilot';    Name='Quitar el boton de Copilot';                 Info='Desactiva Copilot en la barra de tareas';            Recommended=$true }
        [pscustomobject]@{ Id='Chat';       Name='Quitar el icono de Chat / Teams';            Info='Quita el chat integrado de Windows';                 Recommended=$true }
        [pscustomobject]@{ Id='WebSearch';  Name='Quitar la busqueda web de Bing del Inicio';  Info='El menu Inicio pasa a buscar solo en el equipo';     Recommended=$true }
        [pscustomobject]@{ Id='Suggest';    Name='Quitar sugerencias, anuncios y consejos';    Info='Apps sugeridas, contenido destacado, tips';          Recommended=$true }
        [pscustomobject]@{ Id='StartRec';   Name='Vaciar la seccion Recomendado del Inicio';   Info='Sin archivos ni apps recientes en el menu Inicio';   Recommended=$true }
        [pscustomobject]@{ Id='GameDVR';    Name='Desactivar Xbox Game Bar y grabacion';       Info='Quita la captura en segundo plano (mucha RAM)';      Recommended=$true }
        [pscustomobject]@{ Id='BgApps';     Name='Desactivar apps en segundo plano';           Info='OJO: sin avisos de Enlace Movil, alarmas ni correo de la Store; Windows 11 no tiene interruptor, se revierte desde Revertir'; Recommended=$false }
        [pscustomobject]@{ Id='Context';    Name='Menu contextual clasico (Win10)';            Info='Sin el paso extra de "Mostrar mas opciones"';        Recommended=$true }
        [pscustomobject]@{ Id='Explorer';   Name='Explorador: abrir en Este equipo';           Info='Tambien muestra extensiones de archivo';             Recommended=$true }
        [pscustomobject]@{ Id='Services';   Name='Desactivar servicios innecesarios';          Info='Fax, RetailDemo, registro remoto; Mapas y Cartera pasan a manual'; Recommended=$true }
        [pscustomobject]@{ Id='SvcXbox';    Name='Desactivar servicios de Xbox';               Info='OJO: rompe el inicio de sesion de Xbox, Game Pass, partidas en la nube y guardado en la nube'; Recommended=$false }
        [pscustomobject]@{ Id='SvcHotspot'; Name='Desactivar Conexion compartida (ICS)';       Info='OJO: deja de funcionar la zona con cobertura movil (compartir Internet)'; Recommended=$false }
        [pscustomobject]@{ Id='SvcParental';Name='Desactivar control parental (WpcMonSvc)';    Info='OJO: rompe Microsoft Family en cuentas infantiles';  Recommended=$false }
        [pscustomobject]@{ Id='SvcPca';     Name='Asistente de compatibilidad en manual';      Info='OJO: deja de avisar y corregir programas antiguos que fallan'; Recommended=$false }
        [pscustomobject]@{ Id='SvcDoSvc';   Name='Delivery Optimization en manual';            Info='OJO: Store y Windows Update pueden descargar peor; para cortar el P2P basta "Delivery Optimization solo en LAN" de Privacidad'; Recommended=$false }
        [pscustomobject]@{ Id='Tasks';      Name='Desactivar tareas programadas de rastreo';   Info='CEIP, Compatibility Appraiser, DiskDiagnostic';      Recommended=$true }
        [pscustomobject]@{ Id='NetworkOpt'; Name='Optimizar la pila de red';                   Info='Autotuning normal y sin limitacion de ancho de banda'; Recommended=$true }
        [pscustomobject]@{ Id='PowerPlan';  Name='Plan de energia Alto rendimiento';           Info='Recomendado en equipos de escritorio';               Recommended=$false }
        [pscustomobject]@{ Id='SysMain';    Name='Desactivar SysMain (Superfetch)';            Info='Solo en equipos con SSD; en HDD no conviene';        Recommended=$false }
        [pscustomobject]@{ Id='WSearch';    Name='Desactivar la indexacion de Windows Search'; Info='Menos disco, pero las busquedas van mas lentas';     Recommended=$false }
        [pscustomobject]@{ Id='OneDrive';   Name='Quitar OneDrive del arranque';               Info='No lo desinstala, solo deja de iniciarse solo';      Recommended=$false }
        [pscustomobject]@{ Id='Hibernate';  Name='Desactivar hibernacion';                     Info='Libera hiberfil.sys (varios GB) del disco C:';       Recommended=$false }
        [pscustomobject]@{ Id='Reserved';   Name='Quitar el almacenamiento reservado';         Info='Recupera ~7 GB que Windows aparta para updates';     Recommended=$false }
        # --- Win11Debloat: UI/UX, Update, Dev CLI, AI services ---
        [pscustomobject]@{ Id='TaskbarAlignLeft';   Name='Alinear barra de tareas a la izquierda'; Info='Estilo clasico de Windows 10';                          Recommended=$false }
        [pscustomobject]@{ Id='HideTaskView';       Name='Ocultar boton Task View';                Info='Quita el icono de escritorios virtuales';                 Recommended=$true }
        [pscustomobject]@{ Id='ShowEndTask';        Name='Mostrar Finalizar tarea en barra';       Info='Agrega End Task al menu contextual de la barra';          Recommended=$true }
        [pscustomobject]@{ Id='DisableSnapAssist';  Name='Desactivar Snap Assist flyout';          Info='Quita el panel de zonas al pasar sobre maximizar';        Recommended=$false }
        [pscustomobject]@{ Id='DisableTransparency';Name='Desactivar efectos de transparencia';    Info='Mejora rendimiento en equipos modestos';                  Recommended=$false }
        [pscustomobject]@{ Id='DisableAnimations';  Name='Desactivar animaciones de Windows';      Info='AVISO: afecta accesibilidad; mejora respuesta visual';    Recommended=$false }
        [pscustomobject]@{ Id='ForceDarkMode';      Name='Forzar modo oscuro en apps y sistema';   Info='Sobrescribe preferencia de tema claro del usuario';       Recommended=$false }
        [pscustomobject]@{ Id='HideGalleryNav';     Name='Ocultar Galeria en panel de navegacion'; Info='Limpia el panel izquierdo del Explorador (Windows 11 23H2+)'; Recommended=$true }
        [pscustomobject]@{ Id='HideHomeFolder';     Name='Ocultar carpeta Inicio en panel nav';    Info='Quita acceso directo a Inicio en Explorador';             Recommended=$true }
        [pscustomobject]@{ Id='HideOneDriveNav';    Name='Ocultar OneDrive en panel de navegacion';Info='Solo oculta el acceso directo; no desinstala OneDrive';   Recommended=$true }
        [pscustomobject]@{ Id='DisableMouseAccel';  Name='Desactivar aceleracion del mouse';       Info='Movimiento lineal 1:1; preferido por gamers';             Recommended=$false }
        [pscustomobject]@{ Id='DisableStickyKeys';  Name='Desactivar atajo de Sticky Keys';        Info='Evita activacion accidental con 5 pulsaciones de Shift';  Recommended=$true }
        [pscustomobject]@{ Id='DisableStorageSense';Name='Desactivar Storage Sense automatico';    Info='Impide limpieza automatica de archivos temporales';       Recommended=$false }
        [pscustomobject]@{ Id='DisableBitLockerAuto';Name='Desactivar cifrado automatico BitLocker';Info='Evita cifrado silencioso en dispositivos compatibles';   Recommended=$false }
        [pscustomobject]@{ Id='DisableDragTray';    Name='Desactivar bandeja de arrastre';         Info='Quita el area de compartir archivos al arrastrar';        Recommended=$true }
        [pscustomobject]@{ Id='DelayUpdates';       Name='Retrasar actualizaciones de calidad 7d'; Info='AVISO: las de calidad SON los parches de seguridad mensuales: llegan 7 dias tarde. Solo Pro, Enterprise y Education'; Recommended=$false }
        [pscustomobject]@{ Id='NoAutoRestart';      Name='No reiniciar con usuario activo';        Info='Windows no fuerza reinicio tras update si hay sesion';    Recommended=$true }
        [pscustomobject]@{ Id='DevCliTelemetry';    Name='Desactivar telemetria de CLI dev';       Info='Azure CLI, .NET, Bicep, PowerShell, NuGet; requiere nuevo shell';Recommended=$true }
        [pscustomobject]@{ Id='DisableModernStandbyNet';Name='Red desactivada en Modern Standby';  Info='AVISO: impide notificaciones push en suspension';         Recommended=$false }
    )
}

# Servicios de la opcion "Services" (recomendada, modo basico). Solo lo que
# no rompe nada: los que alguna funcion necesita pasan a Manual (arrancan
# cuando hacen falta) o a items opcionales con su aviso. Fuera de esta lista
# (auditoria de sistema, EmiTweaks.psm1:59-84): DoSvc (Store y Windows
# Update; DO FAQ de Microsoft), SharedAccess (zona movil), los cuatro de Xbox,
# WpcMonSvc (Microsoft Family), lfsvc y WerSvc (ya los cubren «Ubicacion» e
# «Informes de errores» de Privacidad, con aviso) y PcaSvc. TabletInputService
# se quita: no existe en Windows 11 y en Windows 10 rompe el teclado tactil.
# Nunca se tocan servicios de seguridad, red, audio ni de ESET.
$script:JunkServices = @(
    @{ Name='Fax';                 Start='Disabled'; Why='Servicio de fax' }
    @{ Name='RetailDemo';          Start='Disabled'; Why='Modo demostracion de tienda' }
    @{ Name='MapsBroker';          Start='Manual';   Why='Mapas descargados' }
    @{ Name='WalletService';       Start='Manual';   Why='Cartera de Microsoft' }
    @{ Name='PhoneSvc';            Start='Manual';   Why='Telefonia' }
    @{ Name='RemoteRegistry';      Start='Disabled'; Why='Registro remoto (riesgo de seguridad)' }
    @{ Name='RemoteAccess';        Start='Disabled'; Why='Enrutamiento y acceso remoto' }
    @{ Name='WMPNetworkSvc';       Start='Manual';   Why='Uso compartido de Windows Media Player' }
    @{ Name='SEMgrSvc';            Start='Manual';   Why='Pagos NFC' }
    # --- Servicios modernos (AI, SQL CEIP) ---
    @{ Name='SQLTELEMETRY';            Start='Disabled'; Why='SQL Server CEIP Telemetry' }
    @{ Name='SQLTELEMETRY$SQLEXPRESS'; Start='Disabled'; Why='SQL Express CEIP Telemetry' }
    @{ Name='WSAIFabricSvc';           Start='Manual';   Why='Windows AI Fabric Service' }
)

# Grupos opcionales (nunca en modo basico), cada uno con su aviso en Get-EmiTweaks.
$script:OptionalServices = @{
    SvcXbox     = @(
        @{ Name='XblAuthManager'; Start='Disabled'; Why='Xbox Live' }
        @{ Name='XblGameSave';    Start='Disabled'; Why='Guardado en la nube de Xbox' }
        @{ Name='XboxNetApiSvc';  Start='Disabled'; Why='Red de Xbox' }
        @{ Name='XboxGipSvc';     Start='Disabled'; Why='Accesorios de Xbox' }
    )
    SvcHotspot  = @( @{ Name='SharedAccess'; Start='Disabled'; Why='Conexion compartida a Internet' } )
    SvcParental = @( @{ Name='WpcMonSvc';    Start='Disabled'; Why='Control parental' } )
    SvcPca      = @( @{ Name='PcaSvc';       Start='Manual';   Why='Asistente de compatibilidad de programas' } )
    SvcDoSvc    = @( @{ Name='DoSvc';        Start='Manual';   Why='Delivery Optimization (descargas P2P)' } )
}

function Set-EmiServiceList {
    param([object[]] $List, [string] $Module)
    $n = 0
    foreach ($s in $List) {
        if (Set-EmiService -Name $s.Name -StartupType $s.Start -Stop -Module $Module) {
            $verb = if ($s.Start -eq 'Manual') { 'en manual' } else { 'desactivado' }
            Write-EmiLog "Servicio $($verb): $($s.Name) - $($s.Why)" Ok
            $n++
        }
    }
    return $n
}

$script:JunkTasks = @(
    @{ P='\Microsoft\Windows\Application Experience\'; N='Microsoft Compatibility Appraiser' }
    @{ P='\Microsoft\Windows\Application Experience\'; N='ProgramDataUpdater' }
    @{ P='\Microsoft\Windows\Application Experience\'; N='StartupAppTask' }
    @{ P='\Microsoft\Windows\Application Experience\'; N='PcaPatchDbTask' }
    @{ P='\Microsoft\Windows\Customer Experience Improvement Program\'; N='Consolidator' }
    @{ P='\Microsoft\Windows\Customer Experience Improvement Program\'; N='UsbCeip' }
    @{ P='\Microsoft\Windows\Customer Experience Improvement Program\'; N='KernelCeipTask' }
    @{ P='\Microsoft\Windows\DiskDiagnostic\';         N='Microsoft-Windows-DiskDiagnosticDataCollector' }
    @{ P='\Microsoft\Windows\Autochk\';                N='Proxy' }
    @{ P='\Microsoft\Windows\Feedback\Siuf\';          N='DmClient' }
    @{ P='\Microsoft\Windows\Feedback\Siuf\';          N='DmClientOnScenarioDownload' }
    @{ P='\Microsoft\Windows\Windows Error Reporting\'; N='QueueReporting' }
    @{ P='\Microsoft\Windows\CloudExperienceHost\';    N='CreateObjectTask' }
    @{ P='\Microsoft\Windows\Maps\';                   N='MapsUpdateTask' }
    @{ P='\Microsoft\Windows\Maps\';                   N='MapsToastTask' }
    @{ P='\Microsoft\Windows\Retail Demo\';            N='CleanupOfflineContent' }
)

$script:ModernStandby = $null

function Test-EmiS0InPowercfg {
    <#  Logica pura sobre la salida de powercfg /a: primero la cabecera, luego
        los estados disponibles y, tras una linea en blanco, los que no lo
        estan. Cambia el idioma, no la forma: se busca S0 en el primer bloque. #>
    param([string[]] $Lines)
    $started = $false
    foreach ($l in $Lines) {
        if (-not $started) { if ("$l".Trim()) { $started = $true }; continue }
        if (-not "$l".Trim()) { break }
        if ($l -match '\bS0\b') { return $true }
    }
    return $false
}

function Test-EmiModernStandby {
    <#  Cierto si el equipo usa Modern Standby (S0 Low Power Idle). $false si
        no se puede saber. Se calcula una vez. #>
    if ($null -ne $script:ModernStandby) { return $script:ModernStandby }
    $r = $false
    try { $r = Test-EmiS0InPowercfg -Lines @(& powercfg.exe /a 2>$null) } catch { }
    $script:ModernStandby = [bool]$r
    return $script:ModernStandby
}

function Get-EmiReservedStorageState {
    <#  'Enabled', 'Disabled' o $null. Con el cmdlet de DISM: la salida de
        dism.exe cambia con el idioma. #>
    try {
        if (Get-Command Get-WindowsReservedStorageState -ErrorAction SilentlyContinue) {
            return [string](Get-WindowsReservedStorageState -ErrorAction Stop).ReservedStorageState
        }
    } catch { }
    return $null
}

function Invoke-EmiTweak {
    <#  Aplica una optimizacion concreta. Devuelve el numero de cambios. #>
    param([Parameter(Mandatory)][string] $Id)

    $n = 0
    $M = 'Optimizacion'

    switch ($Id) {

        'Widgets' {
            if (Set-EmiRegistry $HKCU_ADV 'TaskbarDa' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 DWord $M) { $n++ }
        }

        'Copilot' {
            if (Set-EmiRegistry $HKCU_ADV 'ShowCopilotButton' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 DWord $M) { $n++ }
        }

        'Chat' {
            if (Set-EmiRegistry $HKCU_ADV 'TaskbarMn' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 3 DWord $M) { $n++ }
        }

        'WebSearch' {
            if (Set-EmiRegistry $HKCU_SEARCH 'BingSearchEnabled' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry $HKCU_SEARCH 'CortanaConsent' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry $HKLM_POL_WS 'DisableWebSearch' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry $HKLM_POL_WS 'ConnectedSearchUseWeb' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry $HKLM_POL_WS 'AllowCortana' 0 DWord $M) { $n++ }
        }

        'Suggest' {
            $vals = @(
                'SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-338393Enabled',
                'SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SubscribedContent-310093Enabled',
                'SubscribedContent-314559Enabled','SubscribedContent-338387Enabled','SubscribedContent-88000326Enabled',
                'SystemPaneSuggestionsEnabled','SilentInstalledAppsEnabled','SoftLandingEnabled',
                'RotatingLockScreenOverlayEnabled','ContentDeliveryAllowed','PreInstalledAppsEnabled',
                'OemPreInstalledAppsEnabled','FeatureManagementEnabled'
            )
            foreach ($v in $vals) { if (Set-EmiRegistry $HKCU_CDM $v 0 DWord $M) { $n++ } }
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1 DWord $M) { $n++ }
        }

        'StartRec' {
            if (Set-EmiRegistry $HKCU_ADV 'Start_TrackDocs' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry $HKCU_ADV 'Start_TrackProgs' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecommendedSection' 1 DWord $M) { $n++ }
        }

        'GameDVR' {
            if (Set-EmiRegistry 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\GameBar' 'ShowStartupPanel' 0 DWord $M) { $n++ }
        }

        'BgApps' {
            # Solo el ajuste del usuario. La directiva de equipo
            # LetAppsRunInBackground=2 prohibia el segundo plano a todas las
            # apps de la Store sin que el usuario pudiera reactivar ninguna
            # (auditoria de sistema, EmiTweaks.psm1:168-169).
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1 DWord $M) { $n++ }
        }

        'Context' {
            # El menu clasico sale si existe la clave con (predeterminado) vacio.
            # Set-EmiRegistry anota la clave {86ca1aa0} si la crea (Revertir la
            # quita entera) y no toca ni anota nada si ya tenias el menu clasico.
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(default)' '' String $M) {
                Write-EmiLog 'Menu contextual clasico activado (se ve al reiniciar el Explorador).' Ok
                $n++
            }
        }

        'Explorer' {
            if (Set-EmiRegistry $HKCU_ADV 'LaunchTo' 1 DWord $M) { $n++ }          # Este equipo
            if (Set-EmiRegistry $HKCU_ADV 'HideFileExt' 0 DWord $M) { $n++ }       # ver extensiones
            if (Set-EmiRegistry $HKCU_ADV 'ShowSyncProviderNotifications' 0 DWord $M) { $n++ }
        }

        'Services' { $n += Set-EmiServiceList -List $script:JunkServices -Module $M }

        { $_ -in 'SvcXbox', 'SvcHotspot', 'SvcParental', 'SvcPca', 'SvcDoSvc' } {
            $n += Set-EmiServiceList -List $script:OptionalServices[$_] -Module $M
        }

        'Tasks' {
            foreach ($t in $script:JunkTasks) {
                if (Disable-EmiScheduledTask -TaskPath $t.P -TaskName $t.N -Module $M) {
                    Write-EmiLog "Tarea desactivada: $($t.N)" Ok
                    $n++
                }
            }
        }

        'NetworkOpt' {
            # Autotuning: normal es el valor de fabrica. Solo se cambia si estaba
            # en otro nivel, y se anota cual para que Revertir lo devuelva.
            $lvl = $null
            try { $lvl = [string](Get-NetTCPSetting -SettingName Internet -ErrorAction Stop | Select-Object -First 1).AutoTuningLevelLocal } catch { }
            if (-not $lvl) { Write-EmiLog 'No se pudo leer el autotuning de TCP: no se toca.' Warn }
            elseif ($lvl -eq 'Normal') { Write-EmiLog 'El autotuning de TCP ya estaba en normal.' Ok }
            elseif ($lvl.ToLowerInvariant() -notin @('disabled', 'restricted', 'highlyrestricted', 'experimental')) {
                Write-EmiLog "Autotuning de TCP en un nivel desconocido ($lvl): no se toca." Warn
            }
            else {
                & netsh.exe int tcp set global autotuninglevel=normal 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Add-EmiJournalEntry @{ Kind='Command'; Action='TcpAutotuning'; OldLevel=$lvl.ToLowerInvariant(); Module=$M }
                    Write-EmiLog "Autotuning de TCP: de $lvl a normal." Ok; $n++
                } else { Write-EmiLog "netsh devolvio $LASTEXITCODE`: el autotuning sigue igual." Warn }
            }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xffffffff DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10 DWord $M) { $n++ }
        }

        'PowerPlan' {
            # Con Modern Standby (S0) solo existe Equilibrado: el plan Alto
            # rendimiento no aparece o no hace nada (Microsoft Q&A, "Windows 11
            # High Performance power plan"). Ahi se usa el modo de energia.
            if (Test-EmiModernStandby) {
                Write-EmiLog 'Este equipo usa Modern Standby y solo tiene el plan Equilibrado. Usa Configuracion > Sistema > Energia > Modo de energia. No se cambia nada.' Warn
                break
            }
            $hp   = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'   # Alto rendimiento
            $mine = Get-EmiPowerSchemeGuid                    # copia propia, GUID fijo
            $prev = Get-EmiActivePowerScheme
            if (-not $prev) { Write-EmiLog 'No se pudo leer el plan de energia activo: no se cambia nada.' Warn; break }
            if ($prev -in @($hp, $mine)) { Write-EmiLog 'El plan Alto rendimiento ya estaba activo.' Ok; break }
            $list = (& powercfg.exe /list 2>$null) -join "`n"
            $target = $null; $created = $null
            if ($list -match $hp) { $target = $hp }
            elseif ($list -match $mine) { $target = $mine }
            else {
                # Una sola copia, siempre con el mismo GUID: antes se duplicaba en cada ejecucion
                & powercfg.exe /duplicatescheme $hp $mine 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { $target = $mine; $created = $mine }
            }
            if (-not $target) { Write-EmiLog 'Este equipo no tiene el plan Alto rendimiento: no se cambia nada.' Warn; break }
            & powercfg.exe /setactive $target 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0 -or (Get-EmiActivePowerScheme) -ne $target) {
                Write-EmiLog 'No se pudo activar el plan Alto rendimiento: sigue el plan anterior.' Warn
                if ($created) { & powercfg.exe /delete $created 2>&1 | Out-Null }
                break
            }
            Add-EmiJournalEntry @{ Kind='Command'; Action='PowerScheme'; OldGuid=$prev; CreatedGuid=$created; Module=$M }
            Write-EmiLog 'Plan de energia: Alto rendimiento (Revertir vuelve al anterior).' Ok
            $n++
        }

        'SysMain'  { if (Set-EmiService -Name 'SysMain' -StartupType Disabled -Stop -Module $M) { $n++ } }
        'WSearch'  { if (Set-EmiService -Name 'WSearch' -StartupType Disabled -Stop -Module $M) { $n++ } }

        'OneDrive' {
            $k = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            if ((Get-ItemProperty -LiteralPath $k -Name 'OneDrive' -ErrorAction SilentlyContinue)) {
                Add-EmiJournalEntry @{
                    Kind='Registry'; Path=$k; Name='OneDrive'; Existed=$true; OldType='String'
                    OldValue=(Get-ItemProperty -LiteralPath $k -Name 'OneDrive').OneDrive; Module=$M
                }
                Remove-ItemProperty -LiteralPath $k -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
                Write-EmiLog 'OneDrive ya no se inicia con Windows.' Ok
                $n++
            }
        }

        'Hibernate' {
            try { if (Disable-EmiHibernation -Module $M) { $n++ } }
            catch { Write-EmiLog "Hibernacion: $($_.Exception.Message)" Warn }
        }

        'Reserved' {
            # Se mira el estado antes y despues: con una actualizacion en curso
            # Windows no deja cambiarlo, y antes se daba por hecho igualmente.
            $st = Get-EmiReservedStorageState
            if ($st -eq 'Disabled') { Write-EmiLog 'El almacenamiento reservado ya estaba desactivado.' Ok; break }
            if ($st -ne 'Enabled') { Write-EmiLog 'No se pudo leer el estado del almacenamiento reservado: no se toca.' Warn; break }
            $ok = $false
            try {
                if (Get-Command Set-WindowsReservedStorageState -ErrorAction SilentlyContinue) {
                    Set-WindowsReservedStorageState -State Disabled -ErrorAction Stop | Out-Null
                } else {
                    & dism.exe /Online /Set-ReservedStorageState /State:Disabled /NoRestart 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "DISM devolvio $LASTEXITCODE" }
                }
                $ok = ((Get-EmiReservedStorageState) -ne 'Enabled')
            } catch { Write-EmiLog "Almacenamiento reservado: $($_.Exception.Message)" Warn }
            if ($ok) {
                Add-EmiJournalEntry @{ Kind='Command'; Action='ReservedStorage'; OldState='Enabled'; Module=$M }
                Write-EmiLog 'Almacenamiento reservado desactivado (Revertir lo reactiva).' Ok
                $n++
            } else { Write-EmiLog 'El almacenamiento reservado sigue activo (Windows no deja cambiarlo con una actualizacion pendiente).' Warn }
        }

        # --- Win11Debloat: UI/UX, Update, Dev CLI, AI services ---
        'TaskbarAlignLeft' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAl' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'HideTaskView' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowTaskViewButton' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'ShowEndTask' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Name 'TaskbarEndTask' -Value 1 -Type DWord -Module $M) { $n++ }
        }
        'DisableSnapAssist' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'EnableSnapAssistFlyout' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'DisableTransparency' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'DisableAnimations' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Type DWord -Module $M) { $n++ }
        }
        'ForceDarkMode' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -Value 0 -Type DWord -Module $M) { $n++ }
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'HideGalleryNav' {
            # CLSID de Galeria. El anterior, {0DB7E03F-...}, era el de Objetos 3D
            # de Windows 10 y no hacia nada (Pureinfotech, Winaero).
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'HideHomeFolder' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'HideOneDriveNav' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'DisableMouseAccel' {
            if (Set-EmiRegistry -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSensitivity' -Value '10' -Type String -Module $M) { $n++ }
            if (Set-EmiRegistry -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Type String -Module $M) { $n++ }
            if (Set-EmiRegistry -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Type String -Module $M) { $n++ }
            if (Set-EmiRegistry -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Type String -Module $M) { $n++ }
            if (Set-EmiRegistry -Path 'HKCU:\Control Panel\Mouse' -Name 'SmoothMouseXCurve' -Value ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xC0,0xCC,0x0C,0x00,0x00,0x00,0x00,0x00,0x80,0x99,0x19,0x00,0x00,0x00,0x00,0x00,0x40,0x66,0x26,0x00,0x00,0x00,0x00,0x00,0x00,0x33,0x33,0x00,0x00,0x00,0x00,0x00)) -Type Binary -Module $M) { $n++ }
            if (Set-EmiRegistry -Path 'HKCU:\Control Panel\Mouse' -Name 'SmoothMouseYCurve' -Value ([byte[]](0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x70,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xA8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xE0,0x00,0x00,0x00,0x00,0x00)) -Type Binary -Module $M) { $n++ }
        }
        'DisableStickyKeys' {
            if (Set-EmiRegistry -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '506' -Type String -Module $M) { $n++ }
        }
        'DisableStorageSense' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' -Name 'ConfigStorageSenseGlobalOn' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'DisableBitLockerAuto' {
            if (Set-EmiRegistry -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' -Name 'PreventDeviceEncryption' -Value 1 -Type DWord -Module $M) { $n++ }
        }
        'DisableDragTray' {
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'DragDropTrayEnabled' -Value 0 -Type DWord -Module $M) { $n++ }
        }
        'DelayUpdates' {
            # Sin DeferQualityUpdates=1 el periodo no se aplica; y es una directiva
            # de Windows Update para empresas: en Home no hace nada (Configure
            # Windows Update client policies; Policy CSP Update).
            $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            $ed = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction SilentlyContinue).EditionID
            if ("$ed" -like 'Core*') {
                Write-EmiLog "Retrasar actualizaciones: tu edicion ($ed, Home) no aplica esta directiva. No se cambia nada." Warn
            } else {
                if (Set-EmiRegistry -Path $wu -Name 'DeferQualityUpdates' -Value 1 -Type DWord -Module $M) { $n++ }
                if (Set-EmiRegistry -Path $wu -Name 'DeferQualityUpdatesPeriodInDays' -Value 7 -Type DWord -Module $M) { $n++ }
                Write-EmiLog 'Los parches de seguridad mensuales tambien llegaran 7 dias tarde.' Warn
            }
        }
        'NoAutoRestart' {
            if (Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1 -Type DWord -Module $M) { $n++ }
        }
        'DevCliTelemetry' {
            try {
                $vars = [ordered]@{
                    AZURE_CORE_COLLECT_TELEMETRY = 'false'
                    DOTNET_CLI_TELEMETRY_OPTOUT  = '1'
                    BICEP_TELEMETRY_OPTOUT       = 'true'
                    POWERSHELL_TELEMETRY_OPTOUT  = '1'
                    NUGET_TELEMETRY_OPTOUT       = 'true'
                }
                # Se guarda el valor previo de cada variable (null = no existia)
                $old = @(foreach ($k in $vars.Keys) {
                    [pscustomobject]@{ Name = $k; OldValue = [System.Environment]::GetEnvironmentVariable($k, 'User') }
                })
                foreach ($k in $vars.Keys) { [System.Environment]::SetEnvironmentVariable($k, $vars[$k], 'User') }
                Add-EmiJournalEntry @{ Kind='Command'; Action='EnvVars'; Scope='User'; Variables=$old; Module=$M }
                Write-EmiLog 'Variables de entorno CLI dev configuradas (requiere nuevo shell).' Ok
                $n++
            } catch { Write-EmiLog "Env vars CLI: $($_.Exception.Message)" Warn }
        }
        'DisableModernStandbyNet' {
            if (Set-EmiRegistry -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'StandbyNetworkConnectivity' -Value 0 -Type DWord -Module $M) { $n++ }
        }
    }

    return $n
}

function Invoke-EmiTweakSet {
    <#  Aplica una lista de optimizaciones con progreso. #>
    param([string[]] $Ids)

    $all   = Get-EmiTweaks
    $total = 0
    $i     = 0

    foreach ($id in $Ids) {
        $i++
        $tw = $all | Where-Object { $_.Id -eq $id }
        $label = if ($tw) { $tw.Name } else { $id }
        Set-EmiStatus $label ([int](($i / [math]::Max(1, $Ids.Count)) * 100))
        Write-EmiLog $label Step
        $total += Invoke-EmiTweak -Id $id
    }

    Write-EmiLog "Optimizacion terminada: $total ajustes aplicados." Ok
    Set-EmiStatus 'Optimizacion terminada' 100
    return $total
}

function Restart-EmiExplorer {
    try {
        Write-EmiLog 'Reiniciando el Explorador para aplicar los cambios...' Step
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 900
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        Write-EmiLog 'Explorador reiniciado.' Ok
        return $true
    } catch { return $false }
}

Export-ModuleMember -Function *-Emi*
