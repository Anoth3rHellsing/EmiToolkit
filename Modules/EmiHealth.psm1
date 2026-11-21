# =====================================================================
#  EmiHealth.psm1 - Informe de salud del equipo (solo lectura)
# =====================================================================
#  Reúne en un HTML autocontenido el estado del equipo: Windows, discos,
#  batería, estabilidad, seguridad, arranque y lo que ha cambiado la propia
#  herramienta. No escribe nada en el sistema: solo lee. Lo único que crea es
#  el propio informe (y un XML temporal de powercfg) en su carpeta de datos.
#
#  Tres capas, para poder probarlo sin Windows:
#    1. Sondas: recogen datos en bruto. Las que pueden colgarse (CIM, discos,
#       registros de eventos, DISM, powercfg, Windows Update) corren en un
#       runspace aparte con tiempo límite; si fallan o se agotan, su apartado
#       sale como «no disponible» y el resto del informe sigue.
#    2. Evaluación: convierte los datos en filas con veredicto
#       (bien / atencion / mal / nd) y una línea de «qué hacer». Pura.
#    3. HTML: un solo archivo, sin recursos externos ni scripts, con una CSP
#       que bloquea cualquier carga. Cada valor pasa por HtmlEncode.
#
#  Privacidad: el informe solo lleva el nombre del equipo. Nada de usuarios,
#  rutas, etiquetas de volumen ni números de serie.
# =====================================================================

$script:EsCulture = [Globalization.CultureInfo]::GetCultureInfo('es-ES')
$script:VerdictRank = @{ 'nd' = 0; 'bien' = 1; 'atencion' = 2; 'mal' = 3 }
$script:VerdictText = @{ 'nd' = 'No disponible'; 'bien' = 'Bien'; 'atencion' = 'Atención'; 'mal' = 'Mal' }

function Write-EmiHealthLog {
    param([string] $Message, [string] $Level = 'Info')
    if (Get-Command Write-EmiLog -ErrorAction SilentlyContinue) { Write-EmiLog $Message $Level }
}

function Set-EmiHealthStatus {
    param([string] $Text, [int] $Percent)
    if (Get-Command Set-EmiStatus -ErrorAction SilentlyContinue) { Set-EmiStatus $Text $Percent }
}

# ======================================================================
#                     1. SONDAS (solo lectura)
# ======================================================================

# Funciones que tiene a mano cada sonda dentro de su runspace.
$script:ProbePrelude = {
    $ProbeErrors = New-Object System.Collections.ArrayList
    function Add-ProbeError { param([string] $What, $Err) [void]$ProbeErrors.Add(($What + ': ' + [string]$Err)) }
    function Invoke-ProbeExe {
        <#  Ejecuta un programa del sistema y devuelve su salida, matándolo si
            pasa del tiempo límite. @{ ExitCode; Out; TimedOut } #>
        param([string] $File, [string] $Arguments, [int] $TimeoutSec = 60)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $File
        $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch { }
            return @{ ExitCode = $null; Out = ''; TimedOut = $true }
        }
        $p.WaitForExit()
        return @{ ExitCode = $p.ExitCode; Out = [string]$outTask.Result + [string]$errTask.Result; TimedOut = $false }
    }
    function Get-ProbeEvents {
        <#  Eventos que cumplen el filtro; @() si no hay ninguno; $null si no
            se pudo leer el registro (para no confundir «0» con «no se sabe»). #>
        param([hashtable] $Filter, [int] $Max = 500)
        try { return @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $Max -ErrorAction Stop) }
        catch {
            if ([string]$_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return @() }
            Add-ProbeError ('eventos ' + [string]$Filter.LogName) $_.Exception.Message
            return $null
        }
    }
}

