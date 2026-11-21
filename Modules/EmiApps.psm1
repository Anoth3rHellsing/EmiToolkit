# EmiApps.psm1 — Desinstalar apps AppX instaladas y limpiar su cache
# ADITIVO: no modifica ningun modulo existente. Usa helpers de EmiCore.

Set-StrictMode -Version Latest

# --- Paquetes que NUNCA deben ofrecerse para desinstalar (patrones -like) ---
# Como tambien se quita el paquete aprovisionado, casi nada de esto se puede
# recuperar con Revertir (auditoria de sistema, EmiApps.psm1:7-27). Ademas de
# esta lista se rechaza todo lo que Windows marca como del sistema
# (SignatureKind = System), no desinstalable (NonRemovable) o framework.
$script:ProtectedPatterns = @(
    # Shell e interfaz del sistema
    'Microsoft.Windows.ShellExperienceHost*',
    'Microsoft.Windows.StartMenuExperienceHost*',
    'Microsoft.Windows.SearchExperienceHost*',
    'Microsoft.AAD.BrokerPlugin*',
    'Microsoft.Windows.CloudExperienceHost*',
    'Microsoft.Windows.AssignedAccessLockApp*',
    'Microsoft.Windows.CapturePicker*',
    'Microsoft.Windows.ContentDeliveryManager*',
    'Microsoft.Windows.PinningConfirmationDialog*',
    'MicrosoftWindows.Client.*',
    'windows.immersivecontrolpanel*',
    'Microsoft.MicrosoftEdge*',
    'Microsoft.Windows.Cortana*',             # lo gestiona Debloat con su diario
    # Seguridad (el nombre real es Microsoft.SecHealthUI; Microsoft.Windows.SecHealthUI no existe)
    'Microsoft.SecHealthUI*',
    # Tienda e instalador: sin ellos no se puede reinstalar nada (ni winget)
    'Microsoft.WindowsStore*',
    'Microsoft.StorePurchaseApp*',
    'Microsoft.DesktopAppInstaller*',
    'Microsoft.Services.Store.Engagement*',
    # Idiomas: quitar el paquete devuelve la interfaz al ingles
    'Microsoft.LanguageExperiencePack*',
    # Codecs (HEVC es de pago)
    'Microsoft.HEVCVideoExtension*',
    'Microsoft.VP9VideoExtensions*',
    'Microsoft.AV1VideoExtension*',
    'Microsoft.MPEG2VideoExtension*',
    'Microsoft.AVCEncoderVideoExtension*',
    'Microsoft.HEIFImageExtension*',
    'Microsoft.WebpImageExtension*',
    'Microsoft.RawImageExtension*',
    'Microsoft.WebMediaExtensions*',
    'Microsoft.DolbyAudioExtensions*',
    # Runtimes y frameworks
    'Microsoft.VCLibs*',
    'Microsoft.UI.Xaml*',
    'Microsoft.NET.Native*',
    'Microsoft.WindowsAppRuntime*',
    'MicrosoftCorporationII.WinAppRuntime*',
    'Microsoft.WidgetsPlatformRuntime*',
    'Microsoft.DirectXRuntime*',
    'Microsoft.WindowsXGpu*',
    'Microsoft.OneDriveSync*',
    'Microsoft.ApplicationCompatibilityEnhancements*',
    # Xbox: identidad y servicios de juego (la app Xbox si se puede quitar)
    'Microsoft.XboxIdentityProvider*',
    'Microsoft.GamingServices*',
    # Paneles del fabricante (audio, graficos, touchpad)
    'NVIDIACorp.NVIDIAControlPanel*',
    'RealtekSemiconductorCorp.*',
    'DolbyLaboratories.*',
    'WavesAudio.*',
    'AppUp.IntelGraphicsExperience*',
    'AdvancedMicroDevicesInc-2.*',
    'SynapticsIncorporated.*',
    'ELANMicroelectronicsCorpo.*'
)

# --- Rutas tipicas de cache/temp por familia de apps ---
$script:CacheDirs = @(
    "$env:LOCALAPPDATA\Packages"
)

function Test-EmiProtectedApp {
    <#  Por nombre de paquete (Name o PackageFullName).  #>
    param([Parameter(Mandatory)][string] $PackageFullName)
    foreach ($p in $script:ProtectedPatterns) {
        if ($PackageFullName -like $p) { return $true }
    }
    return $false
}

function Get-EmiPkgProp {
    param($Package, [string] $Name)
    $pr = $Package.PSObject.Properties[$Name]
    if ($pr) { return $pr.Value }
    return $null
}

function Test-EmiProtectedAppx {
    <#  Logica pura sobre el objeto que devuelve Get-AppxPackage: lista de
        protegidos, paquetes del sistema, no desinstalables y frameworks.  #>
    param([Parameter(Mandatory)] $Package)
    if (Test-EmiProtectedApp -PackageFullName ([string](Get-EmiPkgProp $Package 'Name'))) { return $true }
    if ("$(Get-EmiPkgProp $Package 'SignatureKind')" -eq 'System') { return $true }
    if ((Get-EmiPkgProp $Package 'NonRemovable') -eq $true) { return $true }
    if ((Get-EmiPkgProp $Package 'IsFramework') -eq $true) { return $true }
    return $false
}

