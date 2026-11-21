# =====================================================================
#  EmiVault.psm1 - Almacen local de contrasenas cifrado con DPAPI
#  El cifrado es DPAPI del usuario de Windows (CurrentUser): cualquier proceso
#  que corra con ese usuario puede descifrar vault.dat. Windows Hello solo es
#  la puerta de esta interfaz, no forma parte del cifrado.
# =====================================================================

$script:VaultPath      = $null
$script:VaultUnlocked  = $false
$script:VaultEntries   = @()
$script:WinRtLoaded    = $false
$script:UCVType        = $null
$script:UCAvailType    = $null
$script:UCResultType   = $null
$script:BridgeCompiled = $false

function Initialize-EmiVault {
    # La boveda vive en el perfil de quien la usa (%LOCALAPPDATA%\EmiToolkit,
    # ACL del usuario). En <app>\Data, con la herramienta en C:\EmiToolkit,
    # cualquier otro usuario podia borrarla o sustituirla. Se migra una vez.
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [Environment]::GetFolderPath('LocalApplicationData') }
    $dir  = Join-Path $base 'EmiToolkit'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:VaultPath     = Join-Path $dir 'vault.dat'
    $old = Join-Path (Join-Path (Get-EmiRoot) 'Data') 'vault.dat'
    if (-not (Test-Path -LiteralPath $script:VaultPath) -and (Test-Path -LiteralPath $old)) {
        try {
            foreach ($ext in @('', '.bak')) {
                if (Test-Path -LiteralPath ($old + $ext)) {
                    Copy-Item -LiteralPath ($old + $ext) -Destination ($script:VaultPath + $ext) -ErrorAction Stop
                    Rename-Item -LiteralPath ($old + $ext) -NewName ((Split-Path ($old + $ext) -Leaf) + '.migrado') -ErrorAction SilentlyContinue
                }
            }
            Write-EmiLog "Boveda migrada a $dir." Info
        } catch { Write-EmiLog "No se pudo migrar la boveda antigua: $($_.Exception.Message)" Warn }
    }
    $script:VaultUnlocked = $false
    $script:VaultEntries  = @()

    if (-not $script:WinRtLoaded) {
        try {
            Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop

            $script:UCVType = [Type]::GetType(
                'Windows.Security.Credentials.UI.UserConsentVerifier, Windows.Security.Credentials.UI, ContentType=WindowsRuntime')
            $script:UCAvailType = [Type]::GetType(
                'Windows.Security.Credentials.UI.UserConsentVerifierAvailability, Windows.Security.Credentials.UI, ContentType=WindowsRuntime')
            $script:UCResultType = [Type]::GetType(
                'Windows.Security.Credentials.UI.UserConsentVerificationResult, Windows.Security.Credentials.UI, ContentType=WindowsRuntime')

            if ($script:UCVType -and $script:UCAvailType -and $script:UCResultType) {
                $script:WinRtLoaded = $true
            } else {
                Write-EmiLog 'Tipos WinRT de UserConsentVerifier no encontrados.' Warn
            }
        } catch {
            Write-EmiLog "No se pudo cargar WinRT para Windows Hello: $($_.Exception.Message)" Warn
        }
    }

    # Compilar bridge C# para operaciones async WinRT (una sola vez)
    if (-not $script:BridgeCompiled -and $script:WinRtLoaded) {
        try {
            # Verificar si ya existe (puede haber sido compilado en una carga anterior del modulo)
            $existing = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                ForEach-Object { $_.GetType('EmiHelloBridge') } |
                Where-Object { $null -ne $_ } |
                Select-Object -First 1

            if ($existing) {
                $script:BridgeCompiled = $true
            } else {
                $bridgeCode = @'
using System;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;

public static class EmiHelloBridge {
    private static MethodInfo _asTaskGeneric;

    private static MethodInfo AsTaskGeneric {
        get {
            if (_asTaskGeneric == null)
                _asTaskGeneric = typeof(System.WindowsRuntimeSystemExtensions)
                    .GetMethods()
                    .First(m => m.Name == "AsTask" && m.IsGenericMethod && m.GetParameters().Length == 1);
            return _asTaskGeneric;
        }
    }

    public static object AwaitWithPump(object asyncOp, Type resultType) {
        var typed = AsTaskGeneric.MakeGenericMethod(resultType);
        var task = (Task)typed.Invoke(null, new object[] { asyncOp });

        // Usar DispatcherFrame para mantener el message pump de WPF activo
        // mientras el dialogo de Windows Hello esta visible
        var frame = new DispatcherFrame();
        task.ContinueWith(t => { frame.Continue = false; }, TaskScheduler.Default);
        Dispatcher.PushFrame(frame);

        if (task.IsFaulted)
            throw task.Exception.InnerException ?? task.Exception;

        var rp = task.GetType().GetProperty("Result");
        return rp != null ? rp.GetValue(task) : null;
    }

    public static object AwaitBlocking(object asyncOp, Type resultType) {
        var typed = AsTaskGeneric.MakeGenericMethod(resultType);
        var task = (Task)typed.Invoke(null, new object[] { asyncOp });
        task.Wait();
        if (task.IsFaulted)
            throw task.Exception.InnerException ?? task.Exception;
        var rp = task.GetType().GetProperty("Result");
        return rp != null ? rp.GetValue(task) : null;
    }

    public static string CheckAndVerify(Type ucvType, Type availType, Type resultType, string message) {
        // Paso 1: CheckAvailability (sin UI, blocking ok)
        var checkMethod = ucvType.GetMethod("CheckAvailabilityAsync");
        var availOp = checkMethod.Invoke(null, null);
        var availResult = AwaitBlocking(availOp, availType);
        var availName = Enum.GetName(availType, availResult);
        if (availName != "Available")
            return "UNAVAILABLE:" + availName;

        // Paso 2: RequestVerification (muestra dialogo UI, necesita pump activo)
        var verifyMethod = ucvType.GetMethod("RequestVerificationAsync", new Type[] { typeof(string) });
        var verifyOp = verifyMethod.Invoke(null, new object[] { message });
        var verifyResult = AwaitWithPump(verifyOp, resultType);
        return Enum.GetName(resultType, verifyResult);
    }
}
'@
                Add-Type -TypeDefinition $bridgeCode `
                    -ReferencedAssemblies @('System.Runtime.WindowsRuntime', 'System.Core', 'WindowsBase') `
                    -ErrorAction Stop
                $script:BridgeCompiled = $true
            }
        } catch {
            Write-EmiLog "No se pudo compilar EmiHelloBridge: $($_.Exception.Message)" Warn
        }
    }

    try { Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue } catch { }
}