$script:TimedProbes = [ordered]@{

    Equipo = @{ Timeout = 40; Label = 'Windows y reinicios'; Script = {
        param($A)
        $o = @{ Computer = $env:COMPUTERNAME }
        try {
            $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $o.ProductName    = [string]$cv.ProductName
            $o.EditionId      = [string]$cv.EditionID
            $o.DisplayVersion = if ($cv.DisplayVersion) { [string]$cv.DisplayVersion } else { [string]$cv.ReleaseId }
            $o.Build          = [int]$cv.CurrentBuildNumber
            $o.Ubr            = [int]$cv.UBR
        } catch { Add-ProbeError 'version' $_.Exception.Message }
        try {
            $os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 20 -ErrorAction Stop
            $o.Caption  = [string]$os.Caption
            $o.LastBoot = [datetime]$os.LastBootUpTime
        } catch { Add-ProbeError 'arranque' $_.Exception.Message }
        # Sin el registro de Windows (o sin poder leerlo) no se sabe: se deja vacío
        if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion') { try {
            $o.PendingCbs = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            $o.PendingWu  = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            $sm = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
            $o.PendingRename = [bool](@($sm.PendingFileRenameOperations | Where-Object { $_ }).Count -gt 0)
        } catch { Add-ProbeError 'reinicio pendiente' $_.Exception.Message } }
        try {
            $pw = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction Stop
            if ($null -ne $pw.HiberbootEnabled) { $o.FastStartup = ([int]$pw.HiberbootEnabled -eq 1) }
        } catch { }
        $o.Errors = $ProbeErrors.ToArray()
        return $o
    } }

    Almacenamiento = @{ Timeout = 90; Label = 'discos'; Script = {
        param($A)
        $o = @{ Volumes = $null; Disks = $null }
        try {
            # Sin la etiqueta del volumen: puede llevar el nombre de alguien
            $o.Volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 20 -ErrorAction Stop |
                Where-Object { $_.Size -gt 0 } | ForEach-Object {
                    @{ Letter = [string]$_.DeviceID; FileSystem = [string]$_.FileSystem; Size = [double]$_.Size; Free = [double]$_.FreeSpace }
                })
        } catch { Add-ProbeError 'volumenes' $_.Exception.Message }
        try {
            $list = New-Object System.Collections.ArrayList
            foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
                # Modelo, tipo, bus, tamaño y estado. Nunca SerialNumber ni UniqueId.
                $h = @{
                    Name = [string]$d.FriendlyName; Media = [string]$d.MediaType; Bus = [string]$d.BusType
                    Size = [double]$d.Size; Health = [string]$d.HealthStatus
                    Operational = (@($d.OperationalStatus | ForEach-Object { [string]$_ }) -join ', ')
                }
                try {
                    $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop
                    if ($rc) {
                        $h.Wear = $rc.Wear; $h.Temperature = $rc.Temperature; $h.TemperatureMax = $rc.TemperatureMax
                        $h.ReadErrorsUncorrected = $rc.ReadErrorsUncorrected; $h.WriteErrorsUncorrected = $rc.WriteErrorsUncorrected
                        $h.PowerOnHours = $rc.PowerOnHours
                    }
                } catch { Add-ProbeError 'contadores de fiabilidad' $_.Exception.Message }
                [void]$list.Add($h)
            }
            $o.Disks = $list.ToArray()
        } catch { Add-ProbeError 'discos fisicos' $_.Exception.Message }
        $o.Errors = $ProbeErrors.ToArray()
        return $o
    } }

    WinSxS = @{ Timeout = 960; Label = 'almacén de componentes (WinSxS)'; Optional = $true; Script = {
        param($A)
        # /AnalyzeComponentStore solo analiza (no limpia). /English para poder
        # leer la salida en cualquier idioma de Windows.
        $dism = Join-Path $env:SystemRoot 'System32\Dism.exe'
        $r = Invoke-ProbeExe $dism '/English /Online /Cleanup-Image /AnalyzeComponentStore' 900
        if ($r.TimedOut) { return @{ TimedOut = $true } }
        $o = @{ ExitCode = $r.ExitCode }
        function Get-Size([string] $Label) {
            $m = [regex]::Match($r.Out, [regex]::Escape($Label) + '\s*:\s*([\d.,]+)\s*(bytes|KB|MB|GB|TB)', 'IgnoreCase')
            if (-not $m.Success) { return $null }
            $n = $m.Groups[1].Value
            if ($n -match ',' -and $n -notmatch '\.') { $n = $n -replace ',', '.' } else { $n = $n -replace ',', '' }
            $mult = @{ 'bytes' = 1; 'kb' = 1KB; 'mb' = 1MB; 'gb' = 1GB; 'tb' = 1TB }[$m.Groups[2].Value.ToLower()]
            return [double]::Parse($n, [Globalization.CultureInfo]::InvariantCulture) * $mult
        }
        $o.ActualBytes = Get-Size 'Actual Size of Component Store'
        $o.BackupsBytes = Get-Size 'Backups and Disabled Features'
        $o.CacheBytes = Get-Size 'Cache and Temporary Data'
        $m = [regex]::Match($r.Out, 'Number of Reclaimable Packages\s*:\s*(\d+)')
        if ($m.Success) { $o.Reclaimable = [int]$m.Groups[1].Value }
        $m = [regex]::Match($r.Out, 'Component Store Cleanup Recommended\s*:\s*(Yes|No)', 'IgnoreCase')
        if ($m.Success) { $o.Recommended = ($m.Groups[1].Value -ieq 'Yes') }
        return $o
    } }

    Bateria = @{ Timeout = 75; Label = 'batería'; Script = {
        param($A)
        $o = @{ HasBattery = $null; Batteries = @(); Source = $null }
        try { $o.HasBattery = (@(Get-CimInstance Win32_Battery -OperationTimeoutSec 15 -ErrorAction Stop).Count -gt 0) }
        catch { Add-ProbeError 'Win32_Battery' $_.Exception.Message }
        if ($o.HasBattery) {
            # powercfg escribe el XML en la carpeta de informes (solo
            # administradores); se lee y se borra enseguida. Del XML solo se
            # toman capacidades, química y ciclos: nunca el número de serie.
            $xmlPath = Join-Path $A.TempDir ('bateria-' + [guid]::NewGuid().ToString('N') + '.xml')
            try {
                $pc = Join-Path $env:SystemRoot 'System32\powercfg.exe'
                $r = Invoke-ProbeExe $pc ('/batteryreport /xml /output "' + $xmlPath + '"') 60
                if (-not $r.TimedOut -and (Test-Path -LiteralPath $xmlPath)) {
                    $x = New-Object System.Xml.XmlDocument
                    $x.XmlResolver = $null
                    $x.Load($xmlPath)
                    $list = New-Object System.Collections.ArrayList
                    foreach ($b in @($x.SelectNodes("//*[local-name()='Batteries']/*[local-name()='Battery']"))) {
                        $get = { param($n) $node = $b.SelectSingleNode("*[local-name()='$n']"); if ($node) { $node.InnerText } else { $null } }
                        [void]$list.Add(@{
                            Design = [double](& $get 'DesignCapacity'); Full = [double](& $get 'FullChargeCapacity')
                            Cycles = (& $get 'CycleCount'); Chemistry = [string](& $get 'Chemistry')
                        })
                    }
                    if ($list.Count -gt 0) { $o.Batteries = $list.ToArray(); $o.Source = 'powercfg' }
                }
            } catch { Add-ProbeError 'powercfg' $_.Exception.Message }
            finally { try { if (Test-Path -LiteralPath $xmlPath) { Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue } } catch { } }
            if (@($o.Batteries).Count -eq 0) {
                try {
                    $st = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -OperationTimeoutSec 15 -ErrorAction Stop)
                    $fc = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -OperationTimeoutSec 15 -ErrorAction Stop)
                    $cc = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryCycleCount -OperationTimeoutSec 15 -ErrorAction SilentlyContinue)
                    $list = New-Object System.Collections.ArrayList
                    for ($i = 0; $i -lt [math]::Min($st.Count, $fc.Count); $i++) {
                        $cyc = $null; if ($i -lt $cc.Count) { $cyc = $cc[$i].CycleCount }
                        [void]$list.Add(@{ Design = [double]$st[$i].DesignedCapacity; Full = [double]$fc[$i].FullChargedCapacity; Cycles = $cyc; Chemistry = $null })
                    }
                    if ($list.Count -gt 0) { $o.Batteries = $list.ToArray(); $o.Source = 'wmi' }
                } catch { Add-ProbeError 'bateria wmi' $_.Exception.Message }
            }
        }
        $o.Errors = $ProbeErrors.ToArray()
        return $o
    } }

    Estabilidad = @{ Timeout = 75; Label = 'estabilidad'; Script = {
        param($A)
        $since = (Get-Date).AddDays(-30)
        $o = @{ Stability = $null }
        try {
            $m = @(Get-CimInstance Win32_ReliabilityStabilityMetrics -OperationTimeoutSec 40 -ErrorAction Stop |
                   Where-Object { $_.TimeGenerated -and ([datetime]$_.TimeGenerated) -ge $since })
            # Un valor por día (el último de cada día), del más antiguo al más reciente
            $o.Stability = @($m | Group-Object { ([datetime]$_.TimeGenerated).Date.ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object {
                $last = $_.Group | Sort-Object { [datetime]$_.TimeGenerated } | Select-Object -Last 1
                @{ Day = ([datetime]$last.TimeGenerated).Date; Index = [double]$last.SystemStabilityIndex }
            })
        } catch { Add-ProbeError 'indice de estabilidad' $_.Exception.Message }
        $ev = Get-ProbeEvents @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since }
        $o.KernelPower = if ($null -eq $ev) { $null } else { $ev.Count }
        $o.LastKernelPower = if ($ev -and $ev.Count) { $ev[0].TimeCreated } else { $null }
        $ev = Get-ProbeEvents @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since }
        $o.BugCheck = if ($null -eq $ev) { $null } else { $ev.Count }
        $o.LastBugCheck = if ($ev -and $ev.Count) { $ev[0].TimeCreated } else { $null }
        $ev = Get-ProbeEvents @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since } 1000
        $o.AppCrashes = if ($null -eq $ev) { $null } else { $ev.Count }
        if ($ev -and $ev.Count) {
            # Solo el nombre del ejecutable (p. ej. «explorer.exe»), nunca su ruta
            $o.TopCrashApps = @($ev | ForEach-Object { try { [IO.Path]::GetFileName([string]$_.Properties[0].Value) } catch { $null } } |
                Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 3 |
                ForEach-Object { @{ Name = $_.Name; Count = $_.Count } })
        }
        $o.Errors = $ProbeErrors.ToArray()
        return $o
    } }

    Seguridad = @{ Timeout = 60; Label = 'seguridad'; Script = {
        param($A)
        $o = @{}
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            try {
                $mp = Get-MpComputerStatus -ErrorAction Stop
                $o.Defender = @{
                    RealTime = [bool]$mp.RealTimeProtectionEnabled; Enabled = [bool]$mp.AntivirusEnabled
                    SignatureAge = [int]$mp.AntivirusSignatureAge; Tamper = $mp.IsTamperProtected
                    Mode = [string]$mp.AMRunningMode
                }
            } catch { Add-ProbeError 'Defender' $_.Exception.Message }
        }
        # Antivirus y firewall registrados en Seguridad de Windows (ESET, etc.)
        try {
            $o.AvProducts = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object {
                $st = [int]$_.productState
                @{ Name = [string]$_.displayName; Enabled = (($st -band 0x1000) -ne 0); UpToDate = (($st -band 0x10) -eq 0) }
            })
        } catch { Add-ProbeError 'SecurityCenter2 antivirus' $_.Exception.Message }
        try {
            $o.FwProducts = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object {
                @{ Name = [string]$_.displayName; Enabled = (([int]$_.productState -band 0x1000) -ne 0) }
            })
        } catch { }
        try {
            $o.Firewall = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | ForEach-Object {
                @{ Profile = [string]$_.Name; Enabled = ([string]$_.Enabled -eq 'True' -or [string]$_.Enabled -eq '1') }
            })
        } catch { Add-ProbeError 'firewall' $_.Exception.Message }
        $sys = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
        if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
            try {
                $bl = Get-BitLockerVolume -MountPoint $sys -ErrorAction Stop
                $o.BitLocker = @{ Protection = [string]$bl.ProtectionStatus; Status = [string]$bl.VolumeStatus; Percent = [double]$bl.EncryptionPercentage }
            } catch { Add-ProbeError 'BitLocker' $_.Exception.Message }
        }
        if (-not $o.BitLocker) {
            try {
                $ev = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter ("DriveLetter='" + $sys + "'") -OperationTimeoutSec 15 -ErrorAction Stop
                if ($ev) { $o.BitLocker = @{ Protection = @{ 0 = 'Off'; 1 = 'On'; 2 = 'Unknown' }[[int]$ev.ProtectionStatus]; Status = $null; Percent = $null } }
            } catch { }
        }
        try { $o.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) }
        catch {
            if ($_.Exception -is [System.PlatformNotSupportedException] -or [string]$_.FullyQualifiedErrorId -like '*NotSupported*') { $o.SecureBoot = 'bios' }
            else {
                try {
                    $sb = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction Stop
                    if ($null -ne $sb.UEFISecureBootEnabled) { $o.SecureBoot = ([int]$sb.UEFISecureBootEnabled -eq 1) }
                } catch { Add-ProbeError 'Secure Boot' $_.Exception.Message }
            }
        }
        try {
            $t = @{ Present = $null; Ready = $null; Spec = $null }
            if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
                try { $g = Get-Tpm -ErrorAction Stop; $t.Present = [bool]$g.TpmPresent; $t.Ready = [bool]$g.TpmReady } catch { }
            }
            try {
                $w = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -OperationTimeoutSec 15 -ErrorAction Stop
                if ($w) {
                    $t.Spec = ([string]$w.SpecVersion -split ',')[0].Trim()
                    if ($null -eq $t.Present) { $t.Present = $true }
                } elseif ($null -eq $t.Present) { $t.Present = $false }
            } catch { }
            if ($null -ne $t.Present) { $o.Tpm = $t }
        } catch { Add-ProbeError 'TPM' $_.Exception.Message }
        try {
            $u = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop
            $o.Uac = @{ EnableLua = $u.EnableLUA; ConsentAdmin = $u.ConsentPromptBehaviorAdmin; SecureDesktop = $u.PromptOnSecureDesktop }
        } catch { Add-ProbeError 'UAC' $_.Exception.Message }
        $o.Errors = $ProbeErrors.ToArray()
        return $o
    } }

    Actualizaciones = @{ Timeout = 45; Label = 'Windows Update'; Script = {
        param($A)
        # Solo el historial local: no busca actualizaciones ni sale a la red
        $o = @{ LastInstall = $null; Title = $null; Source = $null }
        try {
            $s = New-Object -ComObject Microsoft.Update.Session
            $q = $s.CreateUpdateSearcher()
            $n = [int]$q.GetTotalHistoryCount()
            if ($n -gt 0) {
                $best = $null
                foreach ($h in @($q.QueryHistory(0, [math]::Min($n, 200)))) {
                    # Operation 1 = instalación, ResultCode 2 = correcta (3 = con errores)
                    if ([int]$h.Operation -ne 1 -or [int]$h.ResultCode -notin 2, 3) { continue }
                    $d = [datetime]$h.Date
                    if (-not $best -or $d -gt $best.Date) { $best = @{ Date = $d; Title = [string]$h.Title } }
                }
                if ($best) { $o.LastInstall = $best.Date.ToLocalTime(); $o.Title = $best.Title; $o.Source = 'wu' }
            }
        } catch { Add-ProbeError 'historial de Windows Update' $_.Exception.Message }
        if (-not $o.LastInstall) {
            try {
                $hf = @(Get-CimInstance Win32_QuickFixEngineering -OperationTimeoutSec 20 -ErrorAction Stop | Where-Object { $_.InstalledOn } |
                        Sort-Object { [datetime]$_.InstalledOn } | Select-Object -Last 1)
                if ($hf.Count) { $o.LastInstall = [datetime]$hf[0].InstalledOn; $o.Title = [string]$hf[0].HotFixID; $o.Source = 'hotfix' }
            } catch { Add-ProbeError 'hotfix' $_.Exception.Message }
        }
        $o.Errors = $ProbeErrors.ToArray()
        return $o
    } }

    Arranque = @{ Timeout = 40; Label = 'duración del arranque'; Script = {
        param($A)
        # El evento 100 de Diagnostics-Performance no existe en todos los
        # equipos (hay informes de que dejó de aparecer en algunas versiones).
        $o = @{ Boots = $null }
        $ev = Get-ProbeEvents @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } 5
        if ($null -ne $ev) {
            $o.Boots = @(foreach ($e in $ev) {
                try {
                    $x = [xml]$e.ToXml()
                    $d = @{}
                    foreach ($n in $x.Event.EventData.Data) { $d[[string]$n.Name] = [string]$n.'#text' }
                    @{ Time = $e.TimeCreated; BootMs = [double]$d['BootTime']; MainPathMs = [double]$d['MainPathBootTime'] }
                } catch { }
            })
        }
        $o.Errors = $ProbeErrors.ToArray()
        return $o
    } }
}

# Sondas que necesitan los demás módulos (corren en el runspace de la tarea)
$script:LocalProbes = [ordered]@{
    Programas = {
        if (-not (Get-Command Get-EmiStartupItems -ErrorAction SilentlyContinue)) { return $null }
        $items = @(Get-EmiStartupItems)
        return @{ Total = $items.Count; Enabled = @($items | Where-Object { [string]$_.Status -eq 'Activo' }).Count }
    }
    Cambios = {
        if (-not (Get-Command Get-EmiJournal -ErrorAction SilentlyContinue)) { return $null }
        $e = @(Get-EmiJournal)
        $lost = 0
        if (Get-Command Get-EmiJournalLostCount -ErrorAction SilentlyContinue) { $lost = [int](Get-EmiJournalLostCount) }
        return @{ Entries = $e; Lost = $lost }
    }
    Instantanea = { return (Get-EmiHealthSnapshot) }
}

function Invoke-EmiHealthTimed {
    <#  Ejecuta una sonda en un runspace aparte con tiempo límite.
        @{ Ok; Value; Error; TimedOut }. Si se agota el tiempo, el runspace se
        abandona (se le pide parar sin esperar): una llamada CIM o de
        almacenamiento colgada no bloquea el informe. #>
    param([Parameter(Mandatory)][scriptblock] $Script, [hashtable] $Arguments = @{}, [int] $TimeoutSec = 30)
    $res = @{ Ok = $false; Value = $null; Error = $null; TimedOut = $false }
    $rs = $null; $ps = $null; $abandon = $false
    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $runner = 'param($__Prelude, $__Probe, $A)' + "`n" +
                  '. ([scriptblock]::Create($__Prelude))' + "`n" +
                  '& ([scriptblock]::Create($__Probe)) $A'
        [void]$ps.AddScript($runner).AddArgument($script:ProbePrelude.ToString()).AddArgument($Script.ToString()).AddArgument($Arguments)
        $h = $ps.BeginInvoke()
        if (-not $h.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds([math]::Max(1, $TimeoutSec)))) {
            $res.TimedOut = $true
            $res.Error = "tiempo agotado ($TimeoutSec s)"
            $abandon = $true
            try { [void]$ps.BeginStop($null, $null) } catch { }
            return $res
        }
        $out = $ps.EndInvoke($h)
        if ($out -and $out.Count -gt 0) { $res.Value = $out[$out.Count - 1] }
        if ($res.Value -is [System.Management.Automation.PSObject]) { $res.Value = $res.Value.PSObject.BaseObject }
        $res.Ok = $true
        if ($ps.Streams.Error.Count -gt 0) { $res.Error = [string]$ps.Streams.Error[0] }
    } catch {
        $res.Error = $_.Exception.Message
    } finally {
        if (-not $abandon) {
            try { if ($ps) { $ps.Dispose() } } catch { }
            try { if ($rs) { $rs.Dispose() } } catch { }
        }
    }
    return $res
}

