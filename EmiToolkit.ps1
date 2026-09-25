<#
    Another's Toolbox - mantenimiento de equipos Windows 11
    Interfaz WPF con la transparencia nativa de Windows (estilo Frutiger Aero).

    Ejecutar:  EmiToolkit.cmd   (pide permisos de administrador)
#>

[CmdletBinding()]
param([switch] $NoElevate)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --------------------------- Error Handler Global ---------------------
function Write-RuntimeError {
    param([string] $Message)
    try {
        $logDir = Join-Path $Root 'Data'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $logPath = Join-Path $logDir 'runtime-error.log'
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $entry = "[$timestamp] $Message`r`n"
        Add-Content -Path $logPath -Value $entry -Encoding UTF8
    } catch { }
}

# --------------------------- Elevacion --------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $NoElevate) {
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden',
            '-File', "`"$($MyInvocation.MyCommand.Path)`""
        )
        exit
    }
    catch {
        [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
        [System.Windows.Forms.MessageBox]::Show(
            'Another''s Toolbox necesita permisos de administrador. Se abrira en modo limitado.',
            'Another''s Toolbox', 'OK', 'Warning') | Out-Null
    }
}

try {
# --------------------------- Ensamblados ------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms

# ---------------------------- Modulos ---------------------------------
$ModuleDir   = Join-Path $Root 'Modules'
$ModuleNames = @('EmiCore', 'EmiDisk', 'EmiTweaks', 'EmiPrivacy', 'EmiPrivRecs', 'EmiVault', 'EmiDebloat', 'EmiApps', 'EmiFirewall', 'EmiStartup', 'EmiProcess', 'EmiVortex', 'EmiSystem')
foreach ($m in $ModuleNames) { Import-Module (Join-Path $ModuleDir "$m.psm1") -Force -DisableNameChecking }

Initialize-EmiCore -RootPath $Root
Initialize-EmiVault
Write-EmiLog ('Another''s Toolbox iniciado en ' + $env:COMPUTERNAME + ' por ' + $env:USERNAME + '.') Ok
if (-not $isAdmin) { Write-EmiLog 'Sin permisos de administrador: muchas acciones estaran limitadas.' Warn }

# ------------------------------ XAML ----------------------------------
$xamlPath = Join-Path $Root 'UI\MainWindow.xaml'
$xamlText = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$win = [Windows.Markup.XamlReader]::Parse($xamlText)

function C { param([string] $Name) $win.FindName($Name) }

# Atajos a los controles
$ui = @{}
foreach ($n in @(
    'TbHeaderHint','BtnClose','BtnMax','BtnMin','SwAdvanced','TbModeHint','TbAdminBadge','TbAdvHeader',
    'NavHome','NavAnyDesk','NavDisk','NavTweaks','NavPrivacy','NavPrivRecs','NavDebloat','NavApps','NavEset','NavStartup','NavProcess','NavVortex','NavSystem','NavLog','NavStore',
    'PageHome','PageAnyDesk','PageDisk','PageTweaks','PagePrivacy','PagePrivRecs','PageDebloat','PageApps','PageEset','PageStartup','PageProcess','PageVortex','PageSystem','PageLog',
    'TbHello','TbOneClickInfo','ChkRestore','ChkEsetInclude','ChkZenInclude','BtnOneClick','IcDisks',
    'TbStatPrivacy','TbStatFast','TbStatEset','TbStatZen','TbStatRam','TbStatPc',
    'TbAnyState','TbAnyId','BtnAnyDownload','BtnAnyFolder','BtnAnyOpen','IcAnySteps',
    'BtnDiskScan','BtnDiskClean','BtnDiskDism','TbDiskTotal','LvClean','TxtScanPath','TxtScanMin',
    'BtnScanFiles','BtnScanFolders','LvBig','BtnOpenFile','BtnDeleteBig',
    'BtnTweakApply','BtnTweakRecommended','BtnRestartExplorer','LvTweaks',
    'BtnPrivApply','BtnPrivRecommended','LvPrivacy',
    'BtnHibpOpen','TbPrivRecZenState','BtnPrivRecZenSet','BtnPrivRecZenDownload',
    'CardUblock','TbPrivRecUblockState','BtnPrivRecUblockInstall','BtnLastPassOpen',
    'BtnVaultUnlock','BtnVaultLock','TbVaultLockedMsg','SpVaultContent',
    'TxtGenPassword','BtnGenPassword','BtnGenCopy','ChkGenSpecial','TbGenLength',
    'TxtVaultAppName','TxtVaultEmail','TxtVaultPassword','BtnVaultGenForEntry','BtnVaultAdd',
    'LvVault','TbVaultCount','BtnVaultCopyPw','BtnVaultCopyEmail','BtnVaultDelete',
    'BtnDebloatApply','BtnDebloatRecommended','LvDebloat',
    'BtnAppsScan','BtnAppsUninstall','BtnAppsClearCache','LvApps',
    'BtnStoreOpenWeb','BtnStoreUninstall','BtnStoreSelectAll',
    'ChkStoreAudio','ChkStoreDraw','ChkStoreFinance','ChkStoreHub','ChkStoreMedia',
    'ChkStorePhoto','ChkStorePixel','ChkStorePresent','ChkStoreReader','ChkStoreVault','ChkStoreWriter',
    'BtnEsetApply','BtnEsetTest','BtnEsetRemove','ChkEsetDns','LvEset',
    'BtnStartupScan','BtnStartupDisable','BtnStartupEnable','LvStartup',
    'BtnProcScan','BtnProcKill','BtnProcBlock','TbRam','LvProcess',
    'BtnVortexScan','BtnVortexRemove','BtnVortexFullClean','BtnVortexSkyrimClean','LvVortex',
    'TbZenState','BtnZenSet','BtnZenSettings','TbFastState','ChkHiber','BtnFastDisable','BtnFastEnable','TbSysInfo',
    'BtnUndoAll','BtnOpenLog','TbUndoCount','IcLog','SvLog',
    'TbStatus','PbMain','EllBusy','SwContrast','BgSky','BgGloss','BgBubbles'
)) { $ui[$n] = C $n }

# Pincel original del fondo, para restaurarlo al desactivar contraste alto
$script:SkyBrush = $ui.BgSky.Fill

# ------------------------- Estado de la interfaz ----------------------
$script:LogView   = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$script:LogIndex  = 0
$script:Advanced  = $false
$script:Worker    = $null
$script:WorkHandle = $null
$script:OnDone    = $null
$ui.IcLog.ItemsSource = $script:LogView

$busyGreen = [Windows.Media.BrushConverter]::new().ConvertFrom('#FF4CA22B')
$busyAmber = [Windows.Media.BrushConverter]::new().ConvertFrom('#FFE08C1E')

# ======================================================================
#                      MOTOR DE TAREAS EN SEGUNDO PLANO
# ======================================================================

$script:Preamble = @"
`$ErrorActionPreference = 'Continue'
foreach (`$m in @('$($ModuleNames -join "','")')) {
    Import-Module (Join-Path '$ModuleDir' "`$m.psm1") -Force -DisableNameChecking
}
Initialize-EmiCore -RootPath '$Root'
"@

