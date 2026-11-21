# =====================================================================
#  EmiCore.psm1 - Nucleo compartido: log, diario reversible, helpers
# =====================================================================

$script:Root    = $null
$script:LogFile = $null
$script:Journal = $null

# ------------------------- Tipos para la UI --------------------------
if (-not ('EmiItem' -as [type])) {
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.ComponentModel;

public class EmiItem : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler PropertyChanged;
    private void Raise(string n)
    {
        PropertyChangedEventHandler h = PropertyChanged;
        if (h != null) h(this, new PropertyChangedEventArgs(n));
    }

    private bool _selected;
    public bool Selected { get { return _selected; } set { _selected = value; Raise("Selected"); } }

    private string _status = "";
    public string Status { get { return _status; } set { _status = value; Raise("Status"); } }

    private string _sizeText = "";
    public string SizeText { get { return _sizeText; } set { _sizeText = value; Raise("SizeText"); } }

    private long _size;
    public long Size { get { return _size; } set { _size = value; Raise("Size"); } }

    public string Name { get; set; }
    public string Detail { get; set; }
    public string Path { get; set; }
    public string Category { get; set; }
    public string Tag { get; set; }
    public string Icon { get; set; }
    public bool Recommended { get; set; }

    private bool _locked;
    public bool Locked { get { return _locked; } set { _locked = value; Raise("Locked"); Raise("Editable"); } }
    public bool Editable { get { return !_locked; } }
}
'@
}

if (-not ('EmiNative' -as [type])) {
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class EmiNative
{
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    [DllImport("dwmapi.dll")]
    public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS m);

    [StructLayout(LayoutKind.Sequential)]
    public struct MARGINS { public int L, R, T, B; }

    public const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
    public const int DWMWA_SYSTEMBACKDROP_TYPE     = 38;
    public const int DWMWA_MICA_EFFECT             = 1029; // builds 22000
}
'@
}

# --------------------------- Inicializacion --------------------------

function Initialize-EmiCore {
    param([Parameter(Mandatory)][string] $RootPath)

    $script:Root = $RootPath
    $dataDir = Join-Path $RootPath 'Data'
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

    $script:LogFile = Join-Path $dataDir ("EmiToolkit_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
    $script:Journal = Join-Path $dataDir 'undo-journal.jsonl'

    if (-not $global:EmiSync) {
        $global:EmiSync = [hashtable]::Synchronized(@{
            Log      = New-Object System.Collections.ArrayList
            Progress = 0
            Status   = 'Listo'
            Busy     = $false
            Result   = $null
        })
    }
}

function Get-EmiRoot { $script:Root }

# ------------------------------- Log ---------------------------------

function Write-EmiLog {
    param(
        [Parameter(Mandatory, Position = 0)][string] $Message,
        [Parameter(Position = 1)]
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step')][string] $Level = 'Info'
    )
    $stamp = Get-Date -Format 'HH:mm:ss'
    $line  = "[$stamp] $Message"

    if ($global:EmiSync) {
        [void]$global:EmiSync.Log.Add([pscustomobject]@{ Text = $line; Level = $Level })
    }
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value "[$stamp][$Level] $Message" -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    }
}

function Set-EmiStatus {
    param([string] $Text, [int] $Percent = -1)
    if ($global:EmiSync) {
        $global:EmiSync.Status = $Text
        if ($Percent -ge 0) { $global:EmiSync.Progress = $Percent }
    }
}

# ----------------------------- Utilidades ----------------------------

function Test-EmiAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-EmiSize {
    param([double] $Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Get-EmiFolderSize {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        $sum = 0
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $sum += $_.Length }
        return $sum
    } catch { return 0 }
}