function Get-EmiHealthData {
    <#  Recoge los datos en bruto de todas las sondas.
        -Probes: sustituye sondas por nombre (pruebas). Una sonda sustituida
        corre igual que la original: en runspace con tiempo límite si es de
        las de $TimedProbes, en este runspace si es local. #>
    param([switch] $IncludeWinSxS, [hashtable] $Probes = @{}, [string] $TempDir)
    if (-not $TempDir) { $TempDir = [IO.Path]::GetTempPath() }
    $data = @{ Unavailable = @{} }
    $names = @($script:TimedProbes.Keys) + @($script:LocalProbes.Keys)
    $i = 0
    foreach ($name in $names) {
        $i++
        $pct = [int](100 * $i / ($names.Count + 1))
        if ($script:TimedProbes.Contains($name)) {
            $def = $script:TimedProbes[$name]
            if ($def.Optional -and -not $IncludeWinSxS) { $data[$name] = $null; $data.Unavailable[$name] = 'omitido'; continue }
            Set-EmiHealthStatus ('Informe de salud: ' + $def.Label + '...') $pct
            $sb = if ($Probes.ContainsKey($name)) { $Probes[$name] } else { $def.Script }
            $t = $def.Timeout
            if ($Probes.ContainsKey($name + 'Timeout')) { $t = [int]$Probes[$name + 'Timeout'] }
            $r = Invoke-EmiHealthTimed -Script $sb -Arguments @{ TempDir = $TempDir } -TimeoutSec $t
            if ($r.Ok -and $null -ne $r.Value) {
                $data[$name] = $r.Value
                foreach ($e in @($r.Value.Errors)) { if ($e) { Write-EmiHealthLog ('Informe de salud (' + $name + '): ' + $e) Info } }
            } else {
                $data[$name] = $null
                $data.Unavailable[$name] = if ($r.TimedOut) { 'tiempo agotado' } elseif ($r.Error) { [string]$r.Error } else { 'sin datos' }
                Write-EmiHealthLog ('Informe de salud: ' + $name + ' no disponible (' + $data.Unavailable[$name] + ').') Info
            }
        } else {
            Set-EmiHealthStatus ('Informe de salud: ' + $name.ToLower() + '...') $pct
            $sb = if ($Probes.ContainsKey($name)) { $Probes[$name] } else { $script:LocalProbes[$name] }
            try { $data[$name] = & $sb }
            catch {
                $data[$name] = $null
                $data.Unavailable[$name] = $_.Exception.Message
                Write-EmiHealthLog ('Informe de salud: ' + $name + ' no disponible (' + $_.Exception.Message + ').') Info
            }
        }
    }
    return $data
}

# ======================================================================
#                       ANTES / DESPUÉS (instantánea)
# ======================================================================

function Get-EmiHealthDir {
    <#  %ProgramData%\EmiToolkit\informes (heredando la ACL de solo
        administradores de la carpeta de datos). #>
    $base = $null
    if (Get-Command Get-EmiDataDir -ErrorAction SilentlyContinue) { $base = Get-EmiDataDir }
    if (-not $base) { return $null }
    $dir = Join-Path $base 'informes'
    if (Get-Command Initialize-EmiDataDir -ErrorAction SilentlyContinue) {
        # Repara la ACL y aparta una unión o enlace plantado, igual que la carpeta de datos
        Initialize-EmiDataDir $dir
    } elseif (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-EmiHealthSnapshotData {
    <#  Lo que se compara antes y después de «Optimizar ahora». Rápido y de
        solo lectura. #>
    $s = [ordered]@{ Time = (Get-Date).ToString('s'); Computer = $env:COMPUTERNAME }
    try {
        $v = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 20 -ErrorAction Stop)
        $s.FreeBytes = [double](($v | Measure-Object -Property FreeSpace -Sum).Sum)
    } catch { $s.FreeBytes = $null }
    try {
        $svc = @(Get-CimInstance Win32_Service -OperationTimeoutSec 20 -ErrorAction Stop)
        $s.ServicesDisabled = @($svc | Where-Object { $_.StartMode -eq 'Disabled' }).Count
        $s.ServicesRunning  = @($svc | Where-Object { $_.State -eq 'Running' }).Count
    } catch { $s.ServicesDisabled = $null; $s.ServicesRunning = $null }
    try {
        if (Get-Command Get-EmiStartupItems -ErrorAction SilentlyContinue) {
            $s.StartupEnabled = @(Get-EmiStartupItems | Where-Object { [string]$_.Status -eq 'Activo' }).Count
        } else { $s.StartupEnabled = $null }
    } catch { $s.StartupEnabled = $null }
    try { $s.Processes = @(Get-Process -ErrorAction Stop).Count } catch { $s.Processes = $null }
    try {
        if (Get-Command Get-EmiJournal -ErrorAction SilentlyContinue) { $s.Journal = @(Get-EmiJournal).Count } else { $s.Journal = $null }
    } catch { $s.Journal = $null }
    return $s
}

function Save-EmiHealthSnapshot {
    <#  Guarda la foto de «Antes» o «Despues» de Optimizar ahora en
        informes\instantanea.json. «Antes» empieza una pareja nueva. Nunca
        lanza: si algo falla, lo anota y sigue (no debe parar el mantenimiento). #>
    param([Parameter(Mandatory)][ValidateSet('Antes', 'Despues')][string] $Stage)
    try {
        $dir = Get-EmiHealthDir
        if (-not $dir) { return $false }
        $file = Join-Path $dir 'instantanea.json'
        $snap = Get-EmiHealthSnapshotData
        $doc = [ordered]@{ Antes = $null; Despues = $null }
        if ($Stage -eq 'Despues') {
            $old = Get-EmiHealthSnapshot
            if ($old -and $old.Antes) { $doc.Antes = $old.Antes }
        }
        $doc[$Stage] = $snap
        $json = ConvertTo-Json -InputObject ([pscustomobject]$doc) -Depth 5
        $tmp = $file + '.tmp'
        [IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $file -Force -ErrorAction Stop
        Write-EmiHealthLog ('Informe de salud: foto de ' + $(if ($Stage -eq 'Antes') { 'antes' } else { 'despues' }) + ' del mantenimiento guardada.') Info
        return $true
    } catch {
        Write-EmiHealthLog ('Informe de salud: no se pudo guardar la foto de ' + $Stage + ': ' + $_.Exception.Message) Info
        return $false
    }
}

function Get-EmiHealthSnapshot {
    <#  @{ Antes; Despues } (hashtables) o $null. Los números se leen como
        números: el archivo es de datos, nunca se interpreta. #>
    $dir = $null
    try { $dir = Get-EmiHealthDir } catch { }
    if (-not $dir) { return $null }
    $file = Join-Path $dir 'instantanea.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $fi = Get-Item -LiteralPath $file -Force
        if ($fi.Length -gt 64KB) { return $null }
        $j = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file))
        $conv = {
            param($x)
            if (-not $x) { return $null }
            $h = @{}
            foreach ($k in 'Time', 'FreeBytes', 'ServicesDisabled', 'ServicesRunning', 'StartupEnabled', 'Processes', 'Journal') {
                $v = $x.$k
                if ($null -eq $v) { $h[$k] = $null; continue }
                if ($k -eq 'Time') { $d = [datetime]::MinValue; if ([datetime]::TryParse([string]$v, [ref]$d)) { $h[$k] = $d } else { $h[$k] = $null } }
                else { $h[$k] = [double]$v }
            }
            return $h
        }
        return @{ Antes = (& $conv $j.Antes); Despues = (& $conv $j.Despues) }
    } catch { return $null }
}

# ======================================================================
#                     2. EVALUACIÓN (pura, sin Windows)
# ======================================================================

function New-EmiHealthRow {
    <#  Verdict $null = fila informativa (sin estado y no cuenta). #>
    param([string] $Label, [string] $Value, [string] $Verdict, [string] $Todo)
    return @{ Label = $Label; Value = $Value; Verdict = $Verdict; Todo = $Todo }
}

function New-EmiHealthSection {
    param([string] $Id, [string] $Title, [object[]] $Rows, [string] $OkTodo = 'Nada que hacer.', [string] $NdTodo,
          [string] $Note, $Spark, [string] $NdLabel)
    $worst = $null; $rank = -1
    foreach ($r in @($Rows)) {
        if (-not $r -or -not $r.Verdict) { continue }
        $k = $script:VerdictRank[[string]$r.Verdict]
        if ($null -ne $k -and $k -gt $rank) { $rank = $k; $worst = [string]$r.Verdict }
    }
    if (-not $worst) { $worst = 'nd' }
    $todo = $null
    if ($worst -eq 'bien') { $todo = $OkTodo }
    elseif ($worst -eq 'nd') { $todo = if ($NdTodo) { $NdTodo } else { 'No se pudo comprobar en este equipo.' } }
    else {
        foreach ($r in @($Rows)) { if ($r -and $r.Verdict -eq $worst -and $r.Todo) { $todo = $r.Todo; break } }
        if (-not $todo) { $todo = 'Revisa los puntos marcados.' }
    }
    return @{ Id = $Id; Title = $Title; Verdict = $worst; Todo = $todo; Rows = @($Rows | Where-Object { $_ }); Note = $Note; Spark = $Spark; NdLabel = $NdLabel }
}

function Format-EmiHealthNumber { param([double] $N, [int] $Decimals = 0) return $N.ToString('N' + $Decimals, $script:EsCulture) }

function Format-EmiHealthBytes {
    param([double] $Bytes)
    $neg = $Bytes -lt 0; $b = [math]::Abs($Bytes)
    $t = if ($b -ge 1TB) { (Format-EmiHealthNumber ($b / 1TB) 2) + ' TB' }
         elseif ($b -ge 1GB) { (Format-EmiHealthNumber ($b / 1GB) 1) + ' GB' }
         elseif ($b -ge 1MB) { (Format-EmiHealthNumber ($b / 1MB) 0) + ' MB' }
         elseif ($b -ge 1KB) { (Format-EmiHealthNumber ($b / 1KB) 0) + ' KB' }
         else { (Format-EmiHealthNumber $b 0) + ' B' }
    if ($neg) { return '−' + $t }
    return $t
}

function Format-EmiHealthDate {
    param($Date)
    if (-not $Date) { return 'desconocida' }
    return ([datetime]$Date).ToString('dd/MM/yyyy HH:mm', $script:EsCulture)
}

function Format-EmiHealthAge {
    param([TimeSpan] $Span)
    $d = [int][math]::Floor($Span.TotalDays)
    $h = $Span.Hours
    if ($d -ge 1) { return ('{0} {1}' -f $d, $(if ($d -eq 1) { 'día' } else { 'días' })) + $(if ($d -lt 3 -and $h -gt 0) { " y $h h" } else { '' }) }
    if ($Span.TotalHours -ge 1) { return ('{0} h' -f [int][math]::Floor($Span.TotalHours)) }
    return ('{0} min' -f [int][math]::Max(0, [math]::Floor($Span.TotalMinutes)))
}