function Find-EmiAppxPackage {
    <#  Busca en una lista de paquetes por PackageFullName, PackageFamilyName
        o Name exactos. Get-AppxPackage -Name solo compara con Name, asi que
        pasarle un nombre completo o de familia no encontraba nunca nada.  #>
    param([object[]] $Packages, [string] $FullName, [string] $FamilyName, [string] $Name)
    foreach ($p in $Packages) {
        if ($FullName   -and (Get-EmiPkgProp $p 'PackageFullName')   -eq $FullName)   { return $p }
        if ($FamilyName -and (Get-EmiPkgProp $p 'PackageFamilyName') -eq $FamilyName) { return $p }
        if ($Name       -and (Get-EmiPkgProp $p 'Name')              -eq $Name)       { return $p }
    }
    return $null
}

function Get-EmiFamilyFromFullName {
    <#  Nombre_Version_Arquitectura_Recurso_IdEditor -> Nombre_IdEditor  #>
    param([string] $PackageFullName)
    $parts = $PackageFullName -split '_'
    if ($parts.Count -lt 2) { return $PackageFullName }
    return "$($parts[0])_$($parts[-1])"
}

function Get-EmiPackageCacheSize {
    param([string] $PackageFamilyName)
    if (-not $PackageFamilyName) { return 0 }
    $dir = Join-Path $env:LOCALAPPDATA "Packages\$PackageFamilyName"
    if (-not (Test-Path -LiteralPath $dir)) { return 0 }
    try {
        $sum = (Get-ChildItem -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [long]$sum
    } catch { return 0 }
}

# ============================================================
# Lista de apps instaladas para la UI
# ============================================================
function Get-EmiInstalledApps {
    $pkgs = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    $items = New-Object System.Collections.ArrayList

    foreach ($pkg in $pkgs) {
        if (Test-EmiProtectedAppx -Package $pkg) { continue }

        $cacheSize = Get-EmiPackageCacheSize -PackageFamilyName $pkg.PackageFamilyName
        $items.Add([pscustomobject]@{
            Id        = $pkg.PackageFullName
            Name      = $pkg.Name
            Detail    = $pkg.InstallLocation
            Version   = $pkg.Version
            CacheSize = $cacheSize
        }) | Out-Null
    }
    return $items
}

# ============================================================
# Desinstalar app (con journal para poder reinstalar)
# ============================================================
function Remove-EmiInstalledApp {
    param([Parameter(Mandatory)][string] $PackageFullName)

    $pkg = Find-EmiAppxPackage -Packages @(Get-AppxPackage -ErrorAction SilentlyContinue) -FullName $PackageFullName
    if (-not $pkg) {
        Write-EmiLog "$PackageFullName no esta instalada; omitida." Info
        return $false
    }
    if (Test-EmiProtectedAppx -Package $pkg) {
        Write-EmiLog "$($pkg.Name) es un paquete del sistema protegido; no se toca." Warn
        return $false
    }

    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        Write-EmiLog "$($pkg.Name) removida (usuario actual)." Ok

        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -eq $pkg.Name }
        if ($prov) {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
            Write-EmiLog "$($pkg.Name) removida de provisioned packages." Ok
        }

        # Solo datos: Undo-EmiChanges hace el Add-AppxPackage -Register
        Add-EmiJournalEntry @{
            Kind              = 'Command'
            Action            = 'AppxReinstall'
            PackageName       = $pkg.Name
            PackageFamilyName = $pkg.PackageFamilyName
            Module            = 'Apps'
        }
        return $true
    } catch {
        Write-EmiLog "Error removiendo $($pkg.Name): $($_.Exception.Message)" Error
        return $false
    }
}

# ============================================================
# Limpiar la cache de una app (carpeta LocalCache\ y AC\Temp)
# ============================================================
function Clear-EmiAppCache {
    param([Parameter(Mandatory)][string] $PackageFamilyName)

    $base = Join-Path $env:LOCALAPPDATA "Packages\$PackageFamilyName"
    if (-not (Test-Path -LiteralPath $base)) {
        Write-EmiLog "Sin carpeta de datos para $PackageFamilyName; omitida." Info
        return 0
    }

    $targets = @(
        (Join-Path $base 'LocalCache'),
        (Join-Path $base 'AC\Temp'),
        (Join-Path $base 'AC\INetCache')
    )

    $freed = 0
    foreach ($t in $targets) {
        if (Test-Path -LiteralPath $t) {
            try {
                $size = (Get-ChildItem -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue |
                         Measure-Object -Property Length -Sum).Sum
                if ($null -eq $size) { $size = 0 }
                Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
                $freed += [long]$size
            } catch {
                Write-EmiLog "No se pudo limpiar $t : $($_.Exception.Message)" Warn
            }
        }
    }

    if ($freed -gt 0) {
        Write-EmiLog "Cache de $PackageFamilyName limpiada: $(Format-EmiSize $freed) liberados." Ok
    } else {
        Write-EmiLog "Cache de $PackageFamilyName ya estaba limpia." Info
    }
    return $freed
}

# ============================================================
# Resolver familia desde PackageFullName y limpiar cache
# ============================================================
function Clear-EmiAppCacheByFullName {
    param([Parameter(Mandatory)][string] $PackageFullName)

    # El Tag guarda el PackageFullName: se busca ese paquete exacto.
    $pkg = Find-EmiAppxPackage -Packages @(Get-AppxPackage -ErrorAction SilentlyContinue) -FullName $PackageFullName
    if (-not $pkg) {
        $family = Get-EmiFamilyFromFullName $PackageFullName
        Write-EmiLog "$family ya no esta instalada; se intenta limpiar su carpeta igualmente." Info
        return (Clear-EmiAppCache -PackageFamilyName $family)
    }
    return (Clear-EmiAppCache -PackageFamilyName $pkg.PackageFamilyName)
}

Export-ModuleMember -Function Get-EmiInstalledApps, Remove-EmiInstalledApp, Clear-EmiAppCache, Clear-EmiAppCacheByFullName