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

# Los datos de la maquina (diario de deshacer, copia de hosts y logs) ya no
# viven en <carpeta de la app>\Data: esa carpeta suele ser escribible por
# usuarios sin privilegios (C:\EmiToolkit, Descargas, OneDrive) y el proceso
# elevado obedecia lo que hubiera en el diario. Ahora:
#   - elevado:    %ProgramData%\EmiToolkit, ACL solo Administradores + SYSTEM,
#                 protegida frente a herencia;
#   - sin elevar: %LOCALAPPDATA%\EmiToolkit (solo afecta a ese usuario).
# Lo que hubiera en el Data antiguo se migra una vez, validando cada entrada.

$script:DataDir   = $null
$script:OldData   = $null
$script:SidAdmins = 'S-1-5-32-544'
$script:SidSystem = 'S-1-5-18'
# SID que pueden escribir sin que eso sea un riesgo: SYSTEM, Administradores,
# TrustedInstaller y CREATOR OWNER (solo se hereda a lo que crea quien ya podia).
$script:TrustedSids = @(
    'S-1-5-18', 'S-1-5-32-544', 'S-1-3-0',
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
)

function Test-EmiWindows { return ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) }

function Get-EmiUntrustedWriters {
    <#  Devuelve los SID (no administradores) que pueden modificar $Path:
        ACE Allow con derechos de escritura, borrado o cambio de ACL/propietario,
        o un propietario que no es de confianza (el propietario reescribe la DACL).
        Si no se puede leer la ACL, devuelve '?' (se trata como no fiable). #>
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-EmiWindows)) { return @() }
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $out = New-Object System.Collections.ArrayList
        # WriteData|AppendData|WriteEA|DeleteChild|WriteAttributes|Delete|WriteDac|WriteOwner|GenericAll|GenericWrite
        $mask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
        $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($script:TrustedSids -notcontains $owner) { [void]$out.Add($owner) }
        foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($r.AccessControlType -ne 'Allow') { continue }
            if (($r.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0) { continue }
            $sid = $r.IdentityReference.Value
            if ($script:TrustedSids -contains $sid) { continue }
            if (([int64]$r.FileSystemRights -band $mask) -ne 0 -and -not $out.Contains($sid)) { [void]$out.Add($sid) }
        }
        return $out.ToArray()
    } catch { return @('?') }
}

function Set-EmiAdminOnlyAcl {
    <#  ACL explicita y protegida: Administradores y SYSTEM con control total,
        propietario Administradores. Nada heredado de la carpeta padre. #>
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-EmiWindows)) { return $true }
    try {
        $isDir = Test-Path -LiteralPath $Path -PathType Container
        $sec = if ($isDir) { New-Object System.Security.AccessControl.DirectorySecurity } else { New-Object System.Security.AccessControl.FileSecurity }
        $sec.SetAccessRuleProtection($true, $false)
        $inh = if ($isDir) { [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit' } else { [Security.AccessControl.InheritanceFlags]::None }
        foreach ($s in @($script:SidAdmins, $script:SidSystem)) {
            $sid = New-Object Security.Principal.SecurityIdentifier($s)
            $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', $inh, 'None', 'Allow')))
        }
        $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier($script:SidAdmins)))
        Set-Acl -LiteralPath $Path -AclObject $sec -ErrorAction Stop
        return $true
    } catch {
        Write-EmiLog "No se pudo proteger la ACL de $Path : $($_.Exception.Message)" Warn
        return $false
    }
}

function Initialize-EmiDataDir {
    <#  Crea (o repara) la carpeta de datos protegida. Si ya existia y alguien
        sin privilegios podia escribir en ella, su contenido no es de fiar: se
        aparta con la extension .no-fiable y no se usa. #>
    param([string] $Path)
    $isWin = Test-EmiWindows
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        # Una union o enlace plantado redirigiria el diario a otra carpeta: se
        # borra el enlace (no su destino) y se crea una carpeta de verdad.
        [IO.Directory]::Delete($Path, $false)
        $item = $null
    }
    if (-not $item) {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        [void](Set-EmiAdminOnlyAcl $Path)
        return
    }
    if (-not $isWin) { return }
    $bad = @(Get-EmiUntrustedWriters $Path)
    if ($bad.Count -gt 0) {
        [void](Set-EmiAdminOnlyAcl $Path)
        $stamp = Get-Date -Format 'yyyyMMddHHmmss'
        foreach ($f in @(Get-ChildItem -LiteralPath $Path -Force -File -ErrorAction SilentlyContinue)) {
            try { Rename-Item -LiteralPath $f.FullName -NewName ($f.Name + ".no-fiable-$stamp") -ErrorAction Stop } catch { }
        }
        $script:DataWarning = "La carpeta $Path permitia escribir a usuarios sin privilegios ($($bad -join ', ')). Se ha protegido y su contenido anterior se ha apartado (.no-fiable)."
        return
    }
    # Carpeta correcta: un archivo con ACE explicita de un no administrador se aparta
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Force -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -like '*.no-fiable-*') { continue }
        if (@(Get-EmiUntrustedWriters $f.FullName).Count -gt 0 -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            try { Rename-Item -LiteralPath $f.FullName -NewName ($f.Name + '.no-fiable-' + (Get-Date -Format 'yyyyMMddHHmmss')) -ErrorAction Stop } catch { }
        }
    }
}