function Get-EmiHealthEquipo {
    param($R, [datetime] $Now)
    $rows = New-Object System.Collections.ArrayList
    if (-not $R) { return (New-EmiHealthSection 'equipo' 'Equipo' @((New-EmiHealthRow 'Windows' 'no disponible' 'nd'))) }

    $name = ([string]$R.Caption) -replace '^Microsoft\s+', ''
    if (-not $name) {
        $name = [string]$R.ProductName
        # ProductName sigue diciendo «Windows 10» en Windows 11
        if ($R.Build -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }
    }
    if ($name) {
        $txt = $name
        if ($R.DisplayVersion) { $txt += ' ' + $R.DisplayVersion }
        if ($R.Build) { $txt += ' (compilación ' + $R.Build + $(if ($R.Ubr) { '.' + $R.Ubr } else { '' }) + ')' }
        $v = 'bien'; $todo = $null
        $ent = ([string]$R.EditionId -match 'Enterprise|Education|IoT')
        # Ciclo de vida de Microsoft (revisar cada año):
        #  Windows 10 22H2: fin el 14-oct-2025 (solo ESU).
        #  Windows 11 21H2-23H2 (< 26100): ya sin soporte en todas las ediciones.
        #  Windows 11 24H2 (26100): Home y Pro hasta el 13-oct-2026.
        if ($R.Build -gt 0 -and $R.Build -lt 22000) { $v = 'atencion'; $todo = 'Windows 10 ya no recibe actualizaciones gratuitas (desde el 14 de octubre de 2025): pasa a Windows 11 o contrata las ESU.' }
        elseif ($R.Build -gt 0 -and $R.Build -lt 26100) { $v = 'atencion'; $todo = 'Esta versión de Windows 11 ya no recibe actualizaciones de seguridad: instala la última desde Windows Update.' }
        elseif ($R.Build -eq 26100 -and -not $ent) { $v = 'atencion'; $todo = 'Windows 11 24H2 Home y Pro dejaron de recibir actualizaciones el 13 de octubre de 2026: instala la 25H2 desde Windows Update.' }
        [void]$rows.Add((New-EmiHealthRow 'Windows' $txt $v $todo))
    } else { [void]$rows.Add((New-EmiHealthRow 'Windows' 'no disponible' 'nd')) }

    if ($R.LastBoot) {
        $up = $Now - [datetime]$R.LastBoot
        $txt = (Format-EmiHealthDate $R.LastBoot) + ' (hace ' + (Format-EmiHealthAge $up) + ')'
        $v = 'bien'; $todo = $null
        if ($up.TotalDays -gt 14) {
            $v = 'atencion'
            $todo = 'Reinicia el equipo: lleva ' + [int][math]::Floor($up.TotalDays) + ' días sin reiniciar' + $(if ($R.FastStartup) { ' (con Inicio rápido, «Apagar» no cuenta).' } else { '.' })
        }
        [void]$rows.Add((New-EmiHealthRow 'Último reinicio' $txt $v $todo))
    } else { [void]$rows.Add((New-EmiHealthRow 'Último reinicio' 'no disponible' 'nd')) }

    $known = @(@($R.PendingCbs, $R.PendingWu, $R.PendingRename) | Where-Object { $null -ne $_ })
    if ($known.Count -eq 0) { [void]$rows.Add((New-EmiHealthRow 'Reinicio pendiente' 'no disponible' 'nd')) }
    else {
        $why = @()
        if ($R.PendingWu) { $why += 'Windows Update' }
        if ($R.PendingCbs) { $why += 'componentes de Windows' }
        if ($R.PendingRename) { $why += 'archivos por sustituir' }
        if ($R.PendingWu -or $R.PendingCbs) { [void]$rows.Add((New-EmiHealthRow 'Reinicio pendiente' ('Sí: ' + ($why -join ', ')) 'atencion' 'Reinicia para terminar de instalar las actualizaciones.')) }
        elseif ($R.PendingRename) { [void]$rows.Add((New-EmiHealthRow 'Reinicio pendiente' ('Sí: ' + ($why -join ', ')) 'atencion' 'Reinicia: un programa espera un reinicio para terminar de instalarse.')) }
        else { [void]$rows.Add((New-EmiHealthRow 'Reinicio pendiente' 'No' 'bien')) }
    }

    if ($null -ne $R.FastStartup) {
        if ($R.FastStartup) { [void]$rows.Add((New-EmiHealthRow 'Inicio rápido' 'Activado: «Apagar» no reinicia Windows' 'atencion' 'Usa «Reiniciar» en vez de «Apagar», o desactiva el Inicio rápido (Optimizar ahora lo hace).')) }
        else { [void]$rows.Add((New-EmiHealthRow 'Inicio rápido' 'Desactivado' 'bien')) }
    }
    return (New-EmiHealthSection 'equipo' 'Equipo' $rows.ToArray())
}

function ConvertTo-EmiDiskHealth {
    param([string] $Value)
    switch -Regex ($Value) {
        '^(0|Healthy)$'   { return 'Healthy' }
        '^(1|Warning)$'   { return 'Warning' }
        '^(2|Unhealthy)$' { return 'Unhealthy' }
        default           { return 'Unknown' }
    }
}

function Get-EmiHealthAlmacenamiento {
    param($R, $W, [bool] $WinSxSRequested, [string] $WinSxSWhy)
    $rows = New-Object System.Collections.ArrayList
    if (-not $R -or $null -eq $R.Volumes) { [void]$rows.Add((New-EmiHealthRow 'Espacio libre' 'no disponible' 'nd')) }
    else {
        foreach ($v in @($R.Volumes | Sort-Object { [string]$_.Letter })) {
            $size = [double]$v.Size; $free = [double]$v.Free
            if ($size -le 0) { continue }
            $pct = 100 * $free / $size
            $txt = (Format-EmiHealthBytes $free) + ' libres de ' + (Format-EmiHealthBytes $size) + ' (' + (Format-EmiHealthNumber $pct 0) + ' %)'
            $verdict = 'bien'; $todo = $null
            if ($pct -lt 10) { $verdict = 'mal'; $todo = 'Libera espacio en ' + $v.Letter + ': usa Optimizar ahora o Espacio en disco para ver qué ocupa más.' }
            elseif ($pct -lt 15) { $verdict = 'atencion'; $todo = 'Queda poco espacio en ' + $v.Letter + ': usa Espacio en disco para buscar archivos grandes.' }
            [void]$rows.Add((New-EmiHealthRow ('Unidad ' + $v.Letter + $(if ($v.FileSystem) { ' (' + $v.FileSystem + ')' } else { '' })) $txt $verdict $todo))
        }
        if ($rows.Count -eq 0) { [void]$rows.Add((New-EmiHealthRow 'Espacio libre' 'no se encontraron unidades fijas' 'nd')) }
    }

    $mediaMap = @{ '3' = 'HDD'; '4' = 'SSD'; '5' = 'SCM'; 'HDD' = 'HDD'; 'SSD' = 'SSD'; 'SCM' = 'SCM' }
    $busMap = @{ '17' = 'NVMe'; '11' = 'SATA'; '7' = 'USB'; '8' = 'RAID'; '10' = 'SAS'; '12' = 'SD'; '13' = 'MMC'; '1' = 'SCSI'; '3' = 'ATA'; '15' = 'Virtual' }
    if (-not $R -or $null -eq $R.Disks) { [void]$rows.Add((New-EmiHealthRow 'Discos físicos' 'no disponible' 'nd')) }
    else {
        foreach ($d in @($R.Disks | Where-Object { $_ })) {
            $parts = @()
            $m = $mediaMap[[string]$d.Media]; if ($m) { $parts += $m }
            $b = $busMap[[string]$d.Bus]; if (-not $b -and [string]$d.Bus -and [string]$d.Bus -notmatch '^\d+$') { $b = [string]$d.Bus }; if ($b) { $parts += $b }
            if ([double]$d.Size -gt 0) { $parts += (Format-EmiHealthBytes ([double]$d.Size)) }
            $health = ConvertTo-EmiDiskHealth ([string]$d.Health)
            $verdict = 'bien'; $todo = $null
            switch ($health) {
                'Healthy'   { $parts += 'sano' }
                'Warning'   { $parts += 'con avisos'; $verdict = 'atencion'; $todo = 'El disco avisa de problemas: haz copia de seguridad y vigílalo.' }
                'Unhealthy' { $parts += 'con fallos'; $verdict = 'mal'; $todo = 'El disco está fallando: haz copia de seguridad YA y cámbialo.' }
                default     { $parts += 'estado desconocido'; $verdict = 'nd' }
            }
            $op = [string]$d.Operational
            if ($op -and $op -notmatch '^(OK|2)(,\s*(OK|2))*$' -and $verdict -eq 'bien') { $verdict = 'atencion'; $todo = 'El disco no está en estado normal (' + $op + '): revísalo en Administración de discos.' }
            if ($null -ne $d.Wear -and [string]$d.Wear -ne '') {
                $wear = [double]$d.Wear
                $parts += ('desgaste ' + (Format-EmiHealthNumber $wear 0) + ' %')
                if ($wear -ge 90) { $verdict = 'mal'; $todo = 'El SSD está casi gastado: haz copia de seguridad y planea cambiarlo.' }
                elseif ($wear -ge 70 -and $verdict -ne 'mal') { $verdict = 'atencion'; $todo = 'El SSD lleva mucho desgaste: mantén copias de seguridad al día.' }
            }
            if ($null -ne $d.Temperature -and [string]$d.Temperature -ne '' -and [double]$d.Temperature -gt 0) {
                $tc = [double]$d.Temperature
                $parts += ((Format-EmiHealthNumber $tc 0) + ' °C')
                if ($tc -ge 70 -and $verdict -ne 'mal') { $verdict = 'atencion'; $todo = 'El disco está caliente: revisa la ventilación del equipo.' }
            }
            if ($null -ne $d.ReadErrorsUncorrected -and [string]$d.ReadErrorsUncorrected -ne '' -and [double]$d.ReadErrorsUncorrected -gt 0) {
                $parts += ([string][int64]$d.ReadErrorsUncorrected + ' errores de lectura sin corregir')
                if ($verdict -ne 'mal') { $verdict = 'atencion'; $todo = 'El disco tiene errores de lectura: haz copia de seguridad y vigílalo.' }
            }
            if ($null -ne $d.PowerOnHours -and [string]$d.PowerOnHours -ne '' -and [double]$d.PowerOnHours -gt 0) {
                $parts += ((Format-EmiHealthNumber ([double]$d.PowerOnHours) 0) + ' h encendido')
            }
            $label = 'Disco: ' + $(if ([string]$d.Name) { [string]$d.Name } else { 'sin nombre' })
            [void]$rows.Add((New-EmiHealthRow $label ($parts -join ' · ') $verdict $todo))
        }
        if (@($R.Disks | Where-Object { $_ }).Count -eq 0) { [void]$rows.Add((New-EmiHealthRow 'Discos físicos' 'no se encontraron' 'nd')) }
    }

    if (-not $WinSxSRequested) {
        [void]$rows.Add((New-EmiHealthRow 'WinSxS (componentes)' 'no analizado: marca «Analizar también WinSxS» para incluirlo (tarda varios minutos)' $null))
    } elseif (-not $W -or $W.TimedOut -or $null -eq $W.Recommended) {
        $why = if ($W -and $W.TimedOut) { 'DISM tardó demasiado' } elseif ($WinSxSWhy) { 'no disponible' } else { 'no se pudo leer el resultado de DISM' }
        [void]$rows.Add((New-EmiHealthRow 'WinSxS (componentes)' $why 'nd'))
    } else {
        $txt = @()
        if ($W.ActualBytes) { $txt += ('ocupa ' + (Format-EmiHealthBytes $W.ActualBytes)) }
        if ($null -ne $W.Reclaimable) { $txt += ([string]$W.Reclaimable + ' paquetes recuperables') }
        if ($W.Recommended) {
            $txt += 'se recomienda limpiar'
            [void]$rows.Add((New-EmiHealthRow 'WinSxS (componentes)' ($txt -join ' · ') 'atencion' 'Limpia los componentes: Modo avanzado › Espacio en disco › DISM.'))
        } else {
            $txt += 'no hace falta limpiar'
            [void]$rows.Add((New-EmiHealthRow 'WinSxS (componentes)' ($txt -join ' · ') 'bien'))
        }
    }
    return (New-EmiHealthSection 'almacenamiento' 'Almacenamiento' $rows.ToArray())
}

function Get-EmiHealthBateria {
    param($R)
    if (-not $R -or $null -eq $R.HasBattery) {
        return (New-EmiHealthSection 'bateria' 'Batería' @((New-EmiHealthRow 'Batería' 'no disponible' 'nd')))
    }
    if (-not $R.HasBattery) {
        return (New-EmiHealthSection 'bateria' 'Batería' @((New-EmiHealthRow 'Batería' 'Este equipo no tiene batería' $null)) -NdTodo 'Nada: es un equipo sin batería.' -NdLabel 'No aplica')
    }
    $rows = New-Object System.Collections.ArrayList
    $i = 0
    $bats = @($R.Batteries | Where-Object { $_ })
    foreach ($b in $bats) {
        $i++
        $n = if ($bats.Count -gt 1) { ' ' + $i } else { '' }
        $design = [double]$b.Design; $full = [double]$b.Full
        if ($design -gt 0 -and $full -gt 0) {
            $pct = 100 * $full / $design
            $txt = (Format-EmiHealthNumber $full 0) + ' de ' + (Format-EmiHealthNumber $design 0) + ' mWh de fábrica (' + (Format-EmiHealthNumber ([math]::Min($pct, 100)) 0) + ' %)'
            $v = 'bien'; $todo = $null
            if ($pct -lt 50) { $v = 'mal'; $todo = 'La batería retiene menos de la mitad de su carga original: conviene cambiarla.' }
            elseif ($pct -lt 80) { $v = 'atencion'; $todo = 'La batería ha perdido capacidad: dura menos que nueva. Evita dejarla al 100 % enchufada todo el día.' }
            [void]$rows.Add((New-EmiHealthRow ('Capacidad' + $n) $txt $v $todo))
        } else { [void]$rows.Add((New-EmiHealthRow ('Capacidad' + $n) 'no disponible' 'nd')) }
        $c = $null
        if ($null -ne $b.Cycles -and [string]$b.Cycles -match '^\d+$' -and [int]$b.Cycles -gt 0) { $c = [int]$b.Cycles }
        [void]$rows.Add((New-EmiHealthRow ('Ciclos de carga' + $n) $(if ($c) { Format-EmiHealthNumber $c 0 } else { 'el fabricante no lo informa' }) $null))
    }
    if ($rows.Count -eq 0) { [void]$rows.Add((New-EmiHealthRow 'Batería' 'hay batería, pero no se pudo leer su capacidad' 'nd')) }
    return (New-EmiHealthSection 'bateria' 'Batería' $rows.ToArray())
}