function Split-EmiCommandLine {
    <#  Separa una linea de comandos de Windows en ejecutable y argumentos:
          '"C:\Program Files\X\Uninstall X.exe" /currentuser' -> ruta | /currentuser
          'MsiExec.exe /X{GUID}'                              -> MsiExec.exe | /X{GUID}
          'C:\Program Files\X\unins000.exe'                   -> ruta (con espacios) | '' #>
    param([Parameter(Mandatory)][string] $CommandLine)
    $s = $CommandLine.Trim()
    if ($s.StartsWith('"')) {
        $end = $s.IndexOf('"', 1)
        if ($end -gt 0) {
            return [pscustomobject]@{ FilePath = $s.Substring(1, $end - 1); Arguments = $s.Substring($end + 1).Trim() }
        }
        return [pscustomobject]@{ FilePath = $s.Trim('"'); Arguments = '' }
    }
    # Sin comillas la ruta puede llevar espacios: termina en el primer .exe
    $m = [regex]::Match($s, '^(.+?\.exe)(?:\s+(.*))?$', 'IgnoreCase')
    if ($m.Success) {
        return [pscustomobject]@{ FilePath = $m.Groups[1].Value; Arguments = $m.Groups[2].Value.Trim() }
    }
    $sp = $s.IndexOf(' ')
    if ($sp -gt 0) {
        return [pscustomobject]@{ FilePath = $s.Substring(0, $sp); Arguments = $s.Substring($sp + 1).Trim() }
    }
    return [pscustomobject]@{ FilePath = $s; Arguments = '' }
}

function Get-EmiUninstallCommand {
    <#  Ejecutable y argumentos para desinstalar en silencio una entrada de
        ...\Uninstall. Usa QuietUninstallString si existe; si no, separa
        UninstallString y anade el modo silencioso de cada instalador. #>
    param([string] $QuietUninstallString, [string] $UninstallString)
    if ($QuietUninstallString) { return Split-EmiCommandLine $QuietUninstallString }
    if (-not $UninstallString) { throw 'La entrada no tiene UninstallString.' }

    $c    = Split-EmiCommandLine $UninstallString
    $leaf = ($c.FilePath -split '[\\/]')[-1]
    if ($leaf -match '^msiexec(\.exe)?$') {
        # MSI: /I abre el asistente de mantenimiento; se pide /X y sin interfaz
        $a = $c.Arguments -replace '(?i)(^|\s)/I(?=\s*\{)', '$1/X'
        if ($a -notmatch '(?i)(^|\s)/q') { $a = ($a + ' /qn /norestart').Trim() }
        $c.Arguments = $a
    } elseif ($leaf -match '^unins\d+\.exe$') {
        # Inno Setup
        if ($c.Arguments -notmatch '(?i)/(very)?silent') { $c.Arguments = ($c.Arguments + ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART').Trim() }
    } else {
        # NSIS (electron-builder escribe '"...\Uninstall X.exe" /currentuser')
        if ($c.Arguments -notmatch '(?i)(^|\s)/S(\s|$)') { $c.Arguments = ($c.Arguments + ' /S').Trim() }
    }
    return $c
}

# --------------------- Diario reversible (undo) ----------------------
# El diario es un archivo JSON Lines (Data\undo-journal.jsonl): una entrada
# por linea, y cada cambio solo anade una linea al final. Antes era un array
# JSON que se releia y reescribia entero; en PowerShell 5.1 ConvertFrom-Json
# devuelve ese array como un unico objeto, @() lo envolvia y += lo metia
# dentro, asi que el diario se anidaba en cada escritura y, pasada la
# profundidad de ConvertTo-Json, las entradas viejas se perdian. El archivo
# antiguo (Data\undo-journal.json) se sigue leyendo, aplanado, y se retira
# cuando Undo-EmiChanges termina.

$script:JournalUtf8 = New-Object System.Text.UTF8Encoding($false)
$script:JournalLost = 0

function Get-EmiLegacyJournalPath {
    if (-not $script:Journal) { return $null }
    return [System.IO.Path]::ChangeExtension($script:Journal, '.json')
}

function ConvertFrom-EmiLegacyJournal {
    <#  Aplana el diario antiguo, que en PowerShell 5.1 quedaba asi:
            [ { "value": [ { "value": [...], "Count": 2 }, e3 ], "Count": 2 }, e4 ]
        Devuelve las entradas de la mas antigua a la mas reciente. Las que
        ConvertTo-Json trunco a texto (" ") ya no existen: se suman a $Lost. #>
    param($Node, [ref] $Lost, [int] $Level = 0)
    if ($null -eq $Node -or $Level -gt 200) { return }
    if ($Node -is [string]) { $Lost.Value++; return }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [System.Collections.IDictionary]) {
        foreach ($x in $Node) { ConvertFrom-EmiLegacyJournal $x $Lost ($Level + 1) }
        return
    }
    $names = @($Node.PSObject.Properties | ForEach-Object { $_.Name })
    if ($names -contains 'Kind') { return $Node }
    if ($names -contains 'value') { ConvertFrom-EmiLegacyJournal $Node.value $Lost ($Level + 1); return }
    $Lost.Value++
}

function Add-EmiJournalEntry {
    param([hashtable] $Entry)
    if (-not $script:Journal) { return }
    $Entry['Timestamp'] = (Get-Date).ToString('s')
    $line = ConvertTo-Json -InputObject ([pscustomobject]$Entry) -Depth 8 -Compress
    [System.IO.File]::AppendAllText($script:Journal, $line + "`r`n", $script:JournalUtf8)
}

function Get-EmiJournal {
    <#  Entradas del diario en orden de aplicacion (la mas antigua primero).
        Deja en $script:JournalLost cuantas entradas antiguas no se pudieron leer. #>
    $script:JournalLost = 0
    if (-not $script:Journal) { return @() }
    $lost    = 0
    $entries = New-Object System.Collections.ArrayList

    $legacy = Get-EmiLegacyJournalPath
    if ($legacy -and (Test-Path -LiteralPath $legacy)) {
        try {
            $text = [System.IO.File]::ReadAllText($legacy)
            if ($text.Trim()) {
                # Sin canalizacion: asi PowerShell 5.1 y 7 entregan lo mismo
                $parsed = ConvertFrom-Json -InputObject $text
                foreach ($e in @(ConvertFrom-EmiLegacyJournal $parsed ([ref]$lost))) { [void]$entries.Add($e) }
            }
        } catch { $lost++ }
    }

    if (Test-Path -LiteralPath $script:Journal) {
        foreach ($line in [System.IO.File]::ReadAllLines($script:Journal, $script:JournalUtf8)) {
            if (-not $line.Trim()) { continue }
            # Una linea a medias (corte de luz mientras se escribia) no tumba el resto
            try { [void]$entries.Add((ConvertFrom-Json -InputObject $line)) } catch { $lost++ }
        }
    }

    $script:JournalLost = $lost
    return $entries.ToArray()
}

function Get-EmiJournalLostCount { return [int]$script:JournalLost }

function Set-EmiJournalContent {
    <#  Reescribe el diario con las entradas dadas (las que quedan por revertir)
        y retira el diario antiguo, cuyas entradas ya van incluidas. #>
    param([object[]] $Entries = @())
    if (-not $script:Journal) { return }
    if (-not $Entries -or $Entries.Count -eq 0) { Clear-EmiJournal; return }

    $sb = New-Object System.Text.StringBuilder
    foreach ($e in $Entries) { [void]$sb.Append((ConvertTo-Json -InputObject $e -Depth 8 -Compress) + "`r`n") }
    $tmp = $script:Journal + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $sb.ToString(), $script:JournalUtf8)
    Move-Item -LiteralPath $tmp -Destination $script:Journal -Force -ErrorAction Stop

    $legacy = Get-EmiLegacyJournalPath
    if ($legacy -and (Test-Path -LiteralPath $legacy)) {
        Remove-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue
    }
}