function Set-EmiBusy {
    param([bool] $Busy, [string] $Text = 'Listo')
    $ui.TbStatus.Text  = $Text
    $ui.EllBusy.Fill   = if ($Busy) { $busyAmber } else { $busyGreen }
    foreach ($b in @('BtnOneClick','BtnDiskScan','BtnDiskClean','BtnDiskDism','BtnScanFiles','BtnScanFolders',
                     'BtnTweakApply','BtnPrivApply','BtnDebloatApply','BtnAppsUninstall','BtnAppsClearCache','BtnEsetApply','BtnEsetTest','BtnEsetRemove',
                     'BtnStoreOpenWeb','BtnStoreUninstall','BtnStoreSelectAll',
                     'BtnStartupScan','BtnStartupDisable','BtnProcScan','BtnProcKill','BtnProcBlock',
                     'BtnZenSet','BtnFastDisable','BtnUndoAll','BtnDeleteBig',
                     'BtnVortexScan','BtnVortexRemove','BtnVortexFullClean','BtnVortexSkyrimClean',
                     'BtnVaultUnlock','BtnVaultLock','BtnVaultAdd','BtnGenPassword','BtnVaultDelete')) {
        if ($ui[$b]) { $ui[$b].IsEnabled = -not $Busy }
    }
    if (-not $Busy) { $ui.PbMain.Value = 0 }
}

function Start-EmiWork {
    <#  Ejecuta un bloque en un runspace aparte para no congelar la interfaz. #>
    param(
        [Parameter(Mandatory)][scriptblock] $Work,
        [hashtable] $Parameters = @{},
        [scriptblock] $OnDone,
        [string] $Label = 'Trabajando...'
    )

    if ($script:Worker) { Write-EmiLog 'Ya hay una tarea en curso.' Warn; return }

    Set-EmiBusy $true $Label
    $global:EmiSync.Progress = 0
    $global:EmiSync.Status   = $Label
    $global:EmiSync.Result   = $null

    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions  = 'ReuseThread'
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('EmiSync', $global:EmiSync)
        $rs.SessionStateProxy.SetVariable('P', $Parameters)

        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($script:Preamble + "`n" + $Work.ToString())

        $script:Worker     = $ps
        $script:WorkHandle = $ps.BeginInvoke()
        $script:OnDone     = $OnDone
    } catch {
        # Si el arranque del runspace falla, restaurar la UI o quedaria "ocupada" para siempre
        Write-EmiLog ('No se pudo iniciar la tarea: ' + $_.Exception.Message) Error
        $script:Worker = $null; $script:WorkHandle = $null; $script:OnDone = $null
        try { if ($rs) { $rs.Dispose() } } catch { }
        try { if ($ps) { $ps.Dispose() } } catch { }
        Set-EmiBusy $false 'Listo'
    }
}

# Temporizador que refresca la interfaz y recoge el resultado
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(180)
$timer.Add_Tick({
    # Volcar el log
    try {
        $total = $global:EmiSync.Log.Count
        while ($script:LogIndex -lt $total) {
            $script:LogView.Add($global:EmiSync.Log[$script:LogIndex])
            $script:LogIndex++
            if ($script:LogView.Count -gt 600) { $script:LogView.RemoveAt(0) }
        }
        if ($total -gt 0) { $ui.SvLog.ScrollToEnd() }
    } catch { }

    # Estado y progreso
    if ($script:Worker) {
        $ui.TbStatus.Text = [string]$global:EmiSync.Status
        $ui.PbMain.Value  = [double]$global:EmiSync.Progress

        if ($script:WorkHandle.IsCompleted) {
            try {
                $result = $null
                try { $result = $script:Worker.EndInvoke($script:WorkHandle) } catch { Write-EmiLog ('Error en la tarea: ' + $_.Exception.Message) Error }
                $errs = $script:Worker.Streams.Error
                if ($errs -and $errs.Count -gt 0) { foreach ($e in $errs) { Write-EmiLog ([string]$e) Warn } }
            } finally {
                try { $script:Worker.Runspace.Close(); $script:Worker.Dispose() } catch { }
                $script:Worker = $null; $script:WorkHandle = $null
                Set-EmiBusy $false 'Listo'
            }
            if ($script:OnDone) {
                $cb = $script:OnDone; $script:OnDone = $null
                try { & $cb $result } catch { Write-EmiLog ('Error al refrescar: ' + $_.Exception.Message) Warn }
            }
        }
    }
})
$timer.Start()

# ======================================================================
#                              NAVEGACION
# ======================================================================

$pages = @{
    Home    = $ui.PageHome;    AnyDesk = $ui.PageAnyDesk; Disk    = $ui.PageDisk
    Tweaks  = $ui.PageTweaks;  Privacy = $ui.PagePrivacy; PrivRecs = $ui.PagePrivRecs; Debloat = $ui.PageDebloat; Apps = $ui.PageApps; Eset    = $ui.PageEset
    Startup = $ui.PageStartup; Process = $ui.PageProcess; Vortex  = $ui.PageVortex
    System  = $ui.PageSystem;  Log     = $ui.PageLog
}

function Show-EmiPage {
    param([string] $Name)
    foreach ($k in $pages.Keys) {
        $pages[$k].Visibility = if ($k -eq $Name) { 'Visible' } else { 'Collapsed' }
    }
}

foreach ($nav in @('NavHome','NavAnyDesk','NavDisk','NavTweaks','NavPrivacy','NavPrivRecs','NavDebloat','NavApps','NavEset','NavStartup','NavProcess','NavVortex','NavSystem','NavLog','NavStore')) {
    $ui[$nav].Add_Checked({ Show-EmiPage $this.Tag }.GetNewClosure())
}

$advNav = @('NavDisk','NavTweaks','NavPrivacy','NavPrivRecs','NavDebloat','NavApps','NavEset','NavStartup','NavProcess','NavVortex','NavSystem','NavLog','NavStore')

$ui.SwAdvanced.Add_Click({
    $script:Advanced = [bool]$ui.SwAdvanced.IsChecked
    $vis = if ($script:Advanced) { 'Visible' } else { 'Collapsed' }
    foreach ($n in $advNav) { $ui[$n].Visibility = $vis }
    $ui.TbAdvHeader.Visibility = $vis

    if ($script:Advanced) {
        $ui.TbModeHint.Text = 'Modo avanzado: cada apartado por separado.'
        Initialize-EmiAdvancedPages
    } else {
        $ui.TbModeHint.Text = 'Modo basico: un clic y listo.'
        $ui.NavHome.IsChecked = $true
        Show-EmiPage 'Home'
    }
})

$ui.SwContrast.Add_Click({
    $on = [bool]$ui.SwContrast.IsChecked
    $vis = if ($on) { 'Collapsed' } else { 'Visible' }
    # Ocultar capas decorativas translucidas y forzar fondo solido claro
    $win.Background = if ($on) { [Windows.Media.Brushes]::White } else { [Windows.Media.Brushes]::Transparent }
    $ui.BgGloss.Visibility   = $vis
    $ui.BgBubbles.Visibility  = $vis
    if ($on) { $ui.BgSky.Fill = [Windows.Media.Brushes]::White } else { $ui.BgSky.Fill = $script:SkyBrush }
})