function Get-EmiHealthEstabilidad {
    param($R)
    $rows = New-Object System.Collections.ArrayList
    $spark = $null
    if (-not $R) { return (New-EmiHealthSection 'estabilidad' 'Estabilidad' @((New-EmiHealthRow 'Estabilidad' 'no disponible' 'nd'))) }

    $st = @($R.Stability | Where-Object { $_ })
    if ($st.Count -gt 0) {
        $vals = @($st | ForEach-Object { [double]$_.Index })
        $cur = $vals[-1]
        $first = @($vals | Select-Object -First ([math]::Min(7, $vals.Count)))
        $last = @($vals | Select-Object -Last ([math]::Min(7, $vals.Count)))
        $d = (($last | Measure-Object -Average).Average) - (($first | Measure-Object -Average).Average)
        $trend = if ($vals.Count -lt 4) { 'pocos datos' } elseif ($d -ge 0.5) { 'mejorando' } elseif ($d -le -0.5) { 'empeorando' } else { 'estable' }
        $v = 'bien'; $todo = $null
        if ($cur -lt 4) { $v = 'mal'; $todo = 'Windows ha tenido muchos fallos este mes: mira los apagados y cierres de abajo.' }
        elseif ($cur -lt 7) { $v = 'atencion'; $todo = 'Hay fallos recientes: abre el Monitor de confiabilidad (busca «confiabilidad» en Inicio).' }
        $txt = (Format-EmiHealthNumber $cur 1) + ' de 10 · ' + $trend + ' (mínimo del mes: ' + (Format-EmiHealthNumber (($vals | Measure-Object -Minimum).Minimum) 1) + ')'
        [void]$rows.Add((New-EmiHealthRow 'Índice de estabilidad' $txt $v $todo))
        $spark = @($vals)
    } else {
        [void]$rows.Add((New-EmiHealthRow 'Índice de estabilidad' 'no disponible (el análisis de confiabilidad de Windows no tiene datos)' 'nd'))
    }

    if ($null -eq $R.KernelPower) { [void]$rows.Add((New-EmiHealthRow 'Apagados inesperados (30 días)' 'no disponible' 'nd')) }
    else {
        $n = [int]$R.KernelPower
        $v = if ($n -eq 0) { 'bien' } elseif ($n -le 2) { 'atencion' } else { 'mal' }
        $txt = [string]$n + $(if ($n -gt 0 -and $R.LastKernelPower) { ' · último: ' + (Format-EmiHealthDate $R.LastKernelPower) } else { '' })
        [void]$rows.Add((New-EmiHealthRow 'Apagados inesperados (30 días)' $txt $v 'El equipo se apagó sin cerrar Windows: revisa la fuente o la batería, la temperatura y los cortes de luz.'))
    }
    if ($null -eq $R.BugCheck) { [void]$rows.Add((New-EmiHealthRow 'Pantallazos azules (30 días)' 'no disponible' 'nd')) }
    else {
        $n = [int]$R.BugCheck
        $v = if ($n -eq 0) { 'bien' } elseif ($n -eq 1) { 'atencion' } else { 'mal' }
        $txt = [string]$n + $(if ($n -gt 0 -and $R.LastBugCheck) { ' · último: ' + (Format-EmiHealthDate $R.LastBugCheck) } else { '' })
        [void]$rows.Add((New-EmiHealthRow 'Pantallazos azules (30 días)' $txt $v 'Windows se ha bloqueado: actualiza los controladores (sobre todo gráfica y chipset) y Windows.'))
    }
    if ($null -eq $R.AppCrashes) { [void]$rows.Add((New-EmiHealthRow 'Cierres de programas (30 días)' 'no disponible' 'nd')) }
    else {
        $n = [int]$R.AppCrashes
        $v = if ($n -le 10) { 'bien' } else { 'atencion' }
        $txt = [string]$n
        $top = @($R.TopCrashApps | Where-Object { $_ })
        if ($top.Count -gt 0) { $txt += ' · más frecuentes: ' + (($top | ForEach-Object { [string]$_.Name + ' (' + [string]$_.Count + ')' }) -join ', ') }
        [void]$rows.Add((New-EmiHealthRow 'Cierres de programas (30 días)' $txt $v 'Algunos programas se cierran solos: actualízalos o reinstálalos.'))
    }
    return (New-EmiHealthSection 'estabilidad' 'Estabilidad' $rows.ToArray() -Spark $spark)
}

function Get-EmiHealthSeguridad {
    param($R, $U, [datetime] $Now)
    $rows = New-Object System.Collections.ArrayList
    if (-not $R) { $R = @{} }

    # Antivirus: Defender o el que esté registrado (ESET, etc.)
    $def = $R.Defender
    $others = @($R.AvProducts | Where-Object { $_ -and [string]$_.Name -notmatch 'Windows Defender|Microsoft Defender' })
    $othersOn = @($others | Where-Object { $_.Enabled })
    if ($def -and $def.RealTime) {
        [void]$rows.Add((New-EmiHealthRow 'Antivirus' 'Microsoft Defender, protección en tiempo real activada' 'bien'))
        $age = [int]$def.SignatureAge
        $v = if ($age -le 3) { 'bien' } elseif ($age -le 7) { 'atencion' } else { 'mal' }
        [void]$rows.Add((New-EmiHealthRow 'Firmas del antivirus' ('de hace ' + $age + $(if ($age -eq 1) { ' día' } else { ' días' })) $v 'Actualiza Defender: Seguridad de Windows › Protección antivirus › Buscar actualizaciones.'))
    } elseif ($othersOn.Count -gt 0) {
        $a = $othersOn[0]
        $v = if ($a.UpToDate) { 'bien' } else { 'atencion' }
        [void]$rows.Add((New-EmiHealthRow 'Antivirus' ([string]$a.Name + ' activo' + $(if ($a.UpToDate) { ', al día' } else { ', firmas sin actualizar' })) $v ('Abre ' + [string]$a.Name + ' y actualízalo.')))
    } elseif ($def -or @($R.AvProducts | Where-Object { $_ }).Count -gt 0) {
        [void]$rows.Add((New-EmiHealthRow 'Antivirus' 'Sin protección en tiempo real' 'mal' 'Activa la protección en tiempo real en Seguridad de Windows (o tu antivirus).'))
    } else { [void]$rows.Add((New-EmiHealthRow 'Antivirus' 'no disponible' 'nd')) }

    $profName = @{ 'Domain' = 'Dominio'; 'Private' = 'Privada'; 'Public' = 'Pública' }
    $fw = @($R.Firewall | Where-Object { $_ })
    $fwOther = @($R.FwProducts | Where-Object { $_ -and $_.Enabled -and [string]$_.Name -notmatch 'Windows' })
    if ($fw.Count -gt 0) {
        $off = @($fw | Where-Object { -not $_.Enabled })
        if ($off.Count -eq 0) { [void]$rows.Add((New-EmiHealthRow 'Firewall de Windows' 'Activado en todas las redes' 'bien')) }
        else {
            $names = ($off | ForEach-Object { $p = $profName[[string]$_.Profile]; if ($p) { $p } else { [string]$_.Profile } }) -join ', '
            if ($fwOther.Count -gt 0) { [void]$rows.Add((New-EmiHealthRow 'Firewall' ('Lo gestiona ' + [string]$fwOther[0].Name + ' (Windows desactivado en: ' + $names + ')') 'bien')) }
            else {
                $v = if (@($off | Where-Object { [string]$_.Profile -eq 'Public' }).Count -gt 0) { 'mal' } else { 'atencion' }
                [void]$rows.Add((New-EmiHealthRow 'Firewall de Windows' ('Desactivado en: ' + $names) $v 'Activa el firewall: Seguridad de Windows › Firewall y protección de red.'))
            }
        }
    } else { [void]$rows.Add((New-EmiHealthRow 'Firewall' 'no disponible' 'nd')) }

    $bl = $R.BitLocker
    if ($bl -and $bl.Protection) {
        switch ([string]$bl.Protection) {
            'On'  { [void]$rows.Add((New-EmiHealthRow 'Cifrado del disco (BitLocker)' 'Activado en la unidad del sistema' 'bien')) }
            'Off' {
                $txt = 'Desactivado'
                if ($null -ne $bl.Percent -and [double]$bl.Percent -gt 0 -and [double]$bl.Percent -lt 100) { $txt += ' (cifrado al ' + (Format-EmiHealthNumber ([double]$bl.Percent) 0) + ' %)' }
                elseif ([string]$bl.Status -eq 'FullyEncrypted') { $txt = 'Cifrado, pero con la protección suspendida' }
                [void]$rows.Add((New-EmiHealthRow 'Cifrado del disco (BitLocker)' $txt 'atencion' 'Si es un portátil, activa el cifrado (BitLocker o Cifrado de dispositivo) y guarda la clave de recuperación.'))
            }
            default { [void]$rows.Add((New-EmiHealthRow 'Cifrado del disco (BitLocker)' 'estado desconocido' 'nd')) }
        }
    } else { [void]$rows.Add((New-EmiHealthRow 'Cifrado del disco (BitLocker)' 'no disponible en esta edición o equipo' 'nd')) }

    if ($R.SecureBoot -is [bool]) {
        if ($R.SecureBoot) { [void]$rows.Add((New-EmiHealthRow 'Arranque seguro (Secure Boot)' 'Activado' 'bien')) }
        else { [void]$rows.Add((New-EmiHealthRow 'Arranque seguro (Secure Boot)' 'Desactivado' 'atencion' 'Activa Secure Boot en la UEFI del equipo (protege contra malware de arranque).')) }
    } elseif ([string]$R.SecureBoot -eq 'bios') {
        [void]$rows.Add((New-EmiHealthRow 'Arranque seguro (Secure Boot)' 'El equipo arranca en modo BIOS heredado' 'atencion' 'El equipo arranca en modo BIOS: Secure Boot necesita UEFI (pide ayuda antes de cambiarlo).'))
    } else { [void]$rows.Add((New-EmiHealthRow 'Arranque seguro (Secure Boot)' 'no disponible' 'nd')) }

    $t = $R.Tpm
    if ($t -and $null -ne $t.Present) {
        if (-not $t.Present) { [void]$rows.Add((New-EmiHealthRow 'TPM' 'No hay TPM o está desactivado' 'atencion' 'Activa el TPM (fTPM / PTT) en la UEFI: Windows 11 y BitLocker lo necesitan.')) }
        else {
            $txt = 'Presente' + $(if ($t.Spec) { ', versión ' + $t.Spec } else { '' }) + $(if ($t.Ready -eq $false) { ', no preparado' } else { '' })
            $v = 'bien'
            if ($t.Ready -eq $false) { $v = 'atencion' }
            if ($t.Spec -and [string]$t.Spec -notmatch '^2') { $v = 'atencion' }
            [void]$rows.Add((New-EmiHealthRow 'TPM' $txt $v 'El TPM no está listo o es antiguo: revísalo en tpm.msc.'))
        }
    } else { [void]$rows.Add((New-EmiHealthRow 'TPM' 'no disponible' 'nd')) }

    $u = $R.Uac
    if ($u -and $null -ne $u.EnableLua) {
        if ([int]$u.EnableLua -eq 0) { [void]$rows.Add((New-EmiHealthRow 'Control de cuentas (UAC)' 'Desactivado' 'mal' 'Activa el Control de cuentas de usuario: sin él, cualquier programa corre como administrador.')) }
        elseif ($null -ne $u.ConsentAdmin -and [int]$u.ConsentAdmin -eq 0) { [void]$rows.Add((New-EmiHealthRow 'Control de cuentas (UAC)' 'Activado, pero eleva sin preguntar' 'atencion' 'Sube el Control de cuentas de usuario al nivel predeterminado.')) }
        else { [void]$rows.Add((New-EmiHealthRow 'Control de cuentas (UAC)' 'Activado' 'bien')) }
    } else { [void]$rows.Add((New-EmiHealthRow 'Control de cuentas (UAC)' 'no disponible' 'nd')) }

    if ($U -and $U.LastInstall) {
        $age = ($Now - [datetime]$U.LastInstall).TotalDays
        $v = if ($age -le 35) { 'bien' } elseif ($age -le 60) { 'atencion' } else { 'mal' }
        $txt = (Format-EmiHealthDate $U.LastInstall) + ' (hace ' + (Format-EmiHealthAge ($Now - [datetime]$U.LastInstall)) + ')'
        if ($U.Title) { $kb = [regex]::Match([string]$U.Title, 'KB\d{6,8}'); if ($kb.Success) { $txt += ' · ' + $kb.Value } }
        [void]$rows.Add((New-EmiHealthRow 'Última actualización instalada' $txt $v 'Busca actualizaciones en Configuración › Windows Update e instálalas.'))
    } else { [void]$rows.Add((New-EmiHealthRow 'Última actualización instalada' 'no disponible' 'nd')) }

    return (New-EmiHealthSection 'seguridad' 'Seguridad' $rows.ToArray())
}

