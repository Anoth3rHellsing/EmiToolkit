# EmiApps.psm1 — Desinstalar apps AppX instaladas y limpiar su cache
# ADITIVO: no modifica ningun modulo existente. Usa helpers de EmiCore.

Set-StrictMode -Version Latest

# --- Paquetes del sistema que NUNCA deben ofrecerse para desinstalar ---
$script:ProtectedPrefixes = @(
    'Microsoft.Windows.ShellExperienceHost',
    'Microsoft.Windows.StartMenuExperienceHost',
    'Microsoft.Windows.SearchExperienceHost' # if present
    'Microsoft.AAD.BrokerPlugin',
    'Microsoft.Windows.CloudExperienceHost',
    'Microsoft.Windows.AssignedAccessLockApp',
    'Microsoft.Windows.CapturePicker',
    'Microsoft.Windows.ContentDeliveryManager',
    'Microsoft.Windows.PinningConfirmationDialog',
    'Microsoft.Windows.SecHealthUI',
    'Microsoft.WindowsAppRuntime.CBS',
    'Microsoft.UI.Xaml.',
    'Microsoft.Services.Store.Engagement',
    'Microsoft.WindowsXGpu',
    'Microsoft.YourPhoneGameBar' # placeholder; harmless if not present
    'windows.immersivecontrolpanel',
    'Microsoft.NET.Native',
    'Microsoft.VCLibs',
    'Microsoft.Windows.Cortana' # handled by Debloat with journal entry
)

# --- Rutas tipicas de cache/temp por familia de apps ---
$script:CacheDirs = @(
    "$env:LOCALAPPDATA\Packages"
)

function Test-EmiProtectedApp {
    param([Parameter(Mandatory)][string] $PackageFullName)
    foreach ($p in $script:ProtectedPrefixes) {
        if ($PackageFullName -like "$p*") { return $true }
    }
    return $false
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
    $pkgs = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework -eq $false })
    $items = New-Object System.Collections.ArrayList

    foreach ($pkg in $pkgs) {
        if (Test-EmiProtectedApp -PackageFullName $pkg.Name) { continue }

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

    $pkg = Get-AppxPackage -Name $PackageFullName -ErrorAction SilentlyContinue
    if (-not $pkg) {
        Write-EmiLog "$PackageFullName no esta instalada; omitida." Info
        return $false
    }
    if (Test-EmiProtectedApp -PackageFullName $pkg.Name) {
        Write-EmiLog "$($pkg.Name) es un paquete del sistema protegido; no se toca." Warn
        return $false
    }

    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        Write-EmiLog "$($pkg.Name) removida (usuario actual)." Ok

        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.PackageName -like "*$($pkg.Name)*" }
        if ($prov) {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
            Write-EmiLog "$($pkg.Name) removida de provisioned packages." Ok
        }

        Add-EmiJournalEntry @{
            Kind        = 'Command'
            Undo        = "Add-AppxPackage -Register (Get-AppxPackage -AllUsers -Name '$($pkg.Name)' | Where-Object { -not \$_.IsFramework } | Select-Object -First 1).InstallLocation -DisableDevelopmentMode -ErrorAction SilentlyContinue; Write-EmiLog 'Intenta reinstalar $($pkg.Name) con Add-AppxPackage -Register. Si falla, busca la app en Microsoft Store.' Info"
            Module      = 'Apps'
            PackageName = $pkg.Name
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

    # El Tag guarda el PackageFullName; extraer el Name (sin version/arquitectura)
    $name = ($PackageFullName -split '_')[0]
    $pkg = Get-AppxPackage -Name $name -ErrorAction SilentlyContinue
    if (-not $pkg) {
        Write-EmiLog "$name ya no esta instalada; se intenta limpiar su carpeta igualmente." Info
        return (Clear-EmiAppCache -PackageFamilyName ($PackageFullName -replace '_[0-9].*$', '_')) # best effort
    }
    return (Clear-EmiAppCache -PackageFamilyName $pkg.PackageFamilyName)
}

Export-ModuleMember -Function Get-EmiInstalledApps, Remove-EmiInstalledApp, Clear-EmiAppCache, Clear-EmiAppCacheByFullName