$script:AdvLoaded = $false
function Initialize-EmiAdvancedPages {
    if ($script:AdvLoaded) { return }
    $script:AdvLoaded = $true

    # Optimizaciones
    try {
        $tw = New-Object System.Collections.ArrayList
        foreach ($t in Get-EmiTweaks) {
            $i = New-Object EmiItem
            $i.Name = $t.Name; $i.Detail = $t.Info; $i.Tag = $t.Id
            $i.Recommended = $t.Recommended; $i.Selected = $t.Recommended
            $i.SizeText = if ($t.Recommended) { 'recomendado' } else { 'opcional' }
            [void]$tw.Add($i)
        }
        $ui.LvTweaks.ItemsSource = $tw
    } catch { Write-EmiLog "Error cargando Tweaks: $($_.Exception.Message)" Warn }

    # Privacidad
    try {
        $pv = New-Object System.Collections.ArrayList
        foreach ($t in Get-EmiPrivacyItems) {
            $i = New-Object EmiItem
            $i.Name = $t.Name; $i.Detail = $t.Info; $i.Tag = $t.Id
            $i.Recommended = $t.Recommended; $i.Selected = $t.Recommended
            $i.SizeText = if ($t.Recommended) { 'recomendado' } else { 'opcional' }
            [void]$pv.Add($i)
        }
        $ui.LvPrivacy.ItemsSource = $pv
    } catch { Write-EmiLog "Error cargando Privacidad: $($_.Exception.Message)" Warn }

    # Debloat
    try {
        $db = New-Object System.Collections.ArrayList
        foreach ($t in Get-EmiDebloatItems) {
            $i = New-Object EmiItem
            $i.Name = $t.Name; $i.Detail = $t.Info; $i.Tag = $t.Id
            $i.Recommended = $t.Recommended; $i.Selected = $t.Recommended
            $i.Category = $t.Category
            $i.SizeText = if ($t.Recommended) { 'recomendado' } else { 'opcional' }
            [void]$db.Add($i)
        }
        $ui.LvDebloat.ItemsSource = $db
    } catch { Write-EmiLog "Error cargando Debloat: $($_.Exception.Message)" Warn }

    # ESET
    try { $ui.LvEset.ItemsSource = Get-EmiEsetItems } catch { Write-EmiLog "Error cargando ESET: $($_.Exception.Message)" Warn }

    # Rutas por defecto del buscador
    $ui.TxtScanPath.Text = $env:USERPROFILE

    Update-EmiSystemPage
    Update-EmiPrivRecsPage
    Update-EmiVaultUI
}

function Update-EmiHome {
    $ui.IcDisks.ItemsSource = @(Get-EmiDisks)

    $p = Get-EmiPrivacyStatus
    $ui.TbStatPrivacy.Text = if ($p.Clean) { 'Desactivada correctamente' }
                             else { 'Nivel: ' + $p.TelemetryLevel + ' / DiagTrack: ' + $p.DiagTrack }

    $f = Get-EmiFastStartup
    $ui.TbStatFast.Text = $f.StatusText

    $n = Get-EmiEsetRuleCount
    $ui.TbStatEset.Text = if ($n -gt 0) { $n + ' reglas KB332 activas' } else { 'Sin reglas aplicadas' }

    $z = Get-EmiZenInfo
    $ui.TbStatZen.Text = if (-not $z.Installed) { 'Zen no instalado (no se toca)' }
                         elseif ($z.IsDefault)  { 'Zen es el predeterminado' }
                         else { 'Predeterminado actual: ' + $z.CurrentDefault }

    $m = Get-EmiMemoryStatus
    $ui.TbStatRam.Text = $m.UsedText + ' de ' + $m.TotalText + ' en uso (' + $m.Percent + '%)'

    $s = Get-EmiSystemSummary
    $ui.TbStatPc.Text  = $s.Computer + ' - ' + $s.OS
    $ui.TbHello.Text   = 'Poner a punto ' + $s.Computer
    $ui.TbUndoCount.Text = @(Get-EmiJournal).Count.ToString() + ' cambios registrados'

    $ui.TbAdminBadge.Text = if (Test-EmiAdmin) { 'Ejecutando como administrador.' }
                            else { 'SIN administrador: cierra y usa AnotherToolbox.cmd.' }
}

function Update-EmiSystemPage {
    $z = Get-EmiZenInfo
    $ui.TbZenState.Text = if (-not $z.Installed) { 'Zen Browser no esta instalado en este equipo.' }
                          elseif ($z.IsDefault)  { 'Zen ya es el navegador predeterminado (' + $z.Path + ').' }
                          else { 'Zen instalado en ' + $z.Path + '. Predeterminado actual: ' + $z.CurrentDefault + '.' }
    $ui.BtnZenSet.IsEnabled = $z.Installed

    $f = Get-EmiFastStartup
    $ui.TbFastState.Text = 'Estado actual: ' + $f.StatusText

    $s = Get-EmiSystemSummary
    $ui.TbSysInfo.Text = $s.Computer + ' / ' + $s.User + "`n" + $s.OS + "`n" + $s.Cpu + "`n" + 'RAM: ' + $s.Ram + '   Encendido hace: ' + $s.Uptime
}

function Update-EmiAnyDesk {
    $a = Get-EmiAnyDeskInfo
    if ($a.Installed) {
        $ui.TbAnyState.Text = 'AnyDesk ya esta instalado en este equipo.'
        $ui.TbAnyId.Text    = if ($a.Id) { 'Tu direccion de AnyDesk: ' + $a.Id } else { 'Abre AnyDesk para ver tu direccion de 9 cifras.' }
        $ui.BtnAnyOpen.IsEnabled = $true
    } else {
        $ui.TbAnyState.Text = 'AnyDesk todavia no esta instalado.'
        $ui.TbAnyId.Text    = if ($a.Downloaded) { 'Ya tienes AnyDesk.exe en Descargas: abrelo para instalarlo.' }
                              else { 'Empieza por el paso 1 para descargarlo.' }
        $ui.BtnAnyOpen.IsEnabled = $false
    }
    $ui.IcAnySteps.ItemsSource = @(Get-EmiAnyDeskSteps)
}

function Get-EmiChecked {
    param($ListView)
    $sel = New-Object System.Collections.ArrayList
    if ($ListView.ItemsSource) {
        foreach ($i in $ListView.ItemsSource) { if ($i.Selected) { [void]$sel.Add($i) } }
    }
    return $sel
}

# ======================================================================
#                            BOTON UNICO
# ======================================================================

$ui.BtnOneClick.Add_Click({
    $p = @{
        Restore = [bool]$ui.ChkRestore.IsChecked
        Eset    = [bool]$ui.ChkEsetInclude.IsChecked
        Zen     = [bool]$ui.ChkZenInclude.IsChecked
    }

    Start-EmiWork -Label 'Mantenimiento completo...' -Parameters $p -Work {

        $freed = 0
        if ($P.Restore) { [void](New-EmiRestorePoint) }

        Write-EmiLog '=== 1/7  Limpieza de disco ===' Step
        $safe = (Get-EmiCleanupTargets | Where-Object { $_.Safe }).Id
        $freed = Invoke-EmiCleanup -Ids $safe

        Write-EmiLog '=== 2/7  Optimizacion de Windows 11 ===' Step
        $ids = (Get-EmiTweaks | Where-Object { $_.Recommended }).Id
        [void](Invoke-EmiTweakSet -Ids $ids)

        Write-EmiLog '=== 3/7  Telemetria ===' Step
        $pid2 = (Get-EmiPrivacyItems | Where-Object { $_.Recommended }).Id
        [void](Invoke-EmiPrivacySet -Ids $pid2)

        Write-EmiLog '=== 4/7  Programas de arranque ===' Step
        [void](Invoke-EmiStartupCleanup)

        Write-EmiLog '=== 5/7  Inicio rapido ===' Step
        [void](Disable-EmiFastStartup)

        if ($P.Eset) {
            Write-EmiLog '=== 6/7  Firewall de ESET (KB332) ===' Step
            [void](Invoke-EmiEsetFirewall -ResolveHostnames)
        } else { Write-EmiLog '=== 6/7  Firewall de ESET omitido ===' Warn }

        if ($P.Zen) {
            Write-EmiLog '=== 7/7  Navegador predeterminado ===' Step
            [void](Set-EmiZenDefault)
        } else { Write-EmiLog '=== 7/7  Navegador omitido ===' Warn }

        Write-EmiLog "MANTENIMIENTO TERMINADO. Espacio liberado: $(Format-EmiSize $freed)" Ok
        Set-EmiStatus 'Mantenimiento terminado' 100
        return $freed

    } -OnDone {
        param($r)
        Update-EmiHome
        $freed = 0; if ($r) { $freed = @($r)[-1] }
        $doneMsg = 'Mantenimiento terminado.' + "`n`n" + 'Espacio liberado: ' + (Format-EmiSize $freed) + "`n`n" + 'Conviene reiniciar el equipo para que todo se aplique.'
        [System.Windows.MessageBox]::Show($doneMsg, 'Another''s Toolbox', 'OK', 'Information') | Out-Null
    }
})