function Get-EmiHealthArranque {
    param($Boot, $Startup)
    $rows = New-Object System.Collections.ArrayList
    if ($Startup -and $null -ne $Startup.Enabled) {
        $n = [int]$Startup.Enabled
        $v = if ($n -le 10) { 'bien' } elseif ($n -le 20) { 'atencion' } else { 'mal' }
        $txt = [string]$n + ' activos' + $(if ($null -ne $Startup.Total) { ' de ' + [string]$Startup.Total + ' encontrados' } else { '' })
        [void]$rows.Add((New-EmiHealthRow 'Programas al iniciar' $txt $v 'Quita del arranque lo que no uses: Modo avanzado › Arranque.'))
    } else { [void]$rows.Add((New-EmiHealthRow 'Programas al iniciar' 'no disponible' 'nd')) }

    $b = @($Boot.Boots | Where-Object { $_ -and ([double]$_.MainPathMs -gt 0 -or [double]$_.BootMs -gt 0) })
    if ($b.Count -gt 0) {
        $last = $b[0]
        $ms = if ([double]$last.MainPathMs -gt 0) { [double]$last.MainPathMs } else { [double]$last.BootMs }
        $s = $ms / 1000
        $v = if ($s -lt 30) { 'bien' } elseif ($s -lt 60) { 'atencion' } else { 'mal' }
        $txt = (Format-EmiHealthNumber $s 0) + ' s hasta el escritorio'
        if ([double]$last.BootMs -gt 0 -and [double]$last.MainPathMs -gt 0) { $txt += ' (' + (Format-EmiHealthNumber ([double]$last.BootMs / 1000) 0) + ' s hasta quedar listo)' }
        if ($last.Time) { $txt += ' · ' + (Format-EmiHealthDate $last.Time) }
        [void]$rows.Add((New-EmiHealthRow 'Duración del último arranque' $txt $v 'El arranque es lento: quita programas del inicio y, si el disco es HDD, plantéate un SSD.'))
    } else {
        [void]$rows.Add((New-EmiHealthRow 'Duración del último arranque' 'Windows no la ha registrado (el evento 100 de Diagnostics-Performance no existe en todos los equipos)' 'nd'))
    }
    return (New-EmiHealthSection 'arranque' 'Arranque' $rows.ToArray())
}

function Get-EmiHealthEntryText {
    <#  Una línea por cambio del diario, sin rutas de archivo ni nombres de usuario. #>
    param($E)
    switch ([string]$E.Kind) {
        'Registry' {
            $leaf = ([string]$E.Path -split '\\')[-1]
            return 'Registro: ' + $leaf + ' › ' + [string]$E.Name
        }
        'Service'  { return 'Servicio ' + [string]$E.Name + $(if ($E.OldStartMode) { ' (antes: ' + [string]$E.OldStartMode + ')' } else { '' }) }
        'Task'     { return 'Tarea programada ' + [string]$E.TaskName }
        'Firewall' { return 'Regla de firewall ' + [string]$E.RuleName }
        'File'     { if ([string]$E.Path -match '\\etc\\hosts$') { return 'Archivo hosts' + $(if ($E.Backup) { ' (con copia)' } else { '' }) } else { return 'Archivo o carpeta borrado' + $(if ($E.Backup) { ' (con copia)' } else { ' (sin copia)' }) } }
        'Command'  {
            switch ([string]$E.Action) {
                'AppxReinstall'  { return 'App quitada: ' + [string]$E.PackageName }
                'WindowsFeature' { return 'Característica de Windows: ' + [string]$E.Feature }
                'Hibernate'      { return 'Hibernación' }
                'EnvVars'        { return 'Variables de entorno de telemetría' }
                default          { if ($E.PackageName) { return 'App quitada: ' + [string]$E.PackageName } else { return 'Otro cambio' } }
            }
        }
        default { return 'Cambio de tipo ' + [string]$E.Kind }
    }
}

function Test-EmiHealthReversible {
    <#  Lo mismo que considera reversible el deshacer: un archivo sin copia
        y las acciones «Manual» no se pueden deshacer automáticamente. #>
    param($E)
    $k = [string]$E.Kind
    if ($k -eq 'File') { return [bool]$E.Backup }
    if ($k -eq 'Command') {
        if ($E.Action) { return ([string]$E.Action -ne 'Manual') }
        return ([bool]$E.PackageName -or [string]$E.Undo -match 'powercfg\s+/hibernate\s+on|SetEnvironmentVariable')
    }
    return ($k -in 'Registry', 'Service', 'Task', 'Firewall')
}

function Get-EmiHealthCambios {
    param($R)
    $rows = New-Object System.Collections.ArrayList
    if (-not $R) { return (New-EmiHealthSection 'cambios' "Lo que cambió Another's Toolbox" @((New-EmiHealthRow 'Diario de cambios' 'no disponible' 'nd'))) }
    $e = @($R.Entries | Where-Object { $_ })
    $lost = [int]$R.Lost
    if ($e.Count -eq 0 -and $lost -eq 0) {
        return (New-EmiHealthSection 'cambios' "Lo que cambió Another's Toolbox" @((New-EmiHealthRow 'Cambios registrados' 'Ninguno: la herramienta no ha cambiado nada en este equipo (o ya se revirtió todo)' 'bien')))
    }
    $kindName = [ordered]@{ Registry = 'registro'; Service = 'servicios'; Task = 'tareas programadas'; Firewall = 'reglas de firewall'; File = 'archivos'; Command = 'otros (apps, características, hibernación)' }
    $parts = @()
    foreach ($k in $kindName.Keys) {
        $n = @($e | Where-Object { [string]$_.Kind -eq $k }).Count
        if ($n -gt 0) { $parts += ([string]$n + ' ' + $kindName[$k]) }
    }
    $other = @($e | Where-Object { -not $kindName.Contains([string]$_.Kind) }).Count
    if ($other -gt 0) { $parts += ([string]$other + ' de otro tipo') }
    [void]$rows.Add((New-EmiHealthRow 'Cambios registrados' ([string]$e.Count + ': ' + ($parts -join ', ')) 'bien'))
    $rev = @($e | Where-Object { Test-EmiHealthReversible $_ }).Count
    $v = if ($rev -eq $e.Count) { 'bien' } else { $null }
    [void]$rows.Add((New-EmiHealthRow 'Se pueden deshacer' ([string]$rev + ' de ' + [string]$e.Count + $(if ($rev -lt $e.Count) { ' (el resto son borrados sin copia o cambios manuales)' } else { '' })) $v))
    if ($lost -gt 0) { [void]$rows.Add((New-EmiHealthRow 'Entradas dañadas' ([string]$lost + ' entradas antiguas no se pueden leer') 'atencion' 'Algunas entradas del diario están dañadas: lo que registraban no se podrá revertir automáticamente; queda el punto de restauración.')) }
    $recent = @($e | Select-Object -Last 5)
    [array]::Reverse($recent)
    foreach ($x in $recent) {
        $when = $null; $d = [datetime]::MinValue
        if ([datetime]::TryParse([string]$x.Timestamp, [ref]$d)) { $when = Format-EmiHealthDate $d }
        [void]$rows.Add((New-EmiHealthRow $(if ($when) { $when } else { 'Cambio reciente' }) (Get-EmiHealthEntryText $x) $null))
    }
    return (New-EmiHealthSection 'cambios' "Lo que cambió Another's Toolbox" $rows.ToArray() -OkTodo 'Para volver atrás: Modo avanzado › Registro y deshacer › Revertir todos los cambios.')
}

function Get-EmiHealthAntesDespues {
    param($S)
    $title = 'Antes y después de Optimizar ahora'
    if (-not $S -or -not $S.Antes) {
        return (New-EmiHealthSection 'antesdespues' $title @((New-EmiHealthRow 'Optimizar ahora' 'Todavía no hay datos: se guardan al usar «Optimizar ahora»' $null)) -NdTodo 'Usa «Optimizar ahora» y vuelve a generar el informe para ver la diferencia.' -NdLabel 'Sin datos')
    }
    $a = $S.Antes; $d = $S.Despues
    if (-not $d -or ($a.Time -and $d.Time -and $d.Time -lt $a.Time)) {
        return (New-EmiHealthSection 'antesdespues' $title @((New-EmiHealthRow 'Optimizar ahora' ('Empezó el ' + (Format-EmiHealthDate $a.Time) + ' y no llegó a terminar') 'atencion' 'El último mantenimiento no terminó: mira el registro y vuelve a lanzarlo.')))
    }
    $rows = New-Object System.Collections.ArrayList
    [void]$rows.Add((New-EmiHealthRow 'Optimizar ahora' ('Terminado el ' + (Format-EmiHealthDate $d.Time)) 'bien'))
    $num = {
        param([string] $Label, [string] $Key, [string] $Kind)
        if ($null -eq $a[$Key] -or $null -eq $d[$Key]) { return (New-EmiHealthRow $Label 'no disponible' $null) }
        $x = [double]$a[$Key]; $y = [double]$d[$Key]; $delta = $y - $x
        if ($Kind -eq 'bytes') {
            $txt = (Format-EmiHealthBytes $x) + ' → ' + (Format-EmiHealthBytes $y)
            $dt = if ($delta -ge 0) { '+' + (Format-EmiHealthBytes $delta) } else { Format-EmiHealthBytes $delta }
        } else {
            $txt = (Format-EmiHealthNumber $x 0) + ' → ' + (Format-EmiHealthNumber $y 0)
            $dt = if ($delta -gt 0) { '+' + (Format-EmiHealthNumber $delta 0) } elseif ($delta -lt 0) { '−' + (Format-EmiHealthNumber ([math]::Abs($delta)) 0) } else { 'sin cambios' }
        }
        return (New-EmiHealthRow $Label ($txt + ' (' + $dt + ')') $null)
    }
    [void]$rows.Add((& $num 'Espacio libre en discos fijos' 'FreeBytes' 'bytes'))
    [void]$rows.Add((& $num 'Programas al iniciar (activos)' 'StartupEnabled' 'n'))
    [void]$rows.Add((& $num 'Servicios desactivados' 'ServicesDisabled' 'n'))
    [void]$rows.Add((& $num 'Servicios en ejecución' 'ServicesRunning' 'n'))
    [void]$rows.Add((& $num 'Procesos abiertos' 'Processes' 'n'))
    [void]$rows.Add((& $num 'Cambios en el diario' 'Journal' 'n'))
    return (New-EmiHealthSection 'antesdespues' $title $rows.ToArray() -OkTodo 'Nada que hacer. Reinicia si aún no lo has hecho para que todo se aplique.' -Note 'Los procesos y servicios en ejecución cambian solos con el uso; la foto de después se toma justo al terminar, antes de reiniciar.')
}

