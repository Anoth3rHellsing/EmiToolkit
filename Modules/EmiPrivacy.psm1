# =====================================================================
#  EmiPrivacy.psm1 - Quitar telemetria y devolver el equipo al usuario
#  No toca Windows Defender, Windows Update ni la activacion.
# =====================================================================

function Get-EmiPrivacyItems {
    <#  Editions / MaxBuild: donde surte efecto (EmiCore, Get-EmiItemSkipReason). #>
    Update-EmiCatalogForEdition @(
        [pscustomobject]@{ Id='Telemetry';  Name='Telemetria de diagnostico al minimo';      Info='El minimo que admite tu edicion: Seguridad (0) en Enterprise y Education; Obligatorio (1) en Home y Pro'; Recommended=$true }
        [pscustomobject]@{ Id='DiagTrack';  Name='Detener el servicio DiagTrack';            Info='Experiencias del usuario conectado y telemetria';       Recommended=$true }
        [pscustomobject]@{ Id='AdvertId';   Name='Quitar el ID de publicidad';               Info='Las apps dejan de perfilar al usuario';                 Recommended=$true }
        [pscustomobject]@{ Id='Tailored';   Name='Quitar experiencias personalizadas';       Info='Sin anuncios adaptados a tus datos de diagnostico';     Recommended=$true }
        [pscustomobject]@{ Id='Feedback';   Name='Nunca pedir comentarios';                  Info='Quita las encuestas de Windows';                        Recommended=$true }
        [pscustomobject]@{ Id='Activity';   Name='Desactivar historial de actividad';        Info='Sin linea de tiempo ni envio a la nube';                Recommended=$true }
        [pscustomobject]@{ Id='Speech';     Name='Desactivar reconocimiento de voz en linea';Info='Sin envio de audio a Microsoft';                        Recommended=$true }
        [pscustomobject]@{ Id='InkTyping';  Name='Desactivar datos de escritura y entintado';Info='Sin envio de lo que escribes';                          Recommended=$true }
        [pscustomobject]@{ Id='AppDiag';    Name='Bloquear diagnostico entre aplicaciones';  Info='Las apps no ven que hacen otras apps';                  Recommended=$true }
        [pscustomobject]@{ Id='AppAccountInfo'; Name='Impedir que las apps lean tu cuenta';  Info='Nombre, foto y cuenta; OJO: apps que entran con tu cuenta de Microsoft pueden pedirla otra vez'; Recommended=$false }
        [pscustomobject]@{ Id='AppSyncDevices'; Name='Impedir que las apps hablen con dispositivos no emparejados'; Info='OJO: corta relojes y pulseras, Enlace Movil y apps de accesorios de la Store'; Recommended=$false }
        [pscustomobject]@{ Id='WER';        Name='Desactivar informes de errores';           Info='AVISO: oculta info de crashes a admins IT';              Recommended=$false }
        [pscustomobject]@{ Id='CEIPTasks';  Name='Desactivar tareas de telemetria';          Info='Appraiser, Consolidator, UsbCeip, DmClient';            Recommended=$true }
        [pscustomobject]@{ Id='EdgeTel';    Name='Quitar telemetria de Microsoft Edge';      Info='Sin metricas, sin sugerencias, sin busqueda enviada';   Recommended=$true }
        [pscustomobject]@{ Id='CloudSearch';Name='Quitar contenido en la nube de la busqueda';Info='La busqueda no consulta a Microsoft';                  Recommended=$true }
        [pscustomobject]@{ Id='DeliveryOpt';Name='Delivery Optimization solo en LAN';        Info='Tu ancho de banda deja de servir a Internet';           Recommended=$true }
        [pscustomobject]@{ Id='Location';   Name='Desactivar el sensor de ubicacion';        Info='OJO: afecta a Mapas, "Buscar mi dispositivo" y la zona horaria automatica';Recommended=$false }
        [pscustomobject]@{ Id='FirewallTel';Name='Bloquear en el firewall los procesos de telemetria';Info='Reglas de salida para DiagTrack y CompatTel';  Recommended=$false }
        [pscustomobject]@{ Id='HostsBlock'; Name='Bloquear dominios de telemetria (hosts)';  Info='AVISO: Defender lo marca como HostsFileHijack y al quitarlo restablece el hosts entero'; Recommended=$false }
        # --- Telemetria moderna (Copilot, Recall, AI, Edge, WebView2, winget) ---
        # TurnOffWindowsCopilot esta obsoleta y "no es para la nueva experiencia de
        # Copilot" (Policy CSP WindowsAI): desde 24H2 Copilot es una app y no le
        # afecta. La directiva nueva, RemoveMicrosoftCopilotApp (25H2 + KB5083769),
        # no esta verificada aqui; lo que funciona en todas las ediciones es
        # desinstalar la app (Debloat > Copilot).
        [pscustomobject]@{ Id='DisableCopilot';    Name='Desactivar Windows Copilot (directiva antigua)'; Info='Solo Windows 11 23H2 y anteriores; desde 24H2 quita la app Copilot en Debloat'; Recommended=$false; MaxBuild=22631 }
        # Policy CSP WindowsAI (AllowRecallEnablement, DisableAIDataAnalysis):
        # Pro, Enterprise y Education; en Home, Recall se quita como caracteristica
        [pscustomobject]@{ Id='DisableRecall';     Name='Desactivar Recall y Snapshots';           Info='Impide captura e indexacion local por IA; sin efecto en PC sin NPU'; Recommended=$true; Editions=@('Pro','Enterprise','Education') }
        [pscustomobject]@{ Id='LimitAIDiagnostics';Name='Limitar diagnosticos de IA';              Info='Suplementario a Telemetria; restringe logs y dumps de diagnostico'; Recommended=$true }
        [pscustomobject]@{ Id='DisableEdgeShopping';Name='Desactivar Shopping en Edge';            Info='Quita el asistente de compras y cupones de Edge';                   Recommended=$true }
        [pscustomobject]@{ Id='DisableEdgeSidebar';Name='Desactivar Sidebar y Copilot en Edge';    Info='OJO: la barra lateral y el icono Copilot dejan de estar disponibles';Recommended=$false }
        [pscustomobject]@{ Id='LimitWebView2';     Name='Limitar telemetria de WebView2';          Info='AVANZADO: puede romper apps que usan WebView2 (Teams, Outlook)';    Recommended=$false }
        [pscustomobject]@{ Id='DisableWingetTelemetry';Name='Desactivar telemetria de winget';     Info='App Installer deja de enviar datos de diagnostico';                 Recommended=$true }
        [pscustomobject]@{ Id='DisableDOP2PFull';  Name='Delivery Optimization: solo HTTP';        Info='AVANZADO: desactiva todo P2P; aumenta uso de ancho de banda WAN';   Recommended=$false }
    )
}