# ======================================================================
#                               DISCO
# ======================================================================

$ui.BtnDiskScan.Add_Click({
    Start-EmiWork -Label 'Analizando basura...' -Work {
        return ,(Measure-EmiCleanupTargets)
    } -OnDone {
        param($r)
        $items = @($r)[-1]
        $ui.LvClean.ItemsSource = $items
        $tot = 0; foreach ($i in $items) { if ($i.Selected) { $tot += $i.Size } }
        $ui.TbDiskTotal.Text = "Seleccionado: $(Format-EmiSize $tot)"
    }
})

$ui.BtnDiskClean.Add_Click({
    $sel = Get-EmiChecked $ui.LvClean
    if ($sel.Count -eq 0) { [System.Windows.MessageBox]::Show('Analiza primero y marca que limpiar.','Another''s Toolbox','OK','Information') | Out-Null; return }

    $risky = @($sel | Where-Object { $_.Category -eq 'Revisar' })
    if ($risky.Count -gt 0) {
        $n = ($risky | ForEach-Object { $_.Name }) -join "`n - "
        $riskyMsg = 'Has marcado ubicaciones que pueden contener archivos tuyos:' + "`n`n" + ' - ' + $n + "`n`n" + 'Continuar?'
        $ans = [System.Windows.MessageBox]::Show($riskyMsg, 'Confirmar limpieza', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }
    }

    $ids = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Limpiando...' -Parameters @{ Ids = $ids } -Work {
        return (Invoke-EmiCleanup -Ids $P.Ids)
    } -OnDone {
        param($r)
        $freed = 0; if ($r) { $freed = @($r)[-1] }
        $ui.TbDiskTotal.Text = "Liberado: $(Format-EmiSize $freed)"
        Update-EmiHome
        $ui.BtnDiskScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
})

$ui.BtnDiskDism.Add_Click({
    Start-EmiWork -Label 'DISM: limpiando componentes...' -Work { return (Invoke-EmiComponentCleanup) } -OnDone { Update-EmiHome }
})

$ui.BtnScanFiles.Add_Click({
    $path = $ui.TxtScanPath.Text
    if (-not (Test-Path -LiteralPath $path)) { [System.Windows.MessageBox]::Show('Esa carpeta no existe.','Another''s Toolbox','OK','Warning') | Out-Null; return }
    $min = 100; [void][int]::TryParse($ui.TxtScanMin.Text, [ref]$min)

    Start-EmiWork -Label "Buscando archivos grandes..." -Parameters @{ Path = $path; Min = $min } -Work {
        return ,(Find-EmiLargeFiles -Path $P.Path -MinMB $P.Min -Top 300)
    } -OnDone { param($r) $ui.LvBig.ItemsSource = @($r)[-1] }
})

$ui.BtnScanFolders.Add_Click({
    $path = $ui.TxtScanPath.Text
    if (-not (Test-Path -LiteralPath $path)) { [System.Windows.MessageBox]::Show('Esa carpeta no existe.','Another''s Toolbox','OK','Warning') | Out-Null; return }
    Start-EmiWork -Label 'Midiendo carpetas...' -Parameters @{ Path = $path } -Work {
        return ,(Find-EmiLargeFolders -Path $P.Path)
    } -OnDone { param($r) $ui.LvBig.ItemsSource = @($r)[-1] }
})

