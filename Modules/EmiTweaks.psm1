# =====================================================================
#  EmiTweaks.psm1 - Optimizacion de Windows 11
#  NO toca transparencia ni animaciones (peticion explicita).
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
        [pscustomobject]@{ Id='BgApps';     Name='Desactivar apps en segundo plano';           Info='Las apps de la Store dejan de correr ocultas';       Recommended=$true }
        [pscustomobject]@{ Id='Context';    Name='Menu contextual clasico (Win10)';            Info='Sin el paso extra de "Mostrar mas opciones"';        Recommended=$true }
        [pscustomobject]@{ Id='Explorer';   Name='Explorador: abrir en Este equipo';           Info='Tambien muestra extensiones de archivo';             Recommended=$true }
        [pscustomobject]@{ Id='Services';   Name='Desactivar servicios innecesarios';          Info='Fax, RetailDemo, MapsBroker, WalletService, etc.';   Recommended=$true }
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
        [pscustomobject]@{ Id='HideGalleryNav';     Name='Ocultar Galeria en panel de navegacion'; Info='Limpia el panel izquierdo del Explorador';                Recommended=$true }
        [pscustomobject]@{ Id='HideHomeFolder';     Name='Ocultar carpeta Inicio en panel nav';    Info='Quita acceso directo a Inicio en Explorador';             Recommended=$true }
        [pscustomobject]@{ Id='HideOneDriveNav';    Name='Ocultar OneDrive en panel de navegacion';Info='Solo oculta el acceso directo; no desinstala OneDrive';   Recommended=$true }
        [pscustomobject]@{ Id='DisableMouseAccel';  Name='Desactivar aceleracion del mouse';       Info='Movimiento lineal 1:1; preferido por gamers';             Recommended=$false }
        [pscustomobject]@{ Id='DisableStickyKeys';  Name='Desactivar atajo de Sticky Keys';        Info='Evita activacion accidental con 5 pulsaciones de Shift';  Recommended=$true }
        [pscustomobject]@{ Id='DisableStorageSense';Name='Desactivar Storage Sense automatico';    Info='Impide limpieza automatica de archivos temporales';       Recommended=$false }
        [pscustomobject]@{ Id='DisableBitLockerAuto';Name='Desactivar cifrado automatico BitLocker';Info='Evita cifrado silencioso en dispositivos compatibles';   Recommended=$false }
        [pscustomobject]@{ Id='DisableDragTray';    Name='Desactivar bandeja de arrastre';         Info='Quita el area de compartir archivos al arrastrar';        Recommended=$true }
        [pscustomobject]@{ Id='DelayUpdates';       Name='Retrasar actualizaciones de calidad 7d'; Info='AVISO: solo calidad, nunca seguridad; puede perder parches';Recommended=$false }
        [pscustomobject]@{ Id='NoAutoRestart';      Name='No reiniciar con usuario activo';        Info='Windows no fuerza reinicio tras update si hay sesion';    Recommended=$true }
        [pscustomobject]@{ Id='DevCliTelemetry';    Name='Desactivar telemetria de CLI dev';       Info='Azure CLI, .NET, Bicep, PowerShell, NuGet; requiere nuevo shell';Recommended=$true }
        [pscustomobject]@{ Id='DisableModernStandbyNet';Name='Red desactivada en Modern Standby';  Info='AVISO: impide notificaciones push en suspension';         Recommended=$false }
    )
}