$script:TelemetryHosts = @(
    'vortex.data.microsoft.com'
    'vortex-win.data.microsoft.com'
    'telecommand.telemetry.microsoft.com'
    'telecommand.telemetry.microsoft.com.nsatc.net'
    'oca.telemetry.microsoft.com'
    'sqm.telemetry.microsoft.com'
    'watson.telemetry.microsoft.com'
    'redir.metaservices.microsoft.com'
    'choice.microsoft.com'
    'df.telemetry.microsoft.com'
    'reports.wes.df.telemetry.microsoft.com'
    'services.wes.df.telemetry.microsoft.com'
    'sqm.df.telemetry.microsoft.com'
    'telemetry.microsoft.com'
    'watson.ppe.telemetry.microsoft.com'
    'telemetry.appex.bing.net'
    'telemetry.urs.microsoft.com'
    'settings-sandbox.data.microsoft.com'
    'vortex-sandbox.data.microsoft.com'
    'survey.watson.microsoft.com'
    'watson.live.com'
    'statsfe2.ws.microsoft.com'
    'statsfe1.ws.microsoft.com'
    'corpext.msitadfs.glbdns2.microsoft.com'
    'compatexchange.cloudapp.net'
    # --- Dominios modernos (Aria, Teams) ---
    # NOTA: self.events.data.microsoft.com y storeedgefd.dsx.mp.microsoft.com
    # excluidos deliberadamente: rompen Microsoft Store y auth M365.
    # copilot.cloud.microsoft tampoco: no es telemetria, es el propio
    # servicio de Copilot.
    'browser.pipe.aria.microsoft.com'
    'mobile.pipe.aria.microsoft.com'
    'teams.events.data.microsoft.com'
    'diagnostics.support.microsoft.com'
    'feedback.windows.com'
    'feedback.microsoft-hohm.com'
    'feedback.search.microsoft.com'
)