function Initialize-EmiCore {
    <#  -DataPath solo para pruebas: fuerza la carpeta de datos. #>
    param([Parameter(Mandatory)][string] $RootPath, [string] $DataPath)

    $script:Root    = $RootPath
    $script:OldData = Join-Path $RootPath 'Data'
    $script:DataWarning = $null

    if ($DataPath) {
        $dataDir = $DataPath
        if (-not (Test-Path -LiteralPath $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
    } elseif ((Test-EmiWindows) -and (Test-EmiAdmin)) {
        $dataDir = Join-Path $env:ProgramData 'EmiToolkit'
        try { Initialize-EmiDataDir $dataDir }
        catch { $script:DataWarning = "No se pudo preparar $dataDir : $($_.Exception.Message)" }
    } else {
        $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [Environment]::GetFolderPath('LocalApplicationData') }
        $dataDir = Join-Path $base 'EmiToolkit'
        if (-not (Test-Path -LiteralPath $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
    }
    $script:DataDir = $dataDir
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
    if ($script:DataWarning) { Write-EmiLog $script:DataWarning Warn }
    try { Import-EmiLegacyData }
    catch { Write-EmiLog "No se pudieron migrar los datos antiguos de $($script:OldData): $($_.Exception.Message)" Warn }
}

function Get-EmiRoot { $script:Root }

function Get-EmiDataDir { $script:DataDir }

function Get-EmiHostsBackupPath { Join-Path $script:DataDir 'hosts.backup' }

function Get-EmiHostsPath { Join-Path $env:SystemRoot 'System32\drivers\etc\hosts' }

function Test-EmiHostsContent {
    <#  Una copia de hosts valida: texto pequeno, sin NUL, y cada linea util
        es "IP nombre [nombres...] [# comentario]". No es un archivo cualquiera. #>
    param([Parameter(Mandatory)][string] $Path)
    try {
        $fi = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($fi.PSIsContainer -or ($fi.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
        if ($fi.Length -gt 1MB) { return $false }
        $text = [IO.File]::ReadAllText($fi.FullName)
        if ($text.Contains([char]0)) { return $false }
        foreach ($l in ($text -split "`r?`n")) {
            $t = $l.Trim()
            if (-not $t -or $t.StartsWith('#')) { continue }
            if ($t -notmatch '^[0-9A-Fa-f:.%]+\s+[A-Za-z0-9._\-]+(\s+[A-Za-z0-9._\-]+)*\s*(#.*)?$') { return $false }
        }
        return $true
    } catch { return $false }
}

function Import-EmiLegacyData {
    <#  Migra una sola vez lo que hubiera en <app>\Data (diario, copia de hosts y
        logs) a la carpeta protegida. Cada entrada del diario pasa por las mismas
        listas permitidas que el deshacer; lo que no pasa no se migra. Los
        originales se renombran a *.migrado para no volver a leerlos. #>
    $old = $script:OldData
    if (-not $old -or -not $script:DataDir -or -not (Test-Path -LiteralPath $old -PathType Container)) { return }
    if ([IO.Path]::GetFullPath($old).TrimEnd('\', '/') -eq [IO.Path]::GetFullPath($script:DataDir).TrimEnd('\', '/')) { return }

    # 1. Copia de hosts (antes que el diario: sus entradas File apuntan a ella)
    $oldHosts = Join-Path $old 'hosts.backup'
    $newHosts = Get-EmiHostsBackupPath
    if (Test-Path -LiteralPath $oldHosts) {
        if (-not (Test-Path -LiteralPath $newHosts) -and (Test-EmiHostsContent $oldHosts)) {
            Copy-Item -LiteralPath $oldHosts -Destination $newHosts -Force
            Write-EmiLog "Copia de hosts migrada a $($script:DataDir)." Info
        } elseif (-not (Test-Path -LiteralPath $newHosts)) {
            Write-EmiLog "La copia de hosts antigua ($oldHosts) no parece un archivo hosts: no se migra." Warn
        }
        try { Rename-Item -LiteralPath $oldHosts -NewName 'hosts.backup.migrado' -ErrorAction Stop } catch { }
    }

    # 2. Diario
    $oldFiles = @('undo-journal.jsonl', 'undo-journal.json' | ForEach-Object { Join-Path $old $_ } |
                  Where-Object { Test-Path -LiteralPath $_ })
    if ($oldFiles.Count -gt 0) {
        $saved = $script:Journal
        $script:Journal = Join-Path $old 'undo-journal.jsonl'
        $entries = @(Get-EmiJournal)
        $lost = Get-EmiJournalLostCount
        $script:Journal = $saved

        $ok = 0; $bad = 0
        $oldBackup = [IO.Path]::GetFullPath($oldHosts)
        foreach ($e in $entries) {
            if ([string]$e.Kind -eq 'File' -and $e.Backup -and
                [IO.Path]::GetFullPath([string]$e.Backup) -eq $oldBackup) { $e.Backup = $newHosts }
            if (-not ($e.PSObject.Properties.Name -contains 'Computer')) {
                # Las entradas antiguas no guardaban el equipo: se asume este,
                # pero solo si superan las listas permitidas.
                $e | Add-Member -NotePropertyName Computer -NotePropertyValue $env:COMPUTERNAME -Force
            }
            $why = Test-EmiUndoEntry $e
            if ($why) { $bad++; Write-EmiLog "Migracion del diario: entrada rechazada ($why)." Warn; continue }
            $line = ConvertTo-Json -InputObject $e -Depth 8 -Compress
            [IO.File]::AppendAllText($script:Journal, $line + "`r`n", $script:JournalUtf8)
            $ok++
        }
        foreach ($f in $oldFiles) {
            try { Rename-Item -LiteralPath $f -NewName ((Split-Path $f -Leaf) + '.migrado') -ErrorAction Stop } catch { }
        }
        Write-EmiLog "Diario antiguo migrado a $($script:DataDir): $ok entradas validas, $bad rechazadas, $lost ilegibles." $(if ($bad -or $lost) { 'Warn' } else { 'Info' })
    }

    # 3. Logs (pueden llevar nombres de equipo y usuario: fuera de la carpeta portable)
    foreach ($f in @(Get-ChildItem -LiteralPath $old -Filter '*.log' -File -Force -ErrorAction SilentlyContinue)) {
        $dst = Join-Path $script:DataDir $f.Name
        try {
            if (Test-Path -LiteralPath $dst) {
                [IO.File]::AppendAllText($dst, [IO.File]::ReadAllText($f.FullName))
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            } else { Move-Item -LiteralPath $f.FullName -Destination $dst -Force -ErrorAction Stop }
        } catch { }
    }
}

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

# ---------------- Ejecutables de confianza y procesos sin elevar -----
# Este proceso es administrador: todo lo que lanza hereda ese token. Un .exe
# de %LOCALAPPDATA%, %APPDATA% o Descargas lo puede sustituir cualquier
# programa del usuario, asi que nunca se ejecuta elevado.

function Test-EmiTrustedLocation {
    <#  $true si $Path esta bajo %ProgramFiles%, %ProgramFiles(x86)% o
        %SystemRoot% (carpetas que solo escriben los administradores). #>
    param([string] $Path)
    if (-not $Path) { return $false }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
    foreach ($r in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:SystemRoot)) {
        if (-not $r) { continue }
        $root = [IO.Path]::GetFullPath($r).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-EmiTrustedExecutable {
    <#  Un ejecutable se puede lanzar elevado solo si: esta en una ubicacion de
        confianza, ni el ni su carpeta los puede modificar un no administrador,
        no es un enlace, y su firma Authenticode es valida (y del editor
        esperado, si se indica: texto que debe aparecer en el sujeto). #>
    param([string] $Path, [string[]] $Publisher)
    $res = [pscustomobject]@{ Ok = $false; Reason = ''; Path = $Path; Signer = $null }
    try {
        if (-not $Path) { $res.Reason = 'sin ruta'; return $res }
        $full = [IO.Path]::GetFullPath($Path); $res.Path = $full
        $fi = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($fi.PSIsContainer -or ($fi.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $res.Reason = 'no es un archivo normal'; return $res }
        if (-not (Test-EmiTrustedLocation $full)) { $res.Reason = "esta fuera de Program Files y de Windows ($full)"; return $res }
        $w = @(Get-EmiUntrustedWriters $full) + @(Get-EmiUntrustedWriters (Split-Path $full -Parent))
        if ($w.Count -gt 0) { $res.Reason = "lo pueden modificar usuarios sin privilegios ($(($w | Select-Object -Unique) -join ', '))"; return $res }
        $sig = Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop
        $res.Signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { $null }
        if ([string]$sig.Status -ne 'Valid') { $res.Reason = "firma digital no valida ($($sig.Status))"; return $res }
        if ($Publisher) {
            $match = $false
            foreach ($p in $Publisher) { if ($res.Signer -and $res.Signer.IndexOf($p, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $match = $true } }
            if (-not $match) { $res.Reason = "firmado por otro editor ($($res.Signer))"; return $res }
        }
        $res.Ok = $true
    } catch { $res.Reason = $_.Exception.Message }
    return $res
}

function Get-EmiInteractiveUser {
    <#  DOMINIO\usuario con la sesion de consola abierta (el que ve la ventana,
        no necesariamente la cuenta de administrador que aprobo el UAC). #>
    try { return [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { return $null }
}

function Start-EmiUnelevated {
    <#  Lanza un programa SIN privilegios de administrador, como el usuario de
        la sesion interactiva. Se usa una tarea programada de un solo uso
        (LogonType Interactive, RunLevel Limited):
          - corre con el token filtrado (integridad media) del usuario de la
            consola, en su escritorio, y admite argumentos y codigo de salida;
          - funciona aunque se elevara con otra cuenta de administrador;
          - 'runas /trustlevel:0x20000' en Windows 11 da un token mixto no
            documentado y corre como la cuenta elevada, y 'explorer.exe <exe>'
            no pasa argumentos ni devuelve el resultado.
        Devuelve @{ Started; ExitCode } (ExitCode solo con -Wait). #>
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [string] $Arguments,
        [switch] $Wait,
        [int] $TimeoutSec = 900
    )
    if (-not (Test-EmiAdmin)) {
        $sp = @{ FilePath = $FilePath; PassThru = $true; ErrorAction = 'Stop' }
        if ($Arguments) { $sp['ArgumentList'] = $Arguments }
        $p = Start-Process @sp
        if ($Wait) { [void]$p.WaitForExit($TimeoutSec * 1000); return [pscustomobject]@{ Started = $true; ExitCode = $p.ExitCode } }
        return [pscustomobject]@{ Started = $true; ExitCode = $null }
    }
    $user = Get-EmiInteractiveUser
    if (-not $user) { throw 'No hay ninguna sesion de usuario abierta en la consola: no se puede lanzar sin privilegios.' }
    $tp   = '\EmiToolkit\'
    $name = 'SinElevar-' + [guid]::NewGuid().ToString('N')
    $act  = if ($Arguments) { New-ScheduledTaskAction -Execute $FilePath -Argument $Arguments } else { New-ScheduledTaskAction -Execute $FilePath }
    $prin = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $set  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds ([math]::Max(60, $TimeoutSec)))
    Register-ScheduledTask -TaskPath $tp -TaskName $name -Action $act -Principal $prin -Settings $set -Force -ErrorAction Stop | Out-Null
    try {
        $t0 = (Get-Date).AddSeconds(-2)
        Start-ScheduledTask -TaskPath $tp -TaskName $name -ErrorAction Stop
        # Esperar a que arranque de verdad antes de seguir (o de borrar la tarea)
        $deadline = (Get-Date).AddSeconds(10)
        do {
            Start-Sleep -Milliseconds 300
            $i = Get-ScheduledTaskInfo -TaskPath $tp -TaskName $name -ErrorAction SilentlyContinue
        } while ((Get-Date) -lt $deadline -and (-not $i -or $i.LastRunTime -lt $t0))
        if (-not $i -or $i.LastRunTime -lt $t0) { throw 'La tarea para lanzar el programa sin privilegios no llego a arrancar.' }
        if (-not $Wait) { return [pscustomobject]@{ Started = $true; ExitCode = $null } }
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline) {
            $t = Get-ScheduledTask -TaskPath $tp -TaskName $name -ErrorAction SilentlyContinue
            if (-not $t -or [string]$t.State -notin @('Running', 'Queued')) { break }
            Start-Sleep -Milliseconds 500
        }
        $i = Get-ScheduledTaskInfo -TaskPath $tp -TaskName $name -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Started = $true; ExitCode = if ($i) { [int]$i.LastTaskResult } else { $null } }
    }
    finally {
        # Borrar la tarea no detiene el proceso que ya arranco
        Unregister-ScheduledTask -TaskPath $tp -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Open-EmiUrl {
    <#  Abre una direccion en el navegador del usuario SIN elevar. Desde un
        proceso de administrador, Start-Process 'https://...' puede abrir el
        navegador como administrador; explorer.exe le pasa la direccion al
        shell del usuario, que la abre con su token normal. #>
    param([Parameter(Mandatory)][string] $Url)
    if ($Url -notmatch '^(https://[^\s"]+|ms-settings:[A-Za-z0-9\-]*|ms-windows-store://[^\s"]+)$') { throw "Direccion no admitida: $Url" }
    if ((Test-EmiWindows) -and (Test-EmiAdmin)) {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"' + $Url + '"') -ErrorAction Stop
    } else {
        Start-Process $Url -ErrorAction Stop
    }
}

# --------------------------- Desinstaladores ------------------------
# Las entradas de HKCU\...\Uninstall y los desinstaladores bajo el perfil del
# usuario (%LOCALAPPDATA%\Programs, instalaciones /currentuser) los puede
# escribir cualquier programa del usuario: nunca se ejecutan elevados. Se
# lanzan como el usuario, sin privilegios (es su propia instalacion).

$script:UninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
# Interpretes: aunque esten en System32 y firmados, con argumentos ajenos
# ejecutan cualquier cosa. Nunca se lanzan elevados desde una entrada.
$script:UninstallInterpreters = '^(cmd|powershell|pwsh|rundll32|regsvr32|mshta|wscript|cscript|conhost|explorer|bitsadmin|certutil|wmic|schtasks|reg|msbuild|installutil)(\.exe)?$'

function Find-EmiUninstallEntry {
    <#  Entradas de ...\Uninstall con DisplayName EXACTO (se admite el sufijo
        de version que anade electron-builder: "Nombre 1.2.3") y Publisher
        exacto de la lista. Nada de -like "*nombre*". #>
    param([Parameter(Mandatory)][string] $DisplayName, [Parameter(Mandatory)][string[]] $Publisher)
    $rx = '^' + [regex]::Escape($DisplayName) + '( v?\d+(\.\d+){0,3})?$'
    foreach ($root in $script:UninstallRoots) {
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or [string]$p.DisplayName -notmatch $rx) { continue }
            if ($Publisher -notcontains ([string]$p.Publisher).Trim()) {
                Write-EmiLog "'$($p.DisplayName)' es de otro editor ('$($p.Publisher)'): no se toca." Warn
                continue
            }
            $p | Add-Member -NotePropertyName EmiUserHive -NotePropertyValue ($root -like 'HKCU:*') -Force
            $p
        }
    }
}

function Get-EmiSafeUninstallPlan {
    <#  Decide como desinstalar una entrada. Devuelve FilePath, Arguments y
        Mode: 'Elevated' (HKLM, en Program Files/Windows, firma valida, no es
        un interprete), 'User' (sin privilegios, como el usuario) o 'Refuse'. #>
    param([Parameter(Mandatory)] $Entry)
    $plan = [pscustomobject]@{ Mode = 'Refuse'; FilePath = $null; Arguments = ''; Reason = '' }
    try { $u = Get-EmiUninstallCommand -QuietUninstallString $Entry.QuietUninstallString -UninstallString $Entry.UninstallString }
    catch { $plan.Reason = $_.Exception.Message; return $plan }
    $fp   = [Environment]::ExpandEnvironmentVariables([string]$u.FilePath)
    $leaf = ($fp -split '[\\/]')[-1]

    if ($leaf -match '^msiexec(\.exe)?$') {
        # Solo "/X{GUID}" reconstruido: nada de /i http://..., /y dll, /p parche
        $g = [regex]::Match([string]$u.Arguments, '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}')
        if (-not $g.Success) { $plan.Reason = "msiexec sin un codigo de producto valido: $($u.Arguments)"; return $plan }
        $plan.FilePath  = Join-Path $env:SystemRoot 'System32\msiexec.exe'
        $plan.Arguments = "/X$($g.Value) /qn /norestart"
        $plan.Mode      = if ($Entry.EmiUserHive) { 'User' } else { 'Elevated' }
        return $plan
    }
    if (-not [IO.Path]::IsPathRooted($fp)) { $plan.Reason = "el desinstalador no tiene ruta completa: $fp"; return $plan }
    $plan.FilePath  = $fp
    $plan.Arguments = [string]$u.Arguments
    if (-not (Test-Path -LiteralPath $fp -PathType Leaf)) { $plan.Reason = "no existe $fp"; return $plan }

    if ($Entry.EmiUserHive -or -not (Test-EmiTrustedLocation $fp)) {
        $plan.Mode = 'User'
        $plan.Reason = 'entrada del usuario o desinstalador en una carpeta que puede modificar el usuario'
        return $plan
    }
    if ($leaf -match $script:UninstallInterpreters) { $plan.Mode = 'User'; $plan.Reason = "$leaf es un interprete de comandos"; return $plan }
    $t = Test-EmiTrustedExecutable -Path $fp
    if (-not $t.Ok) {
        # Sin firma valida no se lanza como administrador. Sin elevar, si el
        # desinstalador necesita permisos Windows mostrara su propio UAC con
        # el editor real, y el usuario decide.
        $plan.Mode = 'User'; $plan.Reason = $t.Reason
        return $plan
    }
    $plan.Mode = 'Elevated'
    return $plan
}

function Invoke-EmiSafeUninstall {
    <#  Ejecuta el plan y espera. Devuelve el codigo de salida (0/3010/1641 = bien). #>
    param([Parameter(Mandatory)] $Entry, [int] $TimeoutSec = 900)
    $plan = Get-EmiSafeUninstallPlan $Entry
    switch ($plan.Mode) {
        'Elevated' {
            $sp = @{ FilePath = $plan.FilePath; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
            if ($plan.Arguments) { $sp['ArgumentList'] = $plan.Arguments }
            return [int](Start-Process @sp).ExitCode
        }
        'User' {
            Write-EmiLog "$($Entry.DisplayName): se desinstala sin privilegios de administrador ($($plan.Reason))." Info
            $r = Start-EmiUnelevated -FilePath $plan.FilePath -Arguments $plan.Arguments -Wait -TimeoutSec $TimeoutSec
            return $r.ExitCode
        }
        default { throw "no se ejecuta: $($plan.Reason)" }
    }
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
    # El equipo: un diario copiado de otra maquina no se aplica aqui
    $Entry['Computer']  = $env:COMPUTERNAME
    if ([string]$Entry['Kind'] -eq 'Firewall' -and $Entry['RuleName'] -and -not $Entry['RuleId']) {
        # Se guarda el Name (GUID) de la regla recien creada para borrarla luego
        # por su identificador exacto, nunca por DisplayName con comodines.
        try {
            $r = @(Get-EmiToolFirewallRule -DisplayName ([string]$Entry['RuleName']))
            if ($r.Count -eq 1) { $Entry['RuleId'] = [string]$r[0].Name; $Entry['RuleGroup'] = [string]$r[0].Group }
        } catch { }
    }
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

# ------------------- Listas permitidas del deshacer -------------------
# El deshacer corre como administrador y obedece al diario. Aunque el diario
# ya vive en una carpeta protegida, cada entrada se valida contra lo que la
# herramienta escribe de verdad; lo demas se rechaza y se anota en el log.
# Si un modulo empieza a escribir una ruta, servicio o regla nueva, hay que
# anadirla aqui o su deshacer se rechazara.

$script:UndoRegistryAllow = @(
    # HKLM: directivas y ajustes que escriben EmiPrivacy, EmiTweaks y EmiSystem
    '^HKLM:\\SOFTWARE\\Policies\\Microsoft\\(Dsh|Edge|Edge\\EdgeWebView2|InputPersonalization|SQMClient\\Windows|Speech)$'
    '^HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\(AdvertisingInfo|AppCompat|AppPrivacy|CloudContent|DataCollection|DeliveryOptimization|Explorer|GameDVR|HandwritingErrorReports|LocationAndSensors|System|Windows Chat|Windows Error Reporting|Windows Search|WindowsAI|WindowsCopilot|WindowsUpdate|WindowsUpdate\\AU)$'
    '^HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\DataCollection$'
    '^HKLM:\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting$'
    '^HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile$'
    '^HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location$'
    '^HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\(Run|Run32|StartupFolder)$'
    '^HKLM:\\SYSTEM\\CurrentControlSet\\Control\\(Session Manager\\Power|Power|BitLocker)$'
    '^HKLM:\\SYSTEM\\CurrentControlSet\\Control\\WMI\\Autologger\\[A-Za-z0-9 _.\-]+$'
    # HKCU: ajustes del usuario que escriben EmiPrivacy, EmiTweaks y EmiStartup
    '^HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\(Explorer|Explorer\\Advanced|Explorer\\Advanced\\TaskbarDeveloperSettings|Explorer\\VisualEffects|Explorer\\StartupApproved\\(Run|Run32|StartupFolder)|ContentDeliveryManager|Search|SearchSettings|AdvertisingInfo|Privacy|BackgroundAccessApplications|UserProfileEngagement|Themes\\Personalize|StorageSense\\Parameters\\StoragePolicy)$'
    '^HKCU:\\SOFTWARE\\Microsoft\\(GameBar|Siuf\\Rules|Personalization\\Settings|Input\\TIPC|InputPersonalization|InputPersonalization\\TrainedDataStore|Speech_OneCore\\Settings\\OnlineSpeechPrivacy|AppInstaller)$'
    '^HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\(WindowsCopilot|Explorer)$'
    '^HKCU:\\System\\GameConfigStore$'
    '^HKCU:\\Control Panel\\(Mouse|Accessibility\\StickyKeys)$'
    '^HKCU:\\SOFTWARE\\Classes\\CLSID\\\{(0DB7E03F-FC29-4DC6-9020-FF41B59E513A|f874310e-b6b7-47dc-bc84-b9e6b38f5903|018D5C66-4533-4307-9B53-224DE2ED1FE6)\}$'
)
# Claves donde una escritura equivale a ejecutar codigo: nunca, venga de donde venga
$script:UndoRegistryDeny = '\\(Image File Execution Options|SilentProcessExit|Winlogon|AppInit_DLLs|AppCertDlls|KnownDLLs|Lsa|Services|RunOnce|RunOnceEx|Policies\\Explorer\\Run|Terminal Server|Print\\Monitors|Command Processor|Shell Folders|Environment)(\\|$)'
$script:UndoServices = @(
    'DiagTrack', 'dmwappushservice', 'diagnosticshub.standardcollector.service', 'WerSvc', 'lfsvc',
    'TextInputManagementService', 'SysMain', 'WSearch',
    'Fax', 'RetailDemo', 'MapsBroker', 'WalletService', 'PhoneSvc', 'RemoteRegistry', 'RemoteAccess',
    'SharedAccess', 'WMPNetworkSvc', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc',
    'SEMgrSvc', 'PcaSvc', 'DoSvc', 'WpcMonSvc', 'TabletInputService',
    'SQLTELEMETRY', 'SQLTELEMETRY$SQLEXPRESS', 'WSAIFabricSvc'
)
# Abren el equipo a la red: el deshacer nunca los pone en Automatico ni los arranca
$script:UndoSensitiveServices = @('RemoteRegistry', 'RemoteAccess')
$script:UndoFirewallGroups   = @('EmiToolkit', 'ESET KB332')
$script:UndoFirewallPrefixes = @('EmiToolkit - ', 'ESET KB332 - ')
$script:UndoFeatures = @('Containers-DisposableClientVM', 'Microsoft-Windows-Subsystem-Linux', 'Internet-Explorer-Optional-amd64', 'WindowsMediaPlayer')
$script:UndoEnvVars  = @('AZURE_CORE_COLLECT_TELEMETRY', 'DOTNET_CLI_TELEMETRY_OPTOUT', 'BICEP_TELEMETRY_OPTOUT', 'POWERSHELL_TELEMETRY_OPTOUT', 'NUGET_TELEMETRY_OPTOUT')

function ConvertTo-EmiRegistryPath {
    <#  Forma canonica HKLM:\... / HKCU:\... (o $null si no es una de esas). #>
    param([string] $Path)
    if (-not $Path) { return $null }
    $p = $Path.Trim() -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' -replace '^Registry::', ''
    $p = $p -replace '^HKEY_LOCAL_MACHINE(?=\\|$)', 'HKLM:' -replace '^HKEY_CURRENT_USER(?=\\|$)', 'HKCU:'
    $p = $p -replace '/', '\' -replace '\\{2,}', '\'
    $p = $p.TrimEnd('\')
    if ($p -notmatch '^HK(LM|CU):\\') { return $null }
    if ($p -match '(^|\\)\.{1,2}(\\|$)' -or $p -match '[\*\?\x00]') { return $null }
    return $p
}

function Get-EmiToolFirewallRule {
    <#  Reglas creadas por la herramienta (por su Group exacto) con ese
        DisplayName exacto. Nunca se busca por DisplayName: admite comodines. #>
    param([Parameter(Mandatory)][string] $DisplayName, [string] $RuleId)
    $out = @()
    foreach ($g in $script:UndoFirewallGroups) {
        $out += @(Get-NetFirewallRule -Group $g -ErrorAction SilentlyContinue |
                  Where-Object { $_.DisplayName -ceq $DisplayName -and (-not $RuleId -or $_.Name -eq $RuleId) })
    }
    return $out
}

function Test-EmiUndoEntry {
    <#  $null si la entrada se puede aplicar; si no, el motivo del rechazo. #>
    param([Parameter(Mandatory)] $e)
    $names = @($e.PSObject.Properties | ForEach-Object { $_.Name })
    if (-not ($names -contains 'Computer') -or -not $e.Computer) { return 'no indica en que equipo se hizo' }
    if ([string]$e.Computer -ne [string]$env:COMPUTERNAME) { return "es de otro equipo ($($e.Computer))" }

    switch ([string]$e.Kind) {
        'Registry' {
            $p = ConvertTo-EmiRegistryPath ([string]$e.Path)
            if (-not $p) { return "ruta de registro no valida: $($e.Path)" }
            if ($p -match $script:UndoRegistryDeny) { return "clave protegida: $p" }
            $n = [string]$e.Name
            if (-not $n -or $n.Contains([char]0)) { return 'valor sin nombre' }
            $ok = $false
            foreach ($rx in $script:UndoRegistryAllow) { if ($p -match $rx) { $ok = $true; break } }
            # Casos con nombre fijo
            if ($p -match '^HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run$' -and $n -eq 'OneDrive') { $ok = $true }
            if ($p -ieq 'HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -and
                $n -eq '(default)' -and (-not $e.Existed -or [string]$e.OldValue -eq '')) { $ok = $true }
            if ($p -match '^HKCU:\\SOFTWARE\\Classes\\CLSID\\' -and $n -ne 'System.IsPinnedToNameSpaceTree' -and $n -ne '(default)') { $ok = $false }
            if ($p -match '\\WMI\\Autologger\\' -and $n -ne 'Start') { $ok = $false }
            if (-not $ok) { return "la herramienta no escribe en $p" }
            if ($e.Existed -and $e.OldType -and [string]$e.OldType -notin @('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary', 'Unknown')) {
                return "tipo de valor no admitido: $($e.OldType)"
            }
            return $null
        }
        'Service' {
            if ($script:UndoServices -notcontains [string]$e.Name) { return "servicio no gestionado por la herramienta: $($e.Name)" }
            if ($script:UndoSensitiveServices -contains [string]$e.Name -and
                ([string]$e.OldStartMode -in @('Auto', 'Automatic') -or [string]$e.OldStatus -eq 'Running')) {
                return "no se reactiva $($e.Name) en Automatico ni se arranca: abre el equipo a la red (hazlo a mano en services.msc si de verdad lo necesitas)"
            }
            return $null
        }
        'Task' {
            if ([string]$e.TaskPath -notmatch '^\\Microsoft\\[A-Za-z0-9 _.\\\-]*\\$' -or [string]$e.TaskName -match '[\*\?\[\]]' -or -not $e.TaskName) {
                return "tarea fuera de \Microsoft\: $($e.TaskPath)$($e.TaskName)"
            }
            return $null
        }
        'Firewall' {
            $rn = [string]$e.RuleName
            if (-not $rn -or $rn -match '[\*\?\[\]]') { return "nombre de regla no valido: '$rn'" }
            $pref = $false
            foreach ($x in $script:UndoFirewallPrefixes) { if ($rn.StartsWith($x, [StringComparison]::Ordinal)) { $pref = $true } }
            if (-not $pref) { return "la regla '$rn' no la crea la herramienta" }
            if ($e.RuleId -and [string]$e.RuleId -notmatch '^\{?[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}?$') { return "identificador de regla no valido: $($e.RuleId)" }
            return $null
        }
        'File' {
            # Sin copia no se hace nada (Invoke-EmiUndoEntry la da por irreversible)
            if (-not $e.Backup) { return $null }
            try {
                $path = [IO.Path]::GetFullPath([string]$e.Path)
                $bak  = if ($e.Backup) { [IO.Path]::GetFullPath([string]$e.Backup) } else { $null }
            } catch { return 'ruta de archivo no valida' }
            if ($path -ne [IO.Path]::GetFullPath((Get-EmiHostsPath))) { return "la herramienta solo restaura el archivo hosts, no $path" }
            if ($bak -and $bak -ne [IO.Path]::GetFullPath((Get-EmiHostsBackupPath))) { return "la copia de hosts debe estar en $($script:DataDir), no en $bak" }
            return $null
        }
        'Command' {
            $c = ConvertTo-EmiUndoCommand $e
            switch ([string]$c.Action) {
                'AppxReinstall'  { if ([string]$c.PackageName -notmatch '^[A-Za-z0-9][A-Za-z0-9.\-]{1,127}$') { return "paquete no valido: $($c.PackageName)" } }
                'WindowsFeature' { if ($script:UndoFeatures -notcontains [string]$c.Feature) { return "caracteristica no gestionada: $($c.Feature)" } }
                'EnvVars' {
                    if ($c.Scope -and [string]$c.Scope -ne 'User') { return "solo variables de usuario, no $($c.Scope)" }
                    foreach ($v in @($c.Variables)) { if ($script:UndoEnvVars -notcontains [string]$v.Name) { return "variable no gestionada: $($v.Name)" } }
                }
            }
            return $null
        }
    }
    return $null
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
                $rp = ConvertTo-EmiRegistryPath ([string]$e.Path)
                if (-not (Test-Path -LiteralPath $rp)) { New-Item -Path $rp -Force -ErrorAction Stop | Out-Null }
                New-ItemProperty -LiteralPath $rp -Name $e.Name -Value $val -PropertyType $t -Force -ErrorAction Stop | Out-Null
            } elseif (Test-Path -LiteralPath (ConvertTo-EmiRegistryPath ([string]$e.Path))) {
                Remove-ItemProperty -LiteralPath (ConvertTo-EmiRegistryPath ([string]$e.Path)) -Name $e.Name -Force -ErrorAction SilentlyContinue
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
            if ($e.OldStatus -eq 'Running' -and $script:UndoSensitiveServices -notcontains [string]$e.Name) {
                Start-Service -Name $e.Name -ErrorAction Stop
            }
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
            # Solo reglas del grupo de la herramienta, con el DisplayName exacto
            # (y el GUID guardado, si lo hay); se borran una a una por su Name.
            $rules = @(Get-EmiToolFirewallRule -DisplayName ([string]$e.RuleName) -RuleId ([string]$e.RuleId))
            foreach ($r in $rules) { Remove-NetFirewallRule -Name $r.Name -ErrorAction Stop }
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
            if (-not (Test-EmiHostsContent ([string]$e.Backup))) {
                Write-EmiLog "La copia $($e.Backup) no parece un archivo hosts: no se restaura." Warn
                return 'Failed'
            }
            Copy-Item -LiteralPath (Get-EmiHostsBackupPath) -Destination (Get-EmiHostsPath) -Force -ErrorAction Stop
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

    $n = 0; $skipped = 0; $rejected = 0
    $pending = New-Object System.Collections.ArrayList
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        $e = $entries[$i]
        $r = 'Failed'
        $why = $null
        try { $why = Test-EmiUndoEntry $e } catch { $why = $_.Exception.Message }
        if ($why) {
            # Rechazada: no se aplica, sale del diario y queda apartada para revisarla
            Write-EmiLog "Entrada del diario rechazada ($($e.Kind)): $why." Warn
            try {
                [IO.File]::AppendAllText(($script:Journal -replace '\.jsonl$', '.rechazadas.jsonl'),
                    (ConvertTo-Json -InputObject $e -Depth 8 -Compress) + "`r`n", $script:JournalUtf8)
            } catch { }
            $rejected++
            continue
        }
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
    if ($rejected -gt 0) { Write-EmiLog "$rejected entradas del diario se rechazaron por seguridad (apartadas en $(Split-Path ($script:Journal -replace '\.jsonl$', '.rechazadas.jsonl') -Leaf))." Warn }
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