# Servicios que se desactivan con la opcion "Services".
# Nunca se tocan servicios de seguridad, red, audio ni de ESET.
$script:JunkServices = @(
    @{ Name='Fax';                 Why='Servicio de fax' }
    @{ Name='RetailDemo';          Why='Modo demostracion de tienda' }
    @{ Name='MapsBroker';          Why='Mapas descargados' }
    @{ Name='WalletService';       Why='Cartera de Microsoft' }
    @{ Name='PhoneSvc';            Why='Telefonia' }
    @{ Name='RemoteRegistry';      Why='Registro remoto (riesgo de seguridad)' }
    @{ Name='RemoteAccess';        Why='Enrutamiento y acceso remoto' }
    @{ Name='SharedAccess';        Why='Conexion compartida a Internet' }
    @{ Name='lfsvc';               Why='Servicio de geolocalizacion' }
    @{ Name='WMPNetworkSvc';       Why='Uso compartido de Windows Media Player' }
    @{ Name='XblAuthManager';      Why='Xbox Live' }
    @{ Name='XblGameSave';         Why='Guardado en la nube de Xbox' }
    @{ Name='XboxNetApiSvc';       Why='Red de Xbox' }
    @{ Name='XboxGipSvc';          Why='Accesorios de Xbox' }
    @{ Name='SEMgrSvc';            Why='Pagos NFC' }
    @{ Name='PcaSvc';              Why='Asistente de compatibilidad de programas' }
    @{ Name='WerSvc';              Why='Informe de errores de Windows' }
    @{ Name='DoSvc';               Why='Delivery Optimization (descargas P2P)' }
    @{ Name='WpcMonSvc';           Why='Control parental' }
    @{ Name='TabletInputService';  Why='Teclado en pantalla / panel de escritura' }
    # --- Servicios modernos (AI, SQL CEIP) ---
    @{ Name='SQLTELEMETRY';            Why='SQL Server CEIP Telemetry' }
    @{ Name='SQLTELEMETRY$SQLEXPRESS'; Why='SQL Express CEIP Telemetry' }
    @{ Name='WSAIFabricSvc';           Why='Windows AI Fabric Service' }
)

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
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2 DWord $M) { $n++ }
        }

        'Context' {
            $k = 'HKCU:\SOFTWARE\CLASSES\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
            try {
                if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
                Set-ItemProperty -LiteralPath $k -Name '(default)' -Value '' -Force
                Add-EmiJournalEntry @{ Kind='Registry'; Path=$k; Name='(default)'; Existed=$false; Module=$M }
                $n++
            } catch { }
        }

        'Explorer' {
            if (Set-EmiRegistry $HKCU_ADV 'LaunchTo' 1 DWord $M) { $n++ }          # Este equipo
            if (Set-EmiRegistry $HKCU_ADV 'HideFileExt' 0 DWord $M) { $n++ }       # ver extensiones
            if (Set-EmiRegistry $HKCU_ADV 'ShowSyncProviderNotifications' 0 DWord $M) { $n++ }
        }

        'Services' {
            foreach ($s in $script:JunkServices) {
                if (Set-EmiService -Name $s.Name -StartupType Disabled -Stop -Module $M) {
                    Write-EmiLog "Servicio desactivado: $($s.Name) - $($s.Why)" Ok
                    $n++
                }
            }
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
            try {
                & netsh.exe int tcp set global autotuninglevel=normal | Out-Null
                Write-EmiLog 'Autotuning TCP en normal.' Ok; $n++
            } catch { }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xffffffff DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10 DWord $M) { $n++ }
        }

        'PowerPlan' {
            try {
                $guid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'   # Alto rendimiento
                & powercfg.exe -duplicatescheme $guid 2>$null | Out-Null
                & powercfg.exe -setactive $guid 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-EmiLog 'Plan de energia: Alto rendimiento.' Ok; $n++ }
                else {
                    & powercfg.exe -setactive SCHEME_MIN 2>$null | Out-Null
                    Write-EmiLog 'Plan de energia ajustado.' Ok; $n++
                }
            } catch { Write-EmiLog "Plan de energia: $($_.Exception.Message)" Warn }
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
            try {
                & powercfg.exe /hibernate off | Out-Null
                Write-EmiLog 'Hibernacion desactivada (hiberfil.sys liberado).' Ok
                Add-EmiJournalEntry @{ Kind='Command'; Undo='powercfg /hibernate on'; Module=$M }
                $n++
            } catch { Write-EmiLog "Hibernacion: $($_.Exception.Message)" Warn }
        }

        'Reserved' {
            try {
                & dism.exe /Online /Set-ReservedStorageState /State:Disabled 2>&1 | Out-Null
                Write-EmiLog 'Almacenamiento reservado desactivado.' Ok
                $n++
            } catch { Write-EmiLog "Almacenamiento reservado: $($_.Exception.Message)" Warn }
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
            if (Set-EmiRegistry -Path 'HKCU:\SOFTWARE\Classes\CLSID\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord -Module $M) { $n++ }
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
            if (Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'DeferQualityUpdatesPeriodInDays' -Value 7 -Type DWord -Module $M) { $n++ }
        }
        'NoAutoRestart' {
            if (Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1 -Type DWord -Module $M) { $n++ }
        }
        'DevCliTelemetry' {
            try {
                [System.Environment]::SetEnvironmentVariable('AZURE_CORE_COLLECT_TELEMETRY', 'false', 'User')
                [System.Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', '1', 'User')
                [System.Environment]::SetEnvironmentVariable('BICEP_TELEMETRY_OPTOUT', 'true', 'User')
                [System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'User')
                [System.Environment]::SetEnvironmentVariable('NUGET_TELEMETRY_OPTOUT', 'true', 'User')
                Add-EmiJournalEntry @{ Kind='Command'; Undo="[System.Environment]::SetEnvironmentVariable('AZURE_CORE_COLLECT_TELEMETRY',$null,'User');[System.Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT',$null,'User');[System.Environment]::SetEnvironmentVariable('BICEP_TELEMETRY_OPTOUT',$null,'User');[System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT',$null,'User');[System.Environment]::SetEnvironmentVariable('NUGET_TELEMETRY_OPTOUT',$null,'User')"; Module=$M }
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