# ------------------------------------------------------------------
#  Autenticacion con Windows Hello
# ------------------------------------------------------------------
function Request-EmiVaultUnlock {
    if (-not $script:WinRtLoaded) {
        Write-EmiLog 'Windows Hello no disponible en este equipo.' Warn
        return $false
    }

    if (-not $script:BridgeCompiled) {
        Write-EmiLog 'Bridge de Windows Hello no compilado.' Warn
        return $false
    }

    try {
        $bridgeType = $null
        foreach ($asm in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
            $bridgeType = $asm.GetType('EmiHelloBridge')
            if ($bridgeType) { break }
        }

        if (-not $bridgeType) {
            Write-EmiLog 'Tipo EmiHelloBridge no encontrado en ensamblados cargados.' Error
            return $false
        }

        $result = $bridgeType.GetMethod('CheckAndVerify').Invoke($null, @(
            $script:UCVType, $script:UCAvailType, $script:UCResultType,
            'Desbloquear almacen de contrasenas de Emi Toolkit'))

        if ($result -eq 'Verified') {
            # Si vault.dat no se puede descifrar (otro usuario u otro equipo, p. ej.
            # la carpeta sincronizada por OneDrive), la boveda sigue bloqueada:
            # abrirla vacia haria que el siguiente guardado borrase lo que hay.
            try { $entries = @(Load-EmiVaultRaw) }
            catch {
                Write-EmiLog "No se pudo descifrar vault.dat: $($_.Exception.Message). Solo lo abre el mismo usuario de Windows en el equipo donde se creo. La boveda sigue bloqueada y el archivo no se toca." Error
                return $false
            }
            $script:VaultEntries  = $entries
            $script:VaultUnlocked = $true
            return $true
        } elseif ($result -like 'UNAVAILABLE:*') {
            $reason = $result.Split(':')[1]
            Write-EmiLog "Windows Hello no disponible (estado: $reason). Configura un PIN o biometria en Configuracion > Cuentas > Opciones de inicio." Warn
            return $false
        } else {
            Write-EmiLog "Verificacion con Windows Hello: $result" Warn
            return $false
        }
    } catch {
        Write-EmiLog "Error en Windows Hello: $($_.Exception.Message)" Error
        return $false
    }
}