function Clear-EmiJournal {
    foreach ($f in @($script:Journal, (Get-EmiLegacyJournalPath))) {
        if ($f -and (Test-Path -LiteralPath $f)) {
            Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------- Registro con undo -------------------------

function Set-EmiRegistry {
    <#  Escribe un valor guardando el estado anterior en el diario. #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')]
        [string] $Type = 'DWord',
        [string] $Module = 'General'
    )

    try {
        $existed  = $false
        $oldValue = $null
        $oldType  = $null

        if (Test-Path -LiteralPath $Path) {
            $prop = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $prop -and $prop.PSObject.Properties.Name -contains $Name) {
                $existed  = $true
                $oldValue = $prop.$Name
                try {
                    $key = Get-Item -LiteralPath $Path
                    $oldType = $key.GetValueKind($Name).ToString()
                } catch { $oldType = $Type }
            }
        } else {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        if ($existed -and ("$oldValue" -eq "$Value")) { return $false }   # ya estaba

        Add-EmiJournalEntry @{
            Kind    = 'Registry'
            Path    = $Path
            Name    = $Name
            Existed = $existed
            OldValue = $oldValue
            OldType  = $oldType
            NewValue = $Value
            Module   = $Module
        }

        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-EmiLog "No se pudo escribir $Path\$Name : $($_.Exception.Message)" Warn
        return $false
    }
}

function Set-EmiService {
    <#  Detiene y cambia el arranque de un servicio, guardando el estado. #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [ValidateSet('Disabled', 'Manual', 'Automatic')][string] $StartupType = 'Disabled',
        [switch] $Stop,
        [string] $Module = 'General'
    )

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $false }

    try {
        $wmi = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
        $old = if ($wmi) { $wmi.StartMode } else { 'Unknown' }

        Add-EmiJournalEntry @{
            Kind = 'Service'; Name = $Name; OldStartMode = $old
            OldStatus = $svc.Status.ToString(); Module = $Module
        }

        if ($Stop -and $svc.Status -eq 'Running') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        return $true
    }
    catch {
        Write-EmiLog "Servicio '$Name': $($_.Exception.Message)" Warn
        return $false
    }
}

