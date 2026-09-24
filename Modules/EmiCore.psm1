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
    $script:Journal = Join-Path $dataDir 'undo-journal.json'

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

# --------------------- Diario reversible (undo) ----------------------

function Add-EmiJournalEntry {
    param([hashtable] $Entry)
    if (-not $script:Journal) { return }
    $Entry['Timestamp'] = (Get-Date).ToString('s')
    $all = @()
    if (Test-Path -LiteralPath $script:Journal) {
        try { $all = @(Get-Content -LiteralPath $script:Journal -Raw | ConvertFrom-Json) } catch { $all = @() }
    }
    $all += [pscustomobject]$Entry
    $all | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:Journal -Encoding UTF8
}

function Get-EmiJournal {
    if (-not $script:Journal -or -not (Test-Path -LiteralPath $script:Journal)) { return @() }
    try { return @(Get-Content -LiteralPath $script:Journal -Raw | ConvertFrom-Json) } catch { return @() }
}

function Clear-EmiJournal {
    if ($script:Journal -and (Test-Path -LiteralPath $script:Journal)) {
        Remove-Item -LiteralPath $script:Journal -Force -ErrorAction SilentlyContinue
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

function Undo-EmiChanges {
    <#  Revierte todo lo registrado en el diario. #>
    $entries = @(Get-EmiJournal)
    if ($entries.Count -eq 0) { Write-EmiLog 'No hay cambios que revertir.' Warn; return 0 }

    $n = 0
    # Se recorre al reves: lo ultimo aplicado se revierte primero
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        $e = $entries[$i]
        try {
            switch ($e.Kind) {
                'Registry' {
                    if ($e.Existed) {
                        $t = if ($e.OldType) { $e.OldType } else { 'String' }
                        if ($t -eq 'Unknown') { $t = 'String' }
                        $val = $e.OldValue
                        # El round-trip JSON convierte Binary/MultiString en array de enteros o strings
                        if ($t -eq 'Binary'   -and $val -isnot [byte[]]) { $val = [byte[]]@($val | ForEach-Object { [byte]$_ }) }
                        if ($t -eq 'MultiString' -and $val -isnot [array]) { $val = [string[]]@($val) }
                        if ($t -eq 'DWord' -and $val -is [long]) { $val = [int]($val -band 0xFFFFFFFF) }
                        New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value $val -PropertyType $t -Force -ErrorAction Stop | Out-Null
                    } else {
                        Remove-ItemProperty -LiteralPath $e.Path -Name $e.Name -Force -ErrorAction SilentlyContinue
                    }
                    $n++
                }
                'Service' {
                    $map = @{ 'Auto' = 'Automatic'; 'Automatic' = 'Automatic'; 'Manual' = 'Manual'; 'Disabled' = 'Disabled' }
                    $st  = $map[[string]$e.OldStartMode]
                    if ($st) { Set-Service -Name $e.Name -StartupType $st -ErrorAction SilentlyContinue }
                    if ($e.OldStatus -eq 'Running') { Start-Service -Name $e.Name -ErrorAction SilentlyContinue }
                    $n++
                }
                'Task' {
                    Enable-ScheduledTask -TaskPath $e.TaskPath -TaskName $e.TaskName -ErrorAction SilentlyContinue | Out-Null
                    $n++
                }
                'Firewall' {
                    Get-NetFirewallRule -DisplayName $e.RuleName -ErrorAction SilentlyContinue |
                        Remove-NetFirewallRule -ErrorAction SilentlyContinue
                    $n++
                }
                'File' {
                    if ($e.Backup -and (Test-Path -LiteralPath $e.Backup)) {
                        Copy-Item -LiteralPath $e.Backup -Destination $e.Path -Force -ErrorAction SilentlyContinue
                        $n++
                    }
                }
            }
        }
        catch { Write-EmiLog "Revertir '$($e.Kind)': $($_.Exception.Message)" Warn }
    }

    Clear-EmiJournal
    Write-EmiLog "Se revirtieron $n cambios." Ok
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