function Lock-EmiVault {
    $script:VaultEntries  = @()
    $script:VaultUnlocked = $false
}

function Test-EmiVaultUnlocked {
    return [bool]$script:VaultUnlocked
}

# ------------------------------------------------------------------
#  Lectura / escritura cifrada
# ------------------------------------------------------------------
function Load-EmiVaultRaw {
    <#  Devuelve las entradas de vault.dat (ninguna si aun no existe).
        Lanza una excepcion si el archivo existe pero no se puede descifrar
        o leer: quien llama debe dejar la boveda bloqueada. #>
    if (-not (Test-Path -LiteralPath $script:VaultPath)) { return @() }
    $protected = [System.IO.File]::ReadAllBytes($script:VaultPath)
    $bytes     = [System.Security.Cryptography.ProtectedData]::Unprotect(
                     $protected, $null,
                     [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    $json = [System.Text.Encoding]::UTF8.GetString($bytes)
    $obj  = ConvertFrom-Json -InputObject $json
    if ($null -eq $obj -or -not ($obj.PSObject.Properties.Name -contains 'entries')) {
        throw 'vault.dat no tiene el formato esperado.'
    }
    if ($obj.entries) { return @($obj.entries) }
    return @()
}

function Save-EmiVault {
    # Solo se guarda una boveda que se abrio bien; si no, se sobrescribiria
    # vault.dat con una lista vacia o incompleta.
    if (-not $script:VaultUnlocked) {
        Write-EmiLog 'La boveda esta bloqueada; no se guarda nada.' Warn
        return $false
    }
    try {
        $data = @{ version = 1; entries = @($script:VaultEntries) }
        $json  = $data | ConvertTo-Json -Depth 5 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $protected = [System.Security.Cryptography.ProtectedData]::Protect(
                         $bytes, $null,
                         [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        $dir = Split-Path $script:VaultPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # Escritura atomica: primero a un temporal y luego reemplazo, para no
        # corromper vault.dat si la escritura falla a mitad (disco lleno, crash).
        $tmp = "$($script:VaultPath).tmp"
        [System.IO.File]::WriteAllBytes($tmp, $protected)
        if (Test-Path -LiteralPath $script:VaultPath) {
            # Copia de la version anterior antes de reemplazarla
            Copy-Item -LiteralPath $script:VaultPath -Destination "$($script:VaultPath).bak" -Force -ErrorAction Stop
            Move-Item -LiteralPath $tmp -Destination $script:VaultPath -Force
        } else {
            Rename-Item -LiteralPath $tmp -NewName (Split-Path $script:VaultPath -Leaf) -Force
        }
    } catch {
        Write-EmiLog "Error al guardar la boveda: $($_.Exception.Message)" Error
        return $false
    }
    return $true
}

# ------------------------------------------------------------------
#  CRUD de entradas
# ------------------------------------------------------------------
function Get-EmiVaultEntries {
    if (-not $script:VaultUnlocked) { return @() }
    return @($script:VaultEntries | ForEach-Object {
        [pscustomobject]@{
            Id             = $_.id
            AppName        = $_.appName
            Email          = $_.email
            MaskedPassword = [char]0x2022 * 12
            Notes          = $_.notes
            ModifiedText   = if ($_.modifiedUtc) { ([datetime]$_.modifiedUtc).ToString('yyyy-MM-dd HH:mm') } else { '' }
        }
    })
}

function Get-EmiVaultEntryPlain {
    param([Parameter(Mandatory)][string] $Id)
    if (-not $script:VaultUnlocked) { return $null }
    $entry = $script:VaultEntries | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $entry) { return $null }
    return [pscustomobject]@{
        Id       = $entry.id
        AppName  = $entry.appName
        Email    = $entry.email
        Password = $entry.password
        Notes    = $entry.notes
    }
}

function Add-EmiVaultEntry {
    param(
        [Parameter(Mandatory)][string] $AppName,
        [string] $Email,
        [Parameter(Mandatory)][string] $Password,
        [string] $Notes
    )
    if (-not $script:VaultUnlocked) { return $null }
    $now = [datetime]::UtcNow.ToString('o')
    $newEntry = [pscustomobject]@{
        id          = [guid]::NewGuid().ToString()
        appName     = $AppName
        email       = $Email
        password    = $Password
        notes       = $Notes
        createdUtc  = $now
        modifiedUtc = $now
    }
    $before = @($script:VaultEntries)
    $script:VaultEntries = $before + @($newEntry)
    if (-not (Save-EmiVault)) { $script:VaultEntries = $before; return $null }
    return $newEntry.id
}

function Remove-EmiVaultEntry {
    param([Parameter(Mandatory)][string] $Id)
    if (-not $script:VaultUnlocked) { return $false }
    $before = @($script:VaultEntries)
    $script:VaultEntries = @($before | Where-Object { $_.id -ne $Id })
    if (-not (Save-EmiVault)) { $script:VaultEntries = $before; return $false }
    return $true
}

# ------------------------------------------------------------------
#  Generador de contrasenas seguras
# ------------------------------------------------------------------
function Get-EmiRandomInt {
    param([int] $MaxValue)
    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $buf   = [byte[]]::new(4)
    $limit = [uint32]([uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$MaxValue))
    do {
        $rng.GetBytes($buf)
        $val = [BitConverter]::ToUInt32($buf, 0)
    } while ($val -ge $limit)
    return [int]($val % [uint32]$MaxValue)
}

function New-EmiSecurePassword {
    param(
        [int]    $Length         = 20,
        [switch] $IncludeSpecial
    )
    $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lower   = 'abcdefghijklmnopqrstuvwxyz'
    $digits  = '0123456789'
    $special = '!@#$%^&*()-_=+[]{}|;:,.<>?'
    $charset = $upper + $lower + $digits
    if ($IncludeSpecial) { $charset += $special }
    $mandatory = @(
        $upper[(Get-EmiRandomInt $upper.Length)]
        $lower[(Get-EmiRandomInt $lower.Length)]
        $digits[(Get-EmiRandomInt $digits.Length)]
    )
    if ($IncludeSpecial) {
        $mandatory += $special[(Get-EmiRandomInt $special.Length)]
    }
    $remaining = $Length - $mandatory.Count
    $chars     = [char[]]::new($Length)
    for ($i = 0; $i -lt $remaining; $i++) {
        $chars[$i] = $charset[(Get-EmiRandomInt $charset.Length)]
    }
    for ($i = 0; $i -lt $mandatory.Count; $i++) { $chars[$remaining + $i] = $mandatory[$i] }
    # Fisher-Yates con el mismo RNG: los obligatorios ya no quedan siempre al
    # final (antes las ultimas 3-4 posiciones eran siempre mayus/minus/cifra).
    for ($i = $Length - 1; $i -gt 0; $i--) {
        $j = Get-EmiRandomInt ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    return (-join $chars)
}

Export-ModuleMember -Function *-Emi*, New-EmiSecurePassword