function Disable-EmiScheduledTask {
    param([Parameter(Mandatory)][string] $TaskPath, [Parameter(Mandatory)][string] $TaskName, [string] $Module = 'General')
    try {
        $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $t) { return $false }
        if ($t.State -eq 'Disabled') { return $false }

        Add-EmiJournalEntry @{ Kind = 'Task'; TaskPath = $TaskPath; TaskName = $TaskName; Module = $Module }
        Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
}

function ConvertTo-EmiUndoCommand {
    <#  Las entradas 'Command' guardan datos (Action + parametros), nunca codigo.
        Las entradas antiguas traian el codigo en 'Undo'; aqui se traducen a una
        accion conocida y ese texto no se ejecuta jamas. #>
    param($Entry)
    if ($Entry.Action) { return $Entry }
    $undo = [string]$Entry.Undo
    if ($Entry.PackageName) {
        return [pscustomobject]@{ Kind = 'Command'; Action = 'AppxReinstall'; PackageName = [string]$Entry.PackageName }
    }
    if ($undo -match 'powercfg\s+/hibernate\s+on') {
        return [pscustomobject]@{ Kind = 'Command'; Action = 'Hibernate' }
    }
    if ($undo -match 'SetEnvironmentVariable') {
        $vars = @([regex]::Matches($undo, "SetEnvironmentVariable\('([A-Z0-9_]+)'") |
                  ForEach-Object { [pscustomobject]@{ Name = $_.Groups[1].Value; OldValue = $null } })
        return [pscustomobject]@{ Kind = 'Command'; Action = 'EnvVars'; Scope = 'User'; Variables = $vars }
    }
    $hint = if ($undo -match "Write-EmiLog '([^']+)'") { $Matches[1] } else { 'sin instrucciones' }
    return [pscustomobject]@{ Kind = 'Command'; Action = 'Manual'; Hint = $hint }
}