$script:HostsMarker = '# --- EmiToolkit: bloqueo de telemetria ---'

function Invoke-EmiPrivacyItem {
    param([Parameter(Mandatory)][string] $Id)

    $n = 0
    $M = 'Privacidad'
    $def = @(Get-EmiPrivacyItems | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1
    if ($def -and -not (Test-EmiItemApplies -Item $def)) { return 0 }

    switch ($Id) {

        'Telemetry' {
            # AllowTelemetry=0 (Seguridad) solo existe en Enterprise, Education,
            # IoT y Server; en Home y Pro Windows lo trata como 1 (Policy CSP
            # System, AllowTelemetry; CIS Microsoft Intune for Windows 11).
            # Ahi se escribe 1, que es lo que de verdad se aplica.
            $lvl = if (Test-EmiEditionApplies -Editions @('Enterprise','Education','Server')) { 0 } else { 1 }
            if ($lvl -eq 1) { Write-EmiLog "Telemetria: tu edicion ($((Get-EmiWindowsEdition).Family)) no admite el nivel Seguridad (0); se pone el minimo que admite, Obligatorio (1)." Info }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' $lvl DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'MaxTelemetryAllowed' $lvl DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDiagnosticLogCollection' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDumpCollection' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' $lvl DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowDeviceNameInTelemetry' 0 DWord $M) { $n++ }
        }

        'DiagTrack' {
            if (Set-EmiService -Name 'DiagTrack' -StartupType Disabled -Stop -Module $M) { $n++; Write-EmiLog 'DiagTrack detenido y desactivado.' Ok }
            if (Set-EmiService -Name 'dmwappushservice' -StartupType Disabled -Stop -Module $M) { $n++ }
            if (Set-EmiService -Name 'diagnosticshub.standardcollector.service' -StartupType Disabled -Stop -Module $M) { $n++ }
            # Sesiones de rastreo AutoLogger
            foreach ($al in @('AutoLogger-Diagtrack-Listener','SQMLogger')) {
                $k = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$al"
                if (Test-Path $k) { if (Set-EmiRegistry $k 'Start' 0 DWord $M) { $n++ } }
            }
        }

        'AdvertId' {
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1 DWord $M) { $n++ }
        }

        'Tailored' {
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1 DWord $M) { $n++ }
        }

        'Feedback' {
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0 DWord $M) { $n++ }
        }

        'Activity' {
            $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
            if (Set-EmiRegistry $k 'EnableActivityFeed' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry $k 'PublishUserActivities' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry $k 'UploadUserActivities' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry $k 'AllowClipboardHistory' 1 DWord $M) { $n++ }        # local si, nube no
            if (Set-EmiRegistry $k 'AllowCrossDeviceClipboard' 0 DWord $M) { $n++ }
        }

        'Speech' {
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Speech' 'AllowSpeechModelUpdate' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 0 DWord $M) { $n++ }
        }

        'InkTyping' {
            $k = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization'
            if (Set-EmiRegistry $k 'RestrictImplicitInkCollection' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry $k 'RestrictImplicitTextCollection' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry "$k\TrainedDataStore" 'HarvestContacts' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Input\TIPC' 'Enabled' 0 DWord $M) { $n++ }
        }

        'AppDiag' {
            $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
            if (Set-EmiRegistry $k 'LetAppsGetDiagnosticInfo' 2 DWord $M) { $n++ }
        }

        # Antes iban dentro de AppDiag, en modo basico y sin decirlo en la
        # etiqueta (auditoria de sistema, EmiPrivacy.psm1:148-153).
        'AppAccountInfo' {
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessAccountInfo' 2 DWord $M) { $n++ }
        }

        'AppSyncDevices' {
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsSyncWithDevices' 2 DWord $M) { $n++ }
        }

        'WER' {
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 DWord $M) { $n++ }
            if (Set-EmiService -Name 'WerSvc' -StartupType Disabled -Stop -Module $M) { $n++ }
        }

        'CEIPTasks' {
            $tasks = @(
                @{ P='\Microsoft\Windows\Application Experience\'; N='Microsoft Compatibility Appraiser' }
                @{ P='\Microsoft\Windows\Application Experience\'; N='ProgramDataUpdater' }
                @{ P='\Microsoft\Windows\Customer Experience Improvement Program\'; N='Consolidator' }
                @{ P='\Microsoft\Windows\Customer Experience Improvement Program\'; N='UsbCeip' }
                @{ P='\Microsoft\Windows\Customer Experience Improvement Program\'; N='KernelCeipTask' }
                @{ P='\Microsoft\Windows\Feedback\Siuf\'; N='DmClient' }
                @{ P='\Microsoft\Windows\Feedback\Siuf\'; N='DmClientOnScenarioDownload' }
                @{ P='\Microsoft\Windows\Windows Error Reporting\'; N='QueueReporting' }
                @{ P='\Microsoft\Windows\Autochk\'; N='Proxy' }
                @{ P='\Microsoft\Windows\PI\'; N='Sqm-Tasks' }
            )
            foreach ($t in $tasks) {
                if (Disable-EmiScheduledTask -TaskPath $t.P -TaskName $t.N -Module $M) { $n++; Write-EmiLog "Tarea desactivada: $($t.N)" Ok }
            }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 1 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0 DWord $M) { $n++ }
        }

        'EdgeTel' {
            $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
            foreach ($v in @('MetricsReportingEnabled','SendSiteInfoToImproveServices','PersonalizationReportingEnabled',
                             'UserFeedbackAllowed','EdgeCollectionsEnabled','ShowRecommendationsEnabled',
                             'AlternateErrorPagesEnabled','SearchSuggestEnabled','DiagnosticData')) {
                if (Set-EmiRegistry $k $v 0 DWord $M) { $n++ }
            }
        }

        'CloudSearch' {
            $k = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings'
            if (Set-EmiRegistry $k 'IsMSACloudSearchEnabled' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry $k 'IsAADCloudSearchEnabled' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry $k 'IsDeviceSearchHistoryEnabled' 0 DWord $M) { $n++ }
            if (Set-EmiRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'DeviceHistoryEnabled' 0 DWord $M) { $n++ }
        }

        'DeliveryOpt' {
            # 1 = solo equipos de la red local (no reparte por Internet)
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 1 DWord $M) { $n++ }
        }

        'Location' {
            $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
            if (Set-EmiRegistry $k 'Value' 'Deny' String $M) { $n++ }
            if (Set-EmiRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1 DWord $M) { $n++ }
            if (Set-EmiService -Name 'lfsvc' -StartupType Disabled -Stop -Module $M) { $n++ }
        }

        'FirewallTel' {
            $procs = @(
                @{ N='EmiToolkit - Bloquear CompatTelRunner'; P="$env:SystemRoot\System32\CompatTelRunner.exe" }
                @{ N='EmiToolkit - Bloquear DeviceCensus';    P="$env:SystemRoot\System32\DeviceCensus.exe" }
                @{ N='EmiToolkit - Bloquear WerFault';        P="$env:SystemRoot\System32\WerFault.exe" }
            )
            foreach ($p in $procs) {
                if (-not (Test-Path -LiteralPath $p.P)) { continue }
                if (Get-NetFirewallRule -DisplayName $p.N -ErrorAction SilentlyContinue) { continue }
                try {
                    New-NetFirewallRule -DisplayName $p.N -Direction Outbound -Action Block -Program $p.P `
                                        -Profile Any -Group 'EmiToolkit' -ErrorAction Stop | Out-Null
                    Add-EmiJournalEntry @{ Kind='Firewall'; RuleName=$p.N; Module=$M }
                    Write-EmiLog "Bloqueado en el firewall: $(Split-Path $p.P -Leaf)" Ok
                    $n++
                } catch { Write-EmiLog "Firewall: $($_.Exception.Message)" Warn }
            }
        }

        'HostsBlock' { $n += Add-EmiHostsBlock }

        # --- Telemetria moderna (Copilot, Recall, AI, Edge, WebView2, winget, DO) ---
        'DisableCopilot' {
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1 -Type DWord -Module 'Privacidad'
            $n += Set-EmiRegistry -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1 -Type DWord -Module 'Privacidad'
        }
        'DisableRecall' {
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'AllowRecallEnablement' -Value 0 -Type DWord -Module 'Privacidad'
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'DisableAIDataAnalysis' -Value 1 -Type DWord -Module 'Privacidad'
        }
        'LimitAIDiagnostics' {
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'LimitDiagnosticLogCollection' -Value 1 -Type DWord -Module 'Privacidad'
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'LimitDumpCollection' -Value 1 -Type DWord -Module 'Privacidad'
        }
        'DisableEdgeShopping' {
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'ShoppingInMicrosoftEdgeEnabled' -Value 0 -Type DWord -Module 'Privacidad'
        }
        'DisableEdgeSidebar' {
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HubsSidebarEnabled' -Value 0 -Type DWord -Module 'Privacidad'
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'Microsoft365CopilotChatIconEnabled' -Value 0 -Type DWord -Module 'Privacidad'
        }
        'LimitWebView2' {
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\EdgeWebView2' -Name 'ExperimentationAndConfigurationServiceControl' -Value 0 -Type DWord -Module 'Privacidad'
        }
        'DisableWingetTelemetry' {
            $n += Set-EmiRegistry -Path 'HKCU:\Software\Microsoft\AppInstaller' -Name 'TelemetryEnabled' -Value 0 -Type DWord -Module 'Privacidad'
        }
        'DisableDOP2PFull' {
            $n += Set-EmiRegistry -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name 'DODownloadMode' -Value 0 -Type DWord -Module 'Privacidad'
        }
    }

    return $n
}

function Add-EmiHostsBlock {
    $hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
    try {
        $content = Get-Content -LiteralPath $hosts -Raw -ErrorAction Stop
        if ($content -like "*$($script:HostsMarker)*") {
            Write-EmiLog 'El bloqueo de dominios ya estaba aplicado.' Warn
            return 0
        }

        $backup = Get-EmiHostsBackupPath   # carpeta de datos protegida (EmiCore)
        Copy-Item -LiteralPath $hosts -Destination $backup -Force
        Add-EmiJournalEntry @{ Kind='File'; Path=$hosts; Backup=$backup; Module='Privacidad' }

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($script:HostsMarker)
        foreach ($h in $script:TelemetryHosts) { [void]$sb.AppendLine("0.0.0.0 $h") }
        [void]$sb.AppendLine('# --- fin EmiToolkit ---')

        Add-Content -LiteralPath $hosts -Value $sb.ToString() -Encoding ASCII -ErrorAction Stop
        & ipconfig.exe /flushdns | Out-Null
        Write-EmiLog "$($script:TelemetryHosts.Count) dominios de telemetria bloqueados en hosts." Ok
        return 1
    }
    catch {
        Write-EmiLog "No se pudo editar el archivo hosts: $($_.Exception.Message)" Warn
        return 0
    }
}

function Invoke-EmiPrivacySet {
    param([string[]] $Ids)

    $all = Get-EmiPrivacyItems
    $t = 0; $i = 0
    foreach ($id in $Ids) {
        $i++
        $x = $all | Where-Object { $_.Id -eq $id }
        $label = if ($x) { $x.Name } else { $id }
        Set-EmiStatus $label ([int](($i / [math]::Max(1, $Ids.Count)) * 100))
        Write-EmiLog $label Step
        $t += Invoke-EmiPrivacyItem -Id $id
    }
    Write-EmiLog "Privacidad: $t ajustes aplicados." Ok
    Set-EmiStatus 'Telemetria desactivada' 100
    return $t
}

function Get-EmiPrivacyStatus {
    <#  Diagnostico rapido para mostrar en la pantalla de inicio. #>
    $tel = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name AllowTelemetry -ErrorAction SilentlyContinue).AllowTelemetry
    $dt  = Get-Service DiagTrack -ErrorAction SilentlyContinue
    $adv = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name Enabled -ErrorAction SilentlyContinue).Enabled

    [pscustomobject]@{
        TelemetryLevel = if ($null -eq $tel) { 'sin directiva' } else { "$tel" }
        DiagTrack      = if ($dt) { $dt.Status.ToString() } else { 'ausente' }
        AdvertisingId  = if ($adv -eq 0) { 'desactivado' } else { 'activo' }
        # En Home y Pro el minimo es 1 (ver 'Telemetry')
        Clean          = (($tel -eq 0 -or ($tel -eq 1 -and -not (Test-EmiEditionApplies -Editions @('Enterprise','Education','Server')))) -and
                          (-not $dt -or $dt.Status -ne 'Running') -and $adv -eq 0)
    }
}

Export-ModuleMember -Function *-Emi*