$ui.BtnOpenFile.Add_Click({
    $it = $ui.LvBig.SelectedItem
    if (-not $it) { return }
    if (Test-Path -LiteralPath $it.Path -PathType Leaf) { Start-Process explorer.exe "/select,`"$($it.Path)`"" }
    else { Start-Process explorer.exe "`"$($it.Path)`"" }
})

$ui.BtnDeleteBig.Add_Click({
    $sel = Get-EmiChecked $ui.LvBig
    if ($sel.Count -eq 0) { return }
    $tot = ($sel | Measure-Object Size -Sum).Sum
    $recMsg = 'Se enviaran ' + $sel.Count + ' elementos a la papelera (' + (Format-EmiSize $tot) + ').' + "`n" + 'Podras recuperarlos desde la papelera.' + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($recMsg, 'Confirmar', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }

    $paths = @($sel | ForEach-Object { $_.Path })
    Start-EmiWork -Label 'Enviando a la papelera...' -Parameters @{ Paths = $paths } -Work {
        return (Remove-EmiFilesToRecycleBin -Paths $P.Paths)
    } -OnDone { Update-EmiHome }
})

# ======================================================================
#                            OPTIMIZAR
# ======================================================================

$ui.BtnTweakRecommended.Add_Click({
    foreach ($i in $ui.LvTweaks.ItemsSource) { $i.Selected = $i.Recommended }
})

$ui.BtnTweakApply.Add_Click({
    $ids = @((Get-EmiChecked $ui.LvTweaks) | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { return }
    Start-EmiWork -Label 'Optimizando Windows...' -Parameters @{ Ids = $ids } -Work {
        return (Invoke-EmiTweakSet -Ids $P.Ids)
    } -OnDone {
        Update-EmiHome
        [System.Windows.MessageBox]::Show('Optimizacion aplicada. Algunos cambios necesitan reiniciar el Explorador o el equipo.',
            'Another''s Toolbox','OK','Information') | Out-Null
    }
})

$ui.BtnRestartExplorer.Add_Click({ [void](Restart-EmiExplorer) })

# ======================================================================
#                            PRIVACIDAD
# ======================================================================

$ui.BtnPrivRecommended.Add_Click({
    foreach ($i in $ui.LvPrivacy.ItemsSource) { $i.Selected = $i.Recommended }
})

$ui.BtnPrivApply.Add_Click({
    $ids = @((Get-EmiChecked $ui.LvPrivacy) | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { return }
    Start-EmiWork -Label 'Desactivando telemetria...' -Parameters @{ Ids = $ids } -Work {
        return (Invoke-EmiPrivacySet -Ids $P.Ids)
    } -OnDone { Update-EmiHome }
})

# ======================================================================
#                   RECOMENDACIONES DE PRIVACIDAD
# ======================================================================

function Update-EmiPrivRecsPage {
    $z = Get-EmiZenBrowserStatus
    if (-not $z.Installed) {
        $ui.TbPrivRecZenState.Text = 'Zen Browser no esta instalado.'
        $ui.BtnPrivRecZenSet.Visibility = 'Collapsed'
        $ui.BtnPrivRecZenDownload.Visibility = 'Visible'
        $ui.CardUblock.Visibility = 'Collapsed'
    } elseif ($z.IsDefault) {
        $ui.TbPrivRecZenState.Text = "Zen ya es el navegador predeterminado ($($z.Path))."
        $ui.BtnPrivRecZenSet.Visibility = 'Collapsed'
        $ui.BtnPrivRecZenDownload.Visibility = 'Collapsed'
        $ui.CardUblock.Visibility = 'Visible'
        $ui.TbPrivRecUblockState.Text = if ($z.UblockInstalled) { 'uBlock Origin ya esta instalado.' } else { 'uBlock Origin NO esta instalado. Recomendado.' }
        $ui.BtnPrivRecUblockInstall.IsEnabled = -not $z.UblockInstalled
        $ui.BtnPrivRecUblockInstall.Content   = if ($z.UblockInstalled) { 'Ya instalado' } else { 'Instalar uBlock Origin' }
    } else {
        $ui.TbPrivRecZenState.Text = "Zen instalado en $($z.Path). Predeterminado actual: $($z.CurrentDefault)."
        $ui.BtnPrivRecZenSet.Visibility = 'Visible'
        $ui.BtnPrivRecZenDownload.Visibility = 'Collapsed'
        $ui.CardUblock.Visibility = 'Visible'
        $ui.TbPrivRecUblockState.Text = if ($z.UblockInstalled) { 'uBlock Origin ya esta instalado.' } else { 'uBlock Origin NO esta instalado.' }
        $ui.BtnPrivRecUblockInstall.IsEnabled = -not $z.UblockInstalled
    }
}

function Update-EmiVaultUI {
    if (Test-EmiVaultUnlocked) {
        $ui.TbVaultLockedMsg.Visibility = 'Collapsed'
        $ui.SpVaultContent.Visibility   = 'Visible'
        $ui.BtnVaultUnlock.Visibility   = 'Collapsed'
        $ui.BtnVaultLock.Visibility     = 'Visible'
        $displayEntries = Get-EmiVaultEntries
        $ui.LvVault.ItemsSource = $displayEntries
        $ui.TbVaultCount.Text = "$($displayEntries.Count) entradas guardadas"
    } else {
        $ui.TbVaultLockedMsg.Visibility = 'Visible'
        $ui.SpVaultContent.Visibility   = 'Collapsed'
        $ui.BtnVaultUnlock.Visibility   = 'Visible'
        $ui.BtnVaultLock.Visibility     = 'Collapsed'
        $ui.LvVault.ItemsSource = $null
        $ui.TbVaultCount.Text = ''
    }
}

$ui.BtnHibpOpen.Add_Click({ Open-EmiHibpPage })
$ui.BtnLastPassOpen.Add_Click({ Open-EmiLastPassPage })

$ui.BtnPrivRecZenDownload.Add_Click({ Start-Process 'https://zen-browser.app/' })

$ui.BtnPrivRecZenSet.Add_Click({
    Start-EmiWork -Label 'Configurando Zen...' -Work { return (Set-EmiZenDefault) } -OnDone {
        Update-EmiPrivRecsPage; Update-EmiHome
    }
})

$ui.BtnPrivRecUblockInstall.Add_Click({ Open-EmiUblockInstall })

$ui.BtnVaultUnlock.Add_Click({
    $ok = Request-EmiVaultUnlock
    if ($ok) {
        Write-EmiLog 'Almacen de contrasenas desbloqueado.' Ok
        Update-EmiVaultUI
    } else {
        Write-EmiLog 'No se pudo verificar con Windows Hello.' Warn
    }
})

$ui.BtnVaultLock.Add_Click({
    Lock-EmiVault
    Write-EmiLog 'Almacen de contrasenas bloqueado.' Info
    Update-EmiVaultUI
})

$ui.BtnGenPassword.Add_Click({
    $special = [bool]$ui.ChkGenSpecial.IsChecked
    $pw = New-EmiSecurePassword -Length 20 -IncludeSpecial:$special
    $ui.TxtGenPassword.Text = $pw
})

# Copia un secreto al portapapeles y lo limpia a los 30 segundos
function Copy-EmiSecret {
    param([string] $Text, [string] $Label)
    [System.Windows.Clipboard]::SetText($Text)
    $script:ClipTimer.Tag = "$([DateTime]::UtcNow.Ticks):$Text"
    $script:ClipTimer.Stop(); $script:ClipTimer.Start()
    Write-EmiLog "$Label copiado. El portapapeles se limpiara en 30 segundos." Ok
}
# Timer que limpia el portapapeles si sigue conteniendo el secreto copiado
$script:ClipTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ClipTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:ClipTimer.Add_Tick({
    try {
        $snapshot = [string]$script:ClipTimer.Tag
        $secret   = $snapshot.Substring($snapshot.IndexOf(':') + 1)
        if ([System.Windows.Clipboard]::ContainsText() -and [System.Windows.Clipboard]::GetText() -eq $secret) {
            [System.Windows.Clipboard]::Clear()
            Write-EmiLog 'Portapapeles limpiado.' Info
        }
    } catch { }
    $script:ClipTimer.Stop()
})

$ui.BtnGenCopy.Add_Click({
    if ($ui.TxtGenPassword.Text -and $ui.TxtGenPassword.Text -ne 'Pulsa Generar para crear una contrasena') {
        Copy-EmiSecret $ui.TxtGenPassword.Text 'Contrasena'
    }
})

$ui.BtnVaultGenForEntry.Add_Click({
    $special = [bool]$ui.ChkGenSpecial.IsChecked
    $pw = New-EmiSecurePassword -Length 20 -IncludeSpecial:$special
    $ui.TxtVaultPassword.Text = $pw
})

$ui.BtnVaultAdd.Add_Click({
    $app   = $ui.TxtVaultAppName.Text.Trim()
    $email = $ui.TxtVaultEmail.Text.Trim()
    $pw    = $ui.TxtVaultPassword.Text
    if (-not $app -or -not $pw) {
        [System.Windows.MessageBox]::Show('Rellena al menos el nombre del servicio y la contrasena.', 'Another''s Toolbox', 'OK', 'Warning') | Out-Null
        return
    }
    $id = Add-EmiVaultEntry -AppName $app -Email $email -Password $pw -Notes ''
    if ($id) {
        $ui.TxtVaultAppName.Text  = ''
        $ui.TxtVaultEmail.Text    = ''
        $ui.TxtVaultPassword.Text = ''
        Update-EmiVaultUI
        Write-EmiLog ('Entrada ''' + $app + ''' guardada en el almacen.') Ok
    }
})

$ui.BtnVaultCopyPw.Add_Click({
    $sel = $ui.LvVault.SelectedItem
    if (-not $sel) { return }
    $entry = Get-EmiVaultEntryPlain -Id $sel.Id
    if ($entry) {
        Copy-EmiSecret $entry.Password ('Contrasena de ''' + $entry.AppName + '''')
    }
})

$ui.BtnVaultCopyEmail.Add_Click({
    $sel = $ui.LvVault.SelectedItem
    if (-not $sel) { return }
    $entry = Get-EmiVaultEntryPlain -Id $sel.Id
    if ($entry -and $entry.Email) {
        [System.Windows.Clipboard]::SetText($entry.Email)
        Write-EmiLog ('Correo de ''' + $entry.AppName + ''' copiado.') Ok
    }
})

$ui.BtnVaultDelete.Add_Click({
    $sel = $ui.LvVault.SelectedItem
    if (-not $sel) { return }
    $delMsg = 'Eliminar la entrada ''' + $sel.AppName + '''? Esta accion no se puede deshacer.'
    $ans = [System.Windows.MessageBox]::Show($delMsg, 'Confirmar', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Remove-EmiVaultEntry -Id $sel.Id
    Update-EmiVaultUI
    Write-EmiLog ('Entrada ''' + $sel.AppName + ''' eliminada.') Ok
})

# ======================================================================
#                              DEBLOAT
# ======================================================================

$ui.BtnDebloatRecommended.Add_Click({
    foreach ($i in $ui.LvDebloat.ItemsSource) { $i.Selected = $i.Recommended }
})

$ui.BtnDebloatApply.Add_Click({
    $ids = @((Get-EmiChecked $ui.LvDebloat) | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { return }
    Start-EmiWork -Label 'Aplicando debloat...' -Parameters @{ Ids = $ids } -Work {
        return (Invoke-EmiDebloatSet -Ids $P.Ids)
    } -OnDone {
        # Refrescar catalogo para reflejar apps removidas / features toggled
        $db = New-Object System.Collections.ArrayList
        foreach ($t in Get-EmiDebloatItems) {
            $i = New-Object EmiItem
            $i.Name = $t.Name; $i.Detail = $t.Info; $i.Tag = $t.Id
            $i.Recommended = $t.Recommended; $i.Selected = $false
            $i.Category = $t.Category
            $i.SizeText = if ($t.Recommended) { 'recomendado' } else { 'opcional' }
            [void]$db.Add($i)
        }
        $ui.LvDebloat.ItemsSource = $db
        Update-EmiHome
    }
})

# ======================================================================
#                          APLICACIONES
# ======================================================================

$ui.BtnAppsScan.Add_Click({
    Start-EmiWork -Label 'Analizando apps instaladas...' -Work {
        return ,(Get-EmiInstalledApps)
    } -OnDone {
        param($r)
        $items = @($r)[-1]
        $list = New-Object System.Collections.ArrayList
        foreach ($a in $items) {
            $i = New-Object EmiItem
            $i.Name = $a.Name; $i.Detail = $a.Detail; $i.Tag = $a.Id
            $i.Status = $a.Version
            $i.Size = $a.CacheSize
            $i.SizeText = if ($a.CacheSize -gt 0) { Format-EmiSize $a.CacheSize } else { '' }
            [void]$list.Add($i)
        }
        $ui.LvApps.ItemsSource = $list
        Write-EmiLog ($list.Count.ToString() + ' apps instaladas encontradas.') Ok
    }
})

$ui.BtnAppsUninstall.Add_Click({
    $sel = @(Get-EmiChecked $ui.LvApps)
    if ($sel.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Analiza primero y marca que apps desinstalar.','Another''s Toolbox','OK','Information') | Out-Null
        return
    }
    $names = ($sel | ForEach-Object { $_.Name }) -join "`n - "
    $uninstAppsMsg = 'Se desinstalaran ' + $sel.Count + ' apps del usuario actual:' + "`n`n" + ' - ' + $names + "`n`n" + 'La app puede volver a instalarse desde Microsoft Store o con el comando registrado en Deshacer. Continuar?'
    $ans = [System.Windows.MessageBox]::Show($uninstAppsMsg, 'Confirmar desinstalacion', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }

    $ids = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Desinstalando apps...' -Parameters @{ Ids = $ids } -Work {
        $n = 0
        foreach ($id in $P.Ids) { if (Remove-EmiInstalledApp -PackageFullName $id) { $n++ } }
        Write-EmiLog "$n apps desinstaladas." Ok
        return $n
    } -OnDone {
        $ui.BtnAppsScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        Update-EmiHome
    }
})

$ui.BtnAppsClearCache.Add_Click({
    $sel = @(Get-EmiChecked $ui.LvApps)
    if ($sel.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Marca las apps cuya cache quieres limpiar.','Another''s Toolbox','OK','Information') | Out-Null
        return
    }
    $cacheMsg = 'Se borrara la cache (LocalCache, Temp e INetCache) de ' + $sel.Count + ' apps. La app se regenerara sola al abrirse. Continuar?'
    $ans = [System.Windows.MessageBox]::Show($cacheMsg, 'Limpiar cache', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }

    # El Tag guarda el PackageFullName; el modulo resuelve la familia desde ahi
    $ids = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Limpiando cache...' -Parameters @{ Ids = $ids } -Work {
        $freed = 0
        foreach ($id in $P.Ids) { $freed += (Clear-EmiAppCacheByFullName -PackageFullName $id) }
        Write-EmiLog "Cache limpiada: $(Format-EmiSize $freed) liberados en total." Ok
        return $freed
    } -OnDone {
        $ui.BtnAppsScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        Update-EmiHome
    }
})

# ======================================================================
#                          ANOTHER STORE
# ======================================================================

$ui.BtnStoreOpenWeb.Add_Click({
    Start-Process 'https://anotherstore.neocities.org/'
    Write-EmiLog 'Another Store: navegador abierto.' Ok
})

$ui.BtnStoreSelectAll.Add_Click({
    $checks = @(
        $ui.ChkStoreAudio, $ui.ChkStoreDraw, $ui.ChkStoreFinance, $ui.ChkStoreHub,
        $ui.ChkStoreMedia, $ui.ChkStorePhoto, $ui.ChkStorePixel, $ui.ChkStorePresent,
        $ui.ChkStoreReader, $ui.ChkStoreVault, $ui.ChkStoreWriter
    )
    foreach ($c in $checks) { $c.IsChecked = $true }
})

$ui.BtnStoreUninstall.Add_Click({
    $map = @{
        ChkStoreAudio   = 'Another Suite Audio'
        ChkStoreDraw    = 'Another Suite Draw'
        ChkStoreFinance = 'Another Suite Finance'
        ChkStoreHub     = 'Another Suite Hub'
        ChkStoreMedia   = 'Another Suite Media'
        ChkStorePhoto   = 'Another Suite Photo'
        ChkStorePixel   = 'Another Suite Pixel'
        ChkStorePresent = 'Another Suite Present'
        ChkStoreReader  = 'Another Suite Reader'
        ChkStoreVault   = 'Another Suite Vault'
        ChkStoreWriter  = 'Another Suite Writer'
    }
    $selected = @()
    foreach ($key in $map.Keys) {
        if ($ui.$key.IsChecked) { $selected += $map[$key] }
    }
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            'Marca al menos una app de Another Suite para desinstalar.',
            'Another''s Toolbox', 'OK', 'Information') | Out-Null
        return
    }
    $list = ($selected -join "`n - ")
    $uninstMsg = 'Se buscaran y desinstalaran ' + $selected.Count + ' apps de Another Suite:' + "`n`n" + ' - ' + $list + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($uninstMsg, 'Confirmar desinstalacion', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }

    Start-EmiWork -Label 'Desinstalando apps de Another Store...' -Parameters @{ Names = $selected } -Work {
        $ok = 0; $fail = 0
        foreach ($name in $P.Names) {
            $found = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                       'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                       'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                     Where-Object { $_.DisplayName -like "*$name*" } | Select-Object -First 1
            if ($found -and $found.UninstallString) {
                try {
                    $cmd = $found.UninstallString
                    if ($cmd -match '^".*"$') { $cmd = $cmd.Trim('"') }
                    Start-Process -FilePath $cmd -ArgumentList '/S','/silent','/quiet' -Wait -ErrorAction Stop
                    $ok++
                    Write-EmiLog ('Another Store: ' + $name + ' desinstalado.') Ok
                } catch {
                    $fail++
                    Write-EmiLog ('Another Store: fallo al desinstalar ' + $name + ' — ' + $_.Exception.Message) Error
                }
            } else {
                $fail++
                Write-EmiLog ('Another Store: ' + $name + ' no encontrado en el registro.') Warning
            }
        }
        return @{ Ok = $ok; Fail = $fail }
    } -OnDone {
        $r = $args[0]
        if ($r.Ok -gt 0) {
            $storeResultMsg = $r.Ok + ' app(s) desinstalada(s). ' + $r.Fail + ' no encontrada(s) o con error.'
            [System.Windows.MessageBox]::Show($storeResultMsg, 'Another''s Toolbox', 'OK', 'Information') | Out-Null
        } else {
            [System.Windows.MessageBox]::Show(
                'No se pudo desinstalar ninguna app. Puede que no esten instaladas.',
                'Another''s Toolbox', 'OK', 'Warning') | Out-Null
        }
    }
})

# ======================================================================
#                               ESET
# ======================================================================

$ui.BtnEsetApply.Add_Click({
    $g = @((Get-EmiChecked $ui.LvEset) | ForEach-Object { $_.Tag })
    if ($g.Count -eq 0) { return }
    $dns = [bool]$ui.ChkEsetDns.IsChecked

    Start-EmiWork -Label 'Aplicando reglas de ESET...' -Parameters @{ G = $g; Dns = $dns } -Work {
        if ($P.Dns) { return (Invoke-EmiEsetFirewall -Groups $P.G -ResolveHostnames) }
        return (Invoke-EmiEsetFirewall -Groups $P.G)
    } -OnDone { Update-EmiHome }
})

$ui.BtnEsetTest.Add_Click({
    Start-EmiWork -Label 'Probando conexion con ESET...' -Work {
        return ,(Test-EmiEsetConnectivity)
    } -OnDone {
        param($r)
        $items = @($r)[-1]
        $bad = @($items | Where-Object { $_.Category -eq 'fail' })
        $msg = if ($bad.Count -eq 0) { 'Todos los servidores de ESET responden correctamente.' }
               else { 'No responden ' + $bad.Count + ' de ' + $items.Count + ':' + "`n`n" + ' - ' + (($bad | ForEach-Object { $_.Name + ' ' + $_.Path }) -join "`n - ") }
        [System.Windows.MessageBox]::Show($msg, 'Prueba de conexion', 'OK', 'Information') | Out-Null
    }
})

$ui.BtnEsetRemove.Add_Click({
    $ans = [System.Windows.MessageBox]::Show('Se eliminaran todas las reglas ESET KB332 creadas por esta app. Continuar?',
        'Confirmar', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Start-EmiWork -Label 'Quitando reglas...' -Work { return (Remove-EmiEsetFirewall) } -OnDone { Update-EmiHome }
})

# ======================================================================
#                              ARRANQUE
# ======================================================================

$ui.BtnStartupScan.Add_Click({
    Start-EmiWork -Label 'Analizando el arranque...' -Work {
        return ,(Get-EmiStartupItems)
    } -OnDone { param($r) $ui.LvStartup.ItemsSource = @($r)[-1] }
})

$ui.BtnStartupDisable.Add_Click({
    $sel = @((Get-EmiChecked $ui.LvStartup) | Where-Object { -not $_.Locked })
    if ($sel.Count -eq 0) { return }
    $tags = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Quitando del arranque...' -Parameters @{ Tags = $tags } -Work {
        $n = 0
        foreach ($t in $P.Tags) { if (Disable-EmiStartupItem -Tag $t) { $n++ } }
        Write-EmiLog "$n programas quitados del arranque." Ok
        return $n
    } -OnDone { $ui.BtnStartupScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
})

$ui.BtnStartupEnable.Add_Click({
    $sel = @(Get-EmiChecked $ui.LvStartup)
    if ($sel.Count -eq 0) { return }
    $tags = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Reactivando...' -Parameters @{ Tags = $tags } -Work {
        $n = 0
        foreach ($t in $P.Tags) { if (Enable-EmiStartupItem -Tag $t) { $n++ } }
        Write-EmiLog "$n programas reactivados." Ok
        return $n
    } -OnDone { $ui.BtnStartupScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
})

# ======================================================================
#                              PROCESOS
# ======================================================================

$ui.BtnProcScan.Add_Click({
    Start-EmiWork -Label 'Analizando procesos...' -Work {
        return ,(Get-EmiProcessItems)
    } -OnDone {
        param($r)
        $ui.LvProcess.ItemsSource = @($r)[-1]
        $m = Get-EmiMemoryStatus
        $pct = $m.Percent
        $ui.TbRam.Text = 'RAM: ' + $m.UsedText + ' / ' + $m.TotalText + ' (' + $pct + '%)'
}
})

function Invoke-EmiProcAction {
    param([bool] $Block)
    $sel = @((Get-EmiChecked $ui.LvProcess) | Where-Object { -not $_.Locked })
    if ($sel.Count -eq 0) { return }

    $names = ($sel | ForEach-Object { $_.Name }) -join ', '
    $extra = if ($Block) { "`n`n" + 'Ademas se creara una regla de firewall que les corta Internet (reversible desde Registro y deshacer).' } else { '' }
    $procMsg = 'Se cerraran: ' + $names + $extra + "`n`n" + 'Guarda tu trabajo antes. Continuar?'
    $ans = [System.Windows.MessageBox]::Show($procMsg, 'Confirmar', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }

    $data = @($sel | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.Path } })
    Start-EmiWork -Label 'Cerrando procesos...' -Parameters @{ D = $data; B = $Block } -Work {
        $n = 0
        foreach ($x in $P.D) {
            if (Stop-EmiProcessByName -Name $x.Name) { $n++ }
            if ($P.B -and $x.Path) { [void](Block-EmiProcessNetwork -ExePath $x.Path -Label $x.Name) }
        }
        Write-EmiLog "$n procesos cerrados." Ok
        return $n
    } -OnDone { $ui.BtnProcScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
}

$ui.BtnProcKill.Add_Click({ Invoke-EmiProcAction $false })
$ui.BtnProcBlock.Add_Click({ Invoke-EmiProcAction $true })

# ======================================================================
#                          VORTEX MODS
# ======================================================================

$ui.BtnVortexScan.Add_Click({
    Start-EmiWork -Label 'Analizando Vortex...' -Work {
        return ,(Get-EmiVortexItems)
    } -OnDone { param($r) $ui.LvVortex.ItemsSource = @($r)[-1] }
})

$ui.BtnVortexRemove.Add_Click({
    $sel = @((Get-EmiChecked $ui.LvVortex) | Where-Object { -not $_.Locked })
    if ($sel.Count -eq 0) { return }
    $tags = @($sel | ForEach-Object { $_.Tag })
    $purgeMsg = 'Se purgaran ' + $sel.Count + ' mods de las carpetas de juego y se eliminaran del staging.' + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($purgeMsg, 'Confirmar purga', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Start-EmiWork -Label 'Purgando mods de Vortex...' -Parameters @{ Tags = $tags } -Work {
        return (Remove-EmiVortexMods -Tags $P.Tags)
    } -OnDone { $ui.BtnVortexScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
})

$ui.BtnVortexFullClean.Add_Click({
    $info = Get-EmiVortexInfo
    if (-not $info.Installed) {
        [System.Windows.MessageBox]::Show('Vortex no esta instalado en este equipo.', 'Another''s Toolbox', 'OK', 'Information') | Out-Null
        return
    }
    $vortexMsg = 'ELIMINACION COMPLETA DE VORTEX' + "`n`n" + 'Se purgaran TODOS los mods desplegados, se borrara APPDATA\Vortex (staging, descargas, perfiles, base de datos) y se desinstalara Vortex.' + "`n`n" + 'Esta accion es IRREVERSIBLE.' + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($vortexMsg, 'Confirmar eliminacion total', 'YesNo', 'Error')
    if ($ans -ne 'Yes') { return }
    Start-EmiWork -Label 'Eliminando Vortex completamente...' -Work {
        return (Remove-EmiVortexFull)
    } -OnDone {
        Update-EmiHome
        $ui.BtnVortexScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
})

$ui.BtnVortexSkyrimClean.Add_Click({
    $skyrimMsg = 'FORCE CLEAN SKYRIM' + "`n`n" + 'Esta accion ELIMINARA COMPLETAMENTE:' + "`n`n" + '1. TODOS los mods de Vortex' + "`n" + '2. TODOS los datos de Vortex' + "`n" + '3. Vortex se desinstalara' + "`n" + '4. TODAS las carpetas de Skyrim (Data, Mods, configuraciones)' + "`n" + '5. TODOS los archivos de usuario (Skyrim.ini, SkyrimPrefs.ini)' + "`n" + '6. Manifiestos de despliegue de Vortex' + "`n" + '7. Carpetas en Documentos\My Games\Skyrim' + "`n`n" + 'Esta accion es IRREVERSIBLE y borrara completamente Skyrim.' + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($skyrimMsg, 'Confirmar Force Clean Skyrim', 'YesNo', 'Error')
    if ($ans -ne 'Yes') { return }
    Start-EmiWork -Label 'Ejecutando Force Clean Skyrim...' -Work {
        return (Remove-EmiVortexSkyrimFull)
    } -OnDone {
        Update-EmiHome
        $ui.BtnVortexScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
})

# ======================================================================
#                       NAVEGADOR / ENERGIA
# ======================================================================

$ui.BtnZenSet.Add_Click({
    Start-EmiWork -Label 'Configurando Zen...' -Work { return (Set-EmiZenDefault) } -OnDone {
        param($r)
        $res = @($r)[-1]
        Update-EmiSystemPage; Update-EmiHome
        $msg = switch ($res) {
            'Done'           { 'Zen ya es el navegador predeterminado.' }
            'AlreadyDefault' { 'Zen ya era el navegador predeterminado.' }
            'NotInstalled'   { 'Zen no esta instalado: no se ha cambiado nada.' }
            default          { 'Windows pide confirmarlo a mano. Se abrio Configuracion > Aplicaciones predeterminadas: busca Zen y pulsa "Establecer como predeterminado".' }
        }
        [System.Windows.MessageBox]::Show($msg, 'Zen Browser', 'OK', 'Information') | Out-Null
    }
})

$ui.BtnZenSettings.Add_Click({ [void](Open-EmiDefaultAppsSettings) })

$ui.BtnFastDisable.Add_Click({
    $h = [bool]$ui.ChkHiber.IsChecked
    Start-EmiWork -Label 'Desactivando inicio rapido...' -Parameters @{ H = $h } -Work {
        if ($P.H) { return (Disable-EmiFastStartup -AlsoDisableHibernation) }
        return (Disable-EmiFastStartup)
    } -OnDone { Update-EmiSystemPage; Update-EmiHome }
})

$ui.BtnFastEnable.Add_Click({
    [void](Enable-EmiFastStartup); Update-EmiSystemPage; Update-EmiHome
})

# ======================================================================
#                              ANYDESK
# ======================================================================

$ui.BtnAnyDownload.Add_Click({
    $anyMsg = 'Se abrira anydesk.com en tu navegador para descargar AnyDesk.' + "`n`n" + 'Descarga solo desde esa pagina oficial. Continuar?'
    $ans = [System.Windows.MessageBox]::Show($anyMsg, 'Descargar AnyDesk', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    [void](Open-EmiAnyDeskDownload)
})
$ui.BtnAnyFolder.Add_Click({ [void](Open-EmiDownloadsFolder) })
$ui.BtnAnyOpen.Add_Click({
    if (-not (Start-EmiAnyDesk)) {
        [System.Windows.MessageBox]::Show('AnyDesk todavia no esta instalado. Sigue los pasos 1 a 4.','AnyDesk','OK','Information') | Out-Null
    }
})

# ======================================================================
#                        REGISTRO / DESHACER
# ======================================================================

$ui.BtnUndoAll.Add_Click({
    $c = @(Get-EmiJournal).Count
    if ($c -eq 0) { [System.Windows.MessageBox]::Show('No hay cambios registrados.','Another''s Toolbox','OK','Information') | Out-Null; return }
    $undoMsg = 'Se revertiran ' + $c + ' cambios (registro, servicios, tareas y reglas de firewall). Continuar?'
    $ans = [System.Windows.MessageBox]::Show($undoMsg, 'Revertir todo', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }

    Start-EmiWork -Label 'Revirtiendo cambios...' -Work { return (Undo-EmiChanges) } -OnDone {
        Update-EmiHome
        [System.Windows.MessageBox]::Show('Cambios revertidos. Reinicia el equipo para que todo vuelva a su estado anterior.',
            'Another''s Toolbox','OK','Information') | Out-Null
    }
})

$ui.BtnOpenLog.Add_Click({ Start-Process explorer.exe (Join-Path $Root 'Data') })

# ======================================================================
#                        VENTANA Y ARRANQUE
# ======================================================================

$ui.BtnClose.Add_Click({ $win.Close() })
$ui.BtnMin.Add_Click({ $win.WindowState = 'Minimized' })
$ui.BtnMax.Add_Click({
    $win.WindowState = if ($win.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
})

$win.Add_SourceInitialized({
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
        [void](Enable-EmiBackdrop -Handle $h -Style 'Acrylic')
    } catch { }
})

$win.Add_Loaded({
    Update-EmiHome
    Update-EmiAnyDesk
    $ui.TbHeaderHint.Text = $env:COMPUTERNAME + ' - mantenimiento de Windows 11'
})

$win.Add_Closed({
    try { $timer.Stop() } catch { }
    if ($script:Worker) { try { $script:Worker.Stop(); $script:Worker.Dispose() } catch { } }
    Write-EmiLog 'Another''s Toolbox cerrado.' Info
})

[void]$win.ShowDialog()

} catch {
    $errMsg = $_.Exception.Message
    $errLine = $_.InvocationInfo.ScriptLineNumber
    $errFile = $_.InvocationInfo.ScriptName
    $fullMsg = 'Error al iniciar EmiToolkit:' + "`n`n" + $errMsg + "`n`n" + 'Línea: ' + $errLine + "`n" + 'en ' + $errFile
    Write-RuntimeError -Message $fullMsg
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    [System.Windows.Forms.MessageBox]::Show($fullMsg + "`n`nLog: " + (Join-Path $Root 'Data\runtime-error.log'), 'EmiToolkit Error', 'OK', 'Error') | Out-Null
}