function Invoke-EmiUndoEntry {
    <#  Revierte una entrada. Devuelve:
          'Reverted'     se deshizo;
          'Failed'       no se pudo ahora (se queda en el diario para reintentar);
          'Irreversible' la entrada no guarda con que deshacerla (se avisa y se retira). #>
    param([Parameter(Mandatory)] $e)

    switch ([string]$e.Kind) {
        'Registry' {
            if ($e.Name -eq '(clave completa)') {
                Write-EmiLog "No se puede restaurar la clave borrada $($e.Path): el diario no guarda su contenido." Warn
                return 'Irreversible'
            }
            if ($e.Existed) {
                $t = if ($e.OldType) { [string]$e.OldType } else { 'String' }
                if ($t -eq 'Unknown') { $t = 'String' }
                $val = $e.OldValue
                # El round-trip JSON convierte Binary/MultiString en array de enteros o strings
                if ($t -eq 'Binary'   -and $val -isnot [byte[]]) { $val = [byte[]]@($val | ForEach-Object { [byte]$_ }) }
                if ($t -eq 'MultiString' -and $val -isnot [array]) { $val = [string[]]@($val) }
                if ($t -eq 'DWord' -and $val -is [long]) { $val = [int]($val -band 0xFFFFFFFF) }
                if (-not (Test-Path -LiteralPath $e.Path)) { New-Item -Path $e.Path -Force -ErrorAction Stop | Out-Null }
                New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value $val -PropertyType $t -Force -ErrorAction Stop | Out-Null
            } elseif (Test-Path -LiteralPath $e.Path) {
                Remove-ItemProperty -LiteralPath $e.Path -Name $e.Name -Force -ErrorAction SilentlyContinue
            }
            return 'Reverted'
        }
        'Service' {
            $map = @{ 'Auto' = 'Automatic'; 'Automatic' = 'Automatic'; 'Manual' = 'Manual'; 'Disabled' = 'Disabled' }
            $st  = $map[[string]$e.OldStartMode]
            if (-not $st -and $e.OldStatus -ne 'Running') {
                Write-EmiLog "Servicio '$($e.Name)': no se sabe como arrancaba antes ($($e.OldStartMode))." Warn
                return 'Irreversible'
            }
            if ($st) { Set-Service -Name $e.Name -StartupType $st -ErrorAction Stop }
            if ($e.OldStatus -eq 'Running') { Start-Service -Name $e.Name -ErrorAction Stop }
            return 'Reverted'
        }
        'Task' {
            $t = Get-ScheduledTask -TaskPath $e.TaskPath -TaskName $e.TaskName -ErrorAction SilentlyContinue
            if (-not $t) {
                Write-EmiLog "La tarea $($e.TaskPath)$($e.TaskName) ya no existe en este equipo." Warn
                return 'Irreversible'
            }
            Enable-ScheduledTask -TaskPath $e.TaskPath -TaskName $e.TaskName -ErrorAction Stop | Out-Null
            return 'Reverted'
        }
        'Firewall' {
            $rules = @(Get-NetFirewallRule -DisplayName $e.RuleName -ErrorAction SilentlyContinue)
            if ($rules.Count -gt 0) { $rules | Remove-NetFirewallRule -ErrorAction Stop }
            return 'Reverted'
        }
        'File' {
            if (-not $e.Backup) {
                Write-EmiLog "No hay copia de $($e.Path): se borro sin respaldo y no se puede restaurar." Warn
                return 'Irreversible'
            }
            if (-not (Test-Path -LiteralPath $e.Backup)) {
                Write-EmiLog "Falta la copia $($e.Backup); no se puede restaurar $($e.Path)." Warn
                return 'Irreversible'
            }
            Copy-Item -LiteralPath $e.Backup -Destination $e.Path -Force -ErrorAction Stop
            return 'Reverted'
        }
        'Command' {
            $c = ConvertTo-EmiUndoCommand $e
            switch ([string]$c.Action) {
                'AppxReinstall' {
                    # Solo se puede volver a registrar si el paquete sigue en disco
                    # (instalado para otro usuario o aun en WindowsApps).
                    $src = Get-AppxPackage -AllUsers -Name $c.PackageName -ErrorAction SilentlyContinue |
                           Where-Object { -not $_.IsFramework -and $_.InstallLocation -and
                                          (Test-Path -LiteralPath (Join-Path $_.InstallLocation 'AppxManifest.xml')) } |
                           Select-Object -First 1
                    if (-not $src) {
                        Write-EmiLog "$($c.PackageName) ya no esta en el equipo; reinstalala desde Microsoft Store (ms-windows-store://search/?query=$($c.PackageName))." Warn
                        return 'Failed'
                    }
                    Add-AppxPackage -Register (Join-Path $src.InstallLocation 'AppxManifest.xml') -DisableDevelopmentMode -ErrorAction Stop
                    return 'Reverted'
                }
                'WindowsFeature' {
                    if ($c.OldState -in @('Enabled', 'EnablePending')) {
                        Enable-WindowsOptionalFeature -Online -FeatureName $c.Feature -NoRestart -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                    } else {
                        Disable-WindowsOptionalFeature -Online -FeatureName $c.Feature -NoRestart -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                    }
                    return 'Reverted'
                }
                'Hibernate' {
                    & powercfg.exe /hibernate on 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { Write-EmiLog "powercfg /hibernate on devolvio $LASTEXITCODE." Warn; return 'Failed' }
                    return 'Reverted'
                }
                'EnvVars' {
                    $scope = if ($c.Scope) { [string]$c.Scope } else { 'User' }
                    foreach ($v in @($c.Variables)) {
                        [System.Environment]::SetEnvironmentVariable([string]$v.Name, $v.OldValue, $scope)
                    }
                    return 'Reverted'
                }
                'Manual' {
                    Write-EmiLog "Revertir a mano: $($c.Hint)" Warn
                    return 'Irreversible'
                }
                default {
                    Write-EmiLog "Accion de deshacer desconocida: '$($c.Action)'." Warn
                    return 'Failed'
                }
            }
        }
        default {
            Write-EmiLog "Tipo de cambio desconocido en el diario: '$($e.Kind)'." Warn
            return 'Failed'
        }
    }
}