function Get-EmiHealthSections {
    <#  De los datos en bruto a la lista de apartados con veredicto. #>
    param([Parameter(Mandatory)][hashtable] $Data, [datetime] $Now = (Get-Date), [bool] $WinSxSRequested = $false)
    $u = $Data.Unavailable; if (-not $u) { $u = @{} }
    return @(
        (Get-EmiHealthEquipo $Data.Equipo $Now)
        (Get-EmiHealthAlmacenamiento $Data.Almacenamiento $Data.WinSxS $WinSxSRequested ([string]$u['WinSxS']))
        (Get-EmiHealthBateria $Data.Bateria)
        (Get-EmiHealthEstabilidad $Data.Estabilidad)
        (Get-EmiHealthSeguridad $Data.Seguridad $Data.Actualizaciones $Now)
        (Get-EmiHealthArranque $Data.Arranque $Data.Programas)
        (Get-EmiHealthCambios $Data.Cambios)
        (Get-EmiHealthAntesDespues $Data.Instantanea)
    )
}

# ======================================================================
#                            3. HTML
# ======================================================================

function ConvertTo-EmiHtmlText {
    param($Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Get-EmiVerdictClass {
    param([string] $Verdict)
    if ($script:VerdictRank.ContainsKey($Verdict)) { return $Verdict }
    return 'nd'
}

# Colores de la interfaz (UI\MainWindow.xaml): cielo Frutiger Aero, tarjetas
# de cristal, tinta Deep/Ink/Muted y los brillos verde, ámbar y rojo.
$script:HealthCss = @'
:root{--deep:#07405E;--ink:#0B5C8A;--muted:#2C5F7E;--blue:#1F86C8;
--ok-bg:#E7F8D6;--ok-fg:#2D650F;--ok-br:#9BD46A;--warn-bg:#FFF1D2;--warn-fg:#7E4600;--warn-br:#F0B85A;
--bad-bg:#FFE3DC;--bad-fg:#982811;--bad-br:#EE8F77;--nd-bg:#E7EEF2;--nd-fg:#3F5A69;--nd-br:#B7C7D1}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;min-height:100vh;font-family:"Segoe UI",system-ui,-apple-system,"Helvetica Neue",Arial,sans-serif;color:var(--deep);
background:#9ed8f2 linear-gradient(160deg,#E3F4FD 0%,#95D9F6 30%,#4DBBEC 60%,#67D0C4 82%,#97DC5F 100%) fixed;line-height:1.45}
.wrap{max-width:1000px;margin:0 auto;padding:24px 16px 32px}
.card{background:linear-gradient(180deg,rgba(255,255,255,.93),rgba(255,255,255,.80) 45%,rgba(235,248,255,.74));
border:1px solid rgba(255,255,255,.75);border-radius:14px;box-shadow:0 2px 16px rgba(7,64,94,.18);padding:18px 20px;margin:0 0 14px}
.hero{position:relative;overflow:hidden}
.hero:before{content:"";position:absolute;left:0;right:0;top:0;height:46%;background:linear-gradient(180deg,rgba(255,255,255,.7),rgba(255,255,255,0));pointer-events:none}
.brand{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);font-weight:600}
h1{font-size:30px;font-weight:300;margin:2px 0 4px;color:var(--deep)}
h2{font-size:17px;font-weight:600;margin:0;color:var(--deep)}
.sub{color:var(--muted);font-size:13.5px;margin:0}
.tally{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
.chip{display:inline-flex;align-items:center;gap:6px;border-radius:999px;padding:3px 11px 3px 8px;font-size:12.5px;font-weight:600;border:1px solid;white-space:nowrap}
.chip:before{content:"";width:10px;height:10px;border-radius:50%;box-shadow:inset 0 1px 1px rgba(255,255,255,.8),0 0 0 1px rgba(0,0,0,.08)}
.bien.chip{background:var(--ok-bg);color:var(--ok-fg);border-color:var(--ok-br)}
.bien.chip:before{background:linear-gradient(180deg,#CBF08F,#74C23C 49%,#4E9C22 51%,#7FCF43)}
.atencion.chip{background:var(--warn-bg);color:var(--warn-fg);border-color:var(--warn-br)}
.atencion.chip:before{background:linear-gradient(180deg,#FFE6A8,#F0A93A 49%,#D5871B 51%,#F7B950)}
.mal.chip{background:var(--bad-bg);color:var(--bad-fg);border-color:var(--bad-br)}
.mal.chip:before{background:linear-gradient(180deg,#FFB6A6,#DD5C3E 49%,#B63B22 51%,#E0704F)}
.nd.chip{background:var(--nd-bg);color:var(--nd-fg);border-color:var(--nd-br)}
.nd.chip:before{background:linear-gradient(180deg,#F2F6F8,#C3D0D8 49%,#A9B9C3 51%,#C9D5DC)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;margin:0 0 14px}
.tile{display:block;text-decoration:none;color:inherit;margin:0;padding:14px 16px}
.tile:hover,.tile:focus{box-shadow:0 2px 20px rgba(7,64,94,.30);outline:none}
.tile h2{font-size:15px;margin-bottom:6px}
.tile p{margin:8px 0 0;font-size:12.5px;color:var(--muted)}
.head{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}
.todo{margin:10px 0 12px;padding:9px 12px;border-radius:10px;background:rgba(255,255,255,.66);border:1px solid rgba(31,134,200,.18);font-size:14px}
.todo b{color:var(--ink)}
.rows{width:100%;border-collapse:collapse;font-size:13.5px}
.rows th,.rows td{text-align:left;vertical-align:top;padding:8px 6px;border-top:1px solid rgba(11,92,138,.12)}
.rows th{font-weight:600;color:var(--deep);width:30%}
.rows td.v{color:#12324a;overflow-wrap:anywhere}
.rows td.s{width:1%;white-space:nowrap;text-align:right}
.note{font-size:12.5px;color:var(--muted);margin:10px 0 0}
.spark{margin:4px 0 6px}
.spark svg{width:100%;max-width:420px;height:auto;display:block}
.spark .cap{font-size:12px;color:var(--muted)}
footer{font-size:12.5px;color:var(--deep);text-align:center;padding:6px 10px 0;opacity:.9}
@media (max-width:620px){
 h1{font-size:25px}
 .card{padding:15px 14px}
 .rows,.rows tbody,.rows tr,.rows th,.rows td{display:block;width:auto}
 .rows tr{border-top:1px solid rgba(11,92,138,.14);padding:8px 0}
 .rows th,.rows td{border:0;padding:2px 0}
 .rows td.s{text-align:left;padding-top:4px}
}
@media print{
 body{background:#fff}
 .card{box-shadow:none;border:1px solid #c9d9e3;break-inside:avoid}
 .tile:hover{box-shadow:none}
}
'@

function Get-EmiVerdictLabel {
    param($Section)
    $c = Get-EmiVerdictClass $Section.Verdict
    if ($c -eq 'nd' -and $Section.NdLabel) { return [string]$Section.NdLabel }
    return $script:VerdictText[$c]
}

function ConvertTo-EmiHealthSpark {
    <#  Línea del índice de estabilidad (0-10) en SVG en línea: solo números. #>
    param([double[]] $Values)
    $vals = @($Values | ForEach-Object { [math]::Max(0, [math]::Min(10, [double]$_)) })
    if ($vals.Count -lt 2) { return '' }
    $w = 400.0; $h = 70.0; $pad = 4.0
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $pts = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $vals.Count; $i++) {
        $x = $pad + ($w - 2 * $pad) * $i / ($vals.Count - 1)
        $y = $pad + ($h - 2 * $pad) * (1 - $vals[$i] / 10)
        [void]$pts.Add($x.ToString('0.#', $inv) + ',' + $y.ToString('0.#', $inv))
    }
    $line = $pts -join ' '
    $area = ($pad.ToString($inv) + ',' + ($h - $pad).ToString($inv)) + ' ' + $line + ' ' + (($w - $pad).ToString($inv) + ',' + ($h - $pad).ToString($inv))
    $lx = $pts[$pts.Count - 1] -split ','
    $y7 = ($pad + ($h - 2 * $pad) * 0.3).ToString('0.#', $inv)
    return '<div class="spark"><svg viewBox="0 0 400 70" role="img" aria-label="Evolución del índice de estabilidad en los últimos 30 días">' +
        '<line x1="4" x2="396" y1="' + $y7 + '" y2="' + $y7 + '" stroke="#4CA22B" stroke-opacity=".45" stroke-dasharray="4 4"/>' +
        '<polygon points="' + $area + '" fill="#6FC7F0" fill-opacity=".28"/>' +
        '<polyline points="' + $line + '" fill="none" stroke="#1F86C8" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"/>' +
        '<circle cx="' + $lx[0] + '" cy="' + $lx[1] + '" r="3.6" fill="#0B5C8A"/></svg>' +
        '<div class="cap">Índice de estabilidad, últimos 30 días (0 a 10; la línea verde marca el 7).</div></div>'
}

function ConvertTo-EmiHealthHtml {
    <#  El informe completo como texto HTML. Todo valor pasa por HtmlEncode. #>
    param([Parameter(Mandatory)][object[]] $Sections, [string] $Computer = $env:COMPUTERNAME, [datetime] $Now = (Get-Date))
    $E = { param($t) ConvertTo-EmiHtmlText $t }
    $sb = New-Object System.Text.StringBuilder
    $title = 'Informe de salud · ' + $Computer
    [void]$sb.Append('<!DOCTYPE html>' + "`n" + '<html lang="es">' + "`n" + '<head>' + "`n" + '<meta charset="utf-8">' + "`n")
    [void]$sb.Append('<meta name="viewport" content="width=device-width, initial-scale=1">' + "`n")
    # Ni scripts, ni red: el informe no puede cargar nada aunque algo se colara
    [void]$sb.Append('<meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''; img-src data:; base-uri ''none''; form-action ''none''">' + "`n")
    [void]$sb.Append('<meta name="referrer" content="no-referrer">' + "`n")
    [void]$sb.Append('<title>' + (& $E $title) + '</title>' + "`n" + '<style>' + $script:HealthCss + '</style>' + "`n" + '</head>' + "`n" + '<body>' + "`n" + '<div class="wrap">' + "`n")

    $count = @{ bien = 0; atencion = 0; mal = 0; nd = 0 }
    foreach ($s in $Sections) { $count[(Get-EmiVerdictClass $s.Verdict)]++ }
    [void]$sb.Append('<header class="card hero">' + "`n" + '<div class="brand">Another&#39;s Toolbox</div>' + "`n")
    [void]$sb.Append('<h1>Informe de salud</h1>' + "`n")
    [void]$sb.Append('<p class="sub">Equipo <b>' + (& $E $Computer) + '</b> · ' + (& $E ($Now.ToString("dddd, d 'de' MMMM 'de' yyyy, HH:mm", $script:EsCulture))) + '</p>' + "`n")
    [void]$sb.Append('<div class="tally" aria-label="Resumen">')
    foreach ($k in 'bien', 'atencion', 'mal', 'nd') {
        [void]$sb.Append('<span class="chip ' + $k + '">' + [string]$count[$k] + ' ' + (& $E ($script:VerdictText[$k].ToLower())) + '</span>')
    }
    [void]$sb.Append('</div>' + "`n" + '</header>' + "`n")

    [void]$sb.Append('<nav class="grid" aria-label="Apartados">' + "`n")
    foreach ($s in $Sections) {
        $c = Get-EmiVerdictClass $s.Verdict
        $id = ([string]$s.Id) -replace '[^a-z0-9\-]', ''
        [void]$sb.Append('<a class="card tile" href="#' + $id + '"><h2>' + (& $E $s.Title) + '</h2><span class="chip ' + $c + '">' + (& $E (Get-EmiVerdictLabel $s)) + '</span><p>' + (& $E $s.Todo) + '</p></a>' + "`n")
    }
    [void]$sb.Append('</nav>' + "`n" + '<main>' + "`n")

    foreach ($s in $Sections) {
        $c = Get-EmiVerdictClass $s.Verdict
        $id = ([string]$s.Id) -replace '[^a-z0-9\-]', ''
        [void]$sb.Append('<section class="card" id="' + $id + '">' + "`n")
        [void]$sb.Append('<div class="head"><h2>' + (& $E $s.Title) + '</h2><span class="chip ' + $c + '">' + (& $E (Get-EmiVerdictLabel $s)) + '</span></div>' + "`n")
        [void]$sb.Append('<p class="todo"><b>Qué hacer:</b> ' + (& $E $s.Todo) + '</p>' + "`n")
        if ($s.Spark) { [void]$sb.Append((ConvertTo-EmiHealthSpark ([double[]]@($s.Spark))) + "`n") }
        [void]$sb.Append('<table class="rows"><tbody>' + "`n")
        foreach ($r in @($s.Rows)) {
            $st = ''
            if ($r.Verdict) { $rc = Get-EmiVerdictClass $r.Verdict; $st = '<span class="chip ' + $rc + '">' + (& $E $script:VerdictText[$rc]) + '</span>' }
            [void]$sb.Append('<tr><th scope="row">' + (& $E $r.Label) + '</th><td class="v">' + (& $E $r.Value) + '</td><td class="s">' + $st + '</td></tr>' + "`n")
        }
        [void]$sb.Append('</tbody></table>' + "`n")
        if ($s.Note) { [void]$sb.Append('<p class="note">' + (& $E $s.Note) + '</p>' + "`n") }
        [void]$sb.Append('</section>' + "`n")
    }
    [void]$sb.Append('</main>' + "`n" + '<footer>Informe de solo lectura: generarlo no cambia nada en el equipo. Se ha hecho sin conexión y sin enviar datos a nadie. ')
    [void]$sb.Append('Solo incluye el nombre del equipo: ni usuarios, ni rutas, ni números de serie.</footer>' + "`n")
    [void]$sb.Append('</div>' + "`n" + '</body>' + "`n" + '</html>' + "`n")
    return $sb.ToString()
}

# ======================================================================
#                     GUARDAR, COPIAR Y ABRIR
# ======================================================================

function Test-EmiHealthLinkFree {
    <#  $true si ninguna carpeta de la ruta es una unión o un enlace simbólico
        (un usuario podría plantar uno en su perfil para que el proceso de
        administrador escriba en otra parte). Los marcadores de OneDrive
        (archivos en la nube) no son enlaces y se aceptan. #>
    param([string] $Path)
    $p = $Path
    while ($p) {
        $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $it) { return $false }
        if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $lt = [string]$it.LinkType
            if ($lt -in 'Junction', 'SymbolicLink' -or ($lt -eq '' -and $it.PSObject.Properties['Target'] -and $it.Target)) { return $false }
        }
        $parent = Split-Path -Parent $p
        if (-not $parent -or $parent -eq $p) { break }
        $p = $parent
    }
    return $true
}

function Get-EmiHealthUserDocuments {
    <#  Carpeta Documentos del usuario que ve la ventana (aunque se elevara
        con otra cuenta de administrador). @{ Path; Same; Sid; Reason }.
        Path $null si no se puede saber con seguridad. #>
    $res = @{ Path = $null; Same = $false; Sid = $null; Reason = $null }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { $res.Reason = 'no es Windows'; return $res }
    try {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $user = $null
        if (Get-Command Get-EmiInteractiveUser -ErrorAction SilentlyContinue) { $user = Get-EmiInteractiveUser }
        if (-not $user) { $res.Reason = 'no hay una sesión de consola (¿escritorio remoto?)'; return $res }
        $sid = (New-Object Security.Principal.NTAccount($user)).Translate([Security.Principal.SecurityIdentifier]).Value
        $res.Sid = $sid
        $docs = $null
        if ($sid -eq $me) {
            $res.Same = $true
            $docs = [Environment]::GetFolderPath('MyDocuments')
        } else {
            $prof = (Get-ItemProperty -LiteralPath ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $sid) -ErrorAction Stop).ProfileImagePath
            $prof = [Environment]::ExpandEnvironmentVariables([string]$prof)
            $k = [Microsoft.Win32.Registry]::Users.OpenSubKey($sid + '\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders')
            if ($k) {
                try {
                    $raw = [string]$k.GetValue('Personal', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    if ($raw) {
                        # %USERPROFILE% es el del usuario, no el de esta cuenta
                        $raw = [regex]::Replace($raw, '%USERPROFILE%', [Text.RegularExpressions.MatchEvaluator] { param($m) $prof }, 'IgnoreCase')
                        if ($raw -notmatch '%') { $docs = $raw }
                    }
                } finally { $k.Close() }
            }
            if (-not $docs) {
                $k = [Microsoft.Win32.Registry]::Users.OpenSubKey($sid + '\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders')
                if ($k) { try { $docs = [string]$k.GetValue('Personal') } finally { $k.Close() } }
            }
            if (-not $docs -and $prof) { $docs = Join-Path $prof 'Documents' }
        }
        if (-not $docs -or -not [IO.Path]::IsPathRooted($docs) -or $docs.StartsWith('\\')) { $res.Reason = 'la carpeta Documentos no es local'; return $res }
        if (-not (Test-Path -LiteralPath $docs -PathType Container)) { $res.Reason = 'la carpeta Documentos no existe'; return $res }
        if (-not (Test-EmiHealthLinkFree $docs)) { $res.Reason = 'la ruta de Documentos pasa por un enlace o una unión'; return $res }
        $res.Path = $docs
    } catch { $res.Reason = $_.Exception.Message }
    return $res
}

function Write-EmiHealthUserCopy {
    <#  Copia del informe en Documentos del usuario, sin pisar nada:
        CreateNew falla si ya existe un archivo o un enlace con ese nombre. #>
    param([Parameter(Mandatory)][string] $Html, [Parameter(Mandatory)][string] $Dir, [Parameter(Mandatory)][string] $BaseName)
    $enc = New-Object System.Text.UTF8Encoding($false)
    $bytes = $enc.GetBytes($Html)
    for ($i = 0; $i -lt 20; $i++) {
        $name = if ($i -eq 0) { $BaseName + '.html' } else { $BaseName + ' (' + $i + ').html' }
        $path = Join-Path $Dir $name
        try {
            $fs = New-Object IO.FileStream($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
        } catch [System.IO.IOException] { continue }
        # Comprobar que se escribió donde tocaba (nadie cambió la carpeta por un enlace entre tanto)
        if (-not (Test-EmiHealthLinkFree $path)) { throw 'La carpeta Documentos cambió mientras se guardaba el informe.' }
        return $path
    }
    throw 'Ya hay demasiados informes con ese nombre en Documentos.'
}

function Open-EmiHealthReport {
    <#  Abre la copia del usuario en su navegador SIN elevar. Mismo mecanismo
        que Open-EmiUrl (explorer.exe le pasa el archivo al shell del usuario),
        que solo admite https:// a propósito; si la ventana se elevó con otra
        cuenta, Start-EmiUnelevated lo abre como el usuario de la consola.
        Nunca abre la copia de %ProgramData% (el navegador no podría leerla y
        no debe correr como administrador). #>
    param([Parameter(Mandatory)][string] $Path, [switch] $OtherUser)
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path -notmatch '\.html$' -or $Path.StartsWith('\\')) { throw "Ruta no admitida: $Path" }
    $pd = $env:ProgramData
    if ($pd -and $Path.StartsWith($pd, [StringComparison]::OrdinalIgnoreCase)) { throw 'La copia de ProgramData no se abre en el navegador.' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "No existe: $Path" }
    $isAdmin = $false
    if (Get-Command Test-EmiAdmin -ErrorAction SilentlyContinue) { $isAdmin = [bool](Test-EmiAdmin) }
    if (-not $isAdmin) { Start-Process -FilePath $Path -ErrorAction Stop; return }
    $explorer = Join-Path $env:SystemRoot 'explorer.exe'
    if ($OtherUser -and (Get-Command Start-EmiUnelevated -ErrorAction SilentlyContinue)) {
        [void](Start-EmiUnelevated -FilePath $explorer -Arguments ('"' + $Path + '"'))
    } else {
        Start-Process -FilePath $explorer -ArgumentList ('"' + $Path + '"') -ErrorAction Stop
    }
}

function New-EmiHealthReport {
    <#  Recoge, evalúa y guarda el informe.
          - %ProgramData%\EmiToolkit\informes\salud-<fecha>.html (solo administradores)
          - copia en Documentos del usuario de la consola, si se puede con seguridad
          - -Open: abre la copia del usuario sin elevar
        -Probes, -OutDir, -NoUserCopy y -Now son para pruebas.
        Devuelve @{ Path; UserCopy; UserCopyReason; Opened; Counts; Sections }. #>
    param(
        [switch] $IncludeWinSxS,
        [switch] $Open,
        [switch] $NoUserCopy,
        [hashtable] $Probes = @{},
        [string] $OutDir,
        [string] $Computer = $env:COMPUTERNAME,
        $Now
    )
    $result = @{ Path = $null; UserCopy = $null; UserCopyReason = $null; Opened = $false; Counts = $null; Sections = $null }
    if (-not $OutDir) { $OutDir = Get-EmiHealthDir }
    if (-not $OutDir) { throw 'No hay carpeta de datos para guardar el informe.' }
    if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

    Write-EmiHealthLog 'Informe de salud: recogiendo datos (solo lectura)...' Step
    $data = Get-EmiHealthData -IncludeWinSxS:$IncludeWinSxS -Probes $Probes -TempDir $OutDir
    if (-not $Now) { $Now = Get-Date }
    $sections = @(Get-EmiHealthSections -Data $data -Now ([datetime]$Now) -WinSxSRequested ([bool]$IncludeWinSxS))
    $html = ConvertTo-EmiHealthHtml -Sections $sections -Computer $Computer -Now ([datetime]$Now)

    $stamp = ([datetime]$Now).ToString('yyyy-MM-dd_HHmm')
    $path = Join-Path $OutDir ('salud-' + $stamp + '.html')
    [IO.File]::WriteAllText($path, $html, (New-Object System.Text.UTF8Encoding($false)))
    $result.Path = $path
    Write-EmiHealthLog ('Informe de salud guardado en ' + $path) Ok

    # Solo los 30 informes más recientes en ProgramData
    try {
        @(Get-ChildItem -LiteralPath $OutDir -Filter 'salud-*.html' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 30) |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    } catch { }

    $other = $false
    if (-not $NoUserCopy) {
        $docs = Get-EmiHealthUserDocuments
        if ($docs.Path) {
            try {
                $result.UserCopy = Write-EmiHealthUserCopy -Html $html -Dir $docs.Path -BaseName ('Informe de salud ' + $stamp)
                $other = -not $docs.Same
                Write-EmiHealthLog 'Informe de salud: copia guardada en Documentos del usuario.' Ok
            } catch { $result.UserCopyReason = $_.Exception.Message }
        } else { $result.UserCopyReason = $docs.Reason }
        if ($result.UserCopyReason) { Write-EmiHealthLog ('Informe de salud: sin copia en Documentos (' + $result.UserCopyReason + '); queda solo en ' + $OutDir + '.') Warn }
    }
    if ($Open -and $result.UserCopy) {
        try { Open-EmiHealthReport -Path $result.UserCopy -OtherUser:$other; $result.Opened = $true }
        catch { Write-EmiHealthLog ('Informe de salud: no se pudo abrir en el navegador: ' + $_.Exception.Message) Warn }
    }

    $counts = @{ bien = 0; atencion = 0; mal = 0; nd = 0 }
    foreach ($s in $sections) { $counts[(Get-EmiVerdictClass $s.Verdict)]++ }
    $result.Counts = $counts
    $result.Sections = $sections
    Set-EmiHealthStatus 'Informe de salud listo' 100
    return $result
}

Export-ModuleMember -Function *-Emi*