function Undo-EmiChanges {
    <#  Revierte lo registrado en el diario, de lo mas reciente a lo mas antiguo.
        Lo que no se pudo revertir se queda en el diario para el siguiente intento. #>
    $entries = @(Get-EmiJournal)
    $lost    = Get-EmiJournalLostCount
    if ($lost -gt 0) {
        Write-EmiLog "$lost entradas antiguas del diario estaban danadas y no se pueden revertir." Warn
    }
    if ($entries.Count -eq 0) {
        if ($lost -gt 0) { Clear-EmiJournal } else { Write-EmiLog 'No hay cambios que revertir.' Warn }
        return 0
    }

    $n = 0; $skipped = 0
    $pending = New-Object System.Collections.ArrayList
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        $e = $entries[$i]
        $r = 'Failed'
        try { $r = [string](Invoke-EmiUndoEntry $e | Select-Object -Last 1) }
        catch { Write-EmiLog "Revertir '$($e.Kind)': $($_.Exception.Message)" Warn; $r = 'Failed' }
        switch ($r) {
            'Reverted'     { $n++ }
            'Irreversible' { $skipped++ }
            default        { [void]$pending.Insert(0, $e) }   # conserva el orden original
        }
    }

    try { Set-EmiJournalContent -Entries $pending.ToArray() }
    catch { Write-EmiLog "No se pudo actualizar el diario: $($_.Exception.Message)" Error }

    Write-EmiLog "Se revirtieron $n cambios." Ok
    if ($skipped -gt 0) { Write-EmiLog "$skipped cambios no se pueden deshacer automaticamente (ver avisos)." Warn }
    if ($pending.Count -gt 0) { Write-EmiLog "$($pending.Count) cambios no se pudieron revertir y siguen en el diario para reintentarlo." Warn }
    return $n
}

# --------------------------- Punto de restauracion -------------------

function New-EmiRestorePoint {
    param([string] $Description = 'EmiToolkit - antes de optimizar')
    try {
        Set-EmiStatus 'Creando punto de restauracion...'
        Write-EmiLog 'Creando punto de restauracion del sistema...' Step

        # Windows limita a 1 punto cada 24h; se desactiva ese limite temporalmente
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
                         -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-EmiLog 'Punto de restauracion creado.' Ok
        return $true
    }
    catch {
        Write-EmiLog "No se pudo crear el punto de restauracion: $($_.Exception.Message)" Warn
        return $false
    }
}

# ------------------------------ Ventana ------------------------------

function Enable-EmiBackdrop {
    <#  Aplica el fondo translucido nativo de Windows 11 (Acrylic / Mica). #>
    param([Parameter(Mandatory)][IntPtr] $Handle, [ValidateSet('Acrylic', 'Mica')][string] $Style = 'Acrylic')
    try {
        $dark = 0
        [void][EmiNative]::DwmSetWindowAttribute($Handle, [EmiNative]::DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$dark, 4)

        $m = New-Object EmiNative+MARGINS
        $m.L = -1; $m.R = -1; $m.T = -1; $m.B = -1
        [void][EmiNative]::DwmExtendFrameIntoClientArea($Handle, [ref]$m)

        # 2 = Mica, 3 = Acrylic (transparencia), 4 = Mica Alt
        $type = 3
        if ($Style -eq 'Mica') { $type = 2 }
        $r = [EmiNative]::DwmSetWindowAttribute($Handle, [EmiNative]::DWMWA_SYSTEMBACKDROP_TYPE, [ref]$type, 4)

        if ($r -ne 0) {
            $one = 1
            [void][EmiNative]::DwmSetWindowAttribute($Handle, [EmiNative]::DWMWA_MICA_EFFECT, [ref]$one, 4)
        }
        return $true
    }
    catch { return $false }
}

Export-ModuleMember -Function *-Emi*, Format-EmiSize, Test-EmiAdmin, Get-EmiRoot, Initialize-EmiCore
