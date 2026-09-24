# EmiDebloat.psm1 — App removal y Optional Features (Win11Debloat integration)
# ADITIVO: no modifica ningun modulo existente. Usa helpers de EmiCore.

Set-StrictMode -Version Latest

# --- Catalogo de apps bloatware removibles ---
$script:BloatApps = @(
    @{ Id='RemoveBingNews';      Pkg='Microsoft.BingNews_8wekyb3d8bbwe';                Name='Bing News';              Recommended=$true;  Info='Noticias MSN integradas' }
    @{ Id='RemoveBingWeather';   Pkg='Microsoft.BingWeather_8wekyb3d8bbwe';               Name='Bing Weather';           Recommended=$true;  Info='App del tiempo MSN' }
    @{ Id='RemoveZuneVideo';     Pkg='Microsoft.ZuneVideo_8wekyb3d8bbwe';                 Name='Películas y TV';         Recommended=$true;  Info='Reproductor de video legacy' }
    @{ Id='RemoveZuneMusic';     Pkg='Microsoft.ZuneMusic_8wekyb3d8bbwe';                 Name='Groove Musica';          Recommended=$true;  Info='Reproductor de musica legacy' }
    @{ Id='RemoveSolitaire';     Pkg='Microsoft.MicrosoftSolitaireCollection_8wekyb3d8bbwe';Name='Solitario Collection'; Recommended=$true;  Info='Juegos de cartas con anuncios' }
    @{ Id='RemoveMixedReality';  Pkg='Microsoft.MixedReality.Portal_8wekyb3d8bbwe';       Name='Mixed Reality Portal';   Recommended=$true;  Info='Portal de realidad mixta' }
    @{ Id='RemoveSkypeApp';      Pkg='Microsoft.SkypeApp_kzf8qxf38zg5c';                  Name='Skype';                Recommended=$true;  Info='Cliente Skype UWP' }
    @{ Id='RemovePeople';        Pkg='Microsoft.People_8wekyb3d8bbwe';                    Name='Personas';             Recommended=$true;  Info='Contactos integrado' }
    @{ Id='RemoveMaps';          Pkg='Microsoft.WindowsMaps_8wekyb3d8bbwe';               Name='Mapas';                Recommended=$true;  Info='App de mapas offline' }
    @{ Id='RemoveStickyNotes';   Pkg='Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe';      Name='Sticky Notes';         Recommended=$false; Info='Notas adhesivas; algunos usuarios la necesitan' }
    @{ Id='RemoveVoiceRecorder'; Pkg='Microsoft.WindowsSoundRecorder_8wekyb3d8bbwe';      Name='Grabadora de voz';     Recommended=$false; Info='Grabacion de audio basica' }
    @{ Id='Remove3DViewer';      Pkg='Microsoft.Microsoft3DViewer_8wekyb3d8bbwe';         Name='Visor 3D';             Recommended=$true;  Info='Visor de modelos 3D' }
    @{ Id='RemovePaint3D';       Pkg='Microsoft.MSPaint_8wekyb3d8bbwe';                   Name='Paint 3D';             Recommended=$true;  Info='Editor 3D legacy' }
    @{ Id='RemoveClipchamp';     Pkg='Clipchamp.Clipchamp_yxz26nhyzhsrt';                 Name='Clipchamp';            Recommended=$true;  Info='Editor de video web-based' }
    @{ Id='RemoveTeamsConsumer'; Pkg='MSTeams_8wekyb3d8bbwe';                             Name='Teams (consumer)';     Recommended=$false; Info='AVISO: Teams personal, no empresarial' }
    @{ Id='RemoveOutlookNew';    Pkg='Microsoft.OutlookForWindows_8wekyb3d8bbwe';         Name='Nuevo Outlook';        Recommended=$false; Info='Outlook PWA reemplazo de Mail' }
    @{ Id='RemovePhoneLink';     Pkg='Microsoft.YourPhone_8wekyb3d8bbwe';                 Name='Enlace a telefono';    Recommended=$true;  Info='Sincronizacion movil-PC' }
    @{ Id='RemoveCortana';       Pkg='Microsoft.549981C3F5F10_8wekyb3d8bbwe';             Name='Cortana';              Recommended=$true;  Info='Asistente deprecated por MS' }
    @{ Id='RemoveGetHelp';       Pkg='Microsoft.GetHelp_8wekyb3d8bbwe';                   Name='Obtener ayuda';        Recommended=$true;  Info='App de soporte MS' }
    @{ Id='RemoveTips';          Pkg='Microsoft.Getstarted_8wekyb3d8bbwe';                Name='Consejos / Inicio';    Recommended=$true;  Info='Tutorial de bienvenida' }
    @{ Id='RemoveFeedbackHub';   Pkg='Microsoft.WindowsFeedbackHub_8wekyb3d8bbwe';        Name='Centro de comentarios';Recommended=$true;  Info='Feedback a Microsoft' }
    @{ Id='RemoveQuickAssist';   Pkg='MicrosoftCorporationII.QuickAssist_8wekyb3d8bbwe';  Name='Asistencia rapida';    Recommended=$false; Info='Soporte remoto; util para asistencia' }
    @{ Id='RemoveFamily';        Pkg='Microsoft.MicrosoftFamily_8wekyb3d8bbwe';           Name='Microsoft Family';     Recommended=$false; Info='Control parental; NO quitar si se usa' }
    @{ Id='RemoveDevHome';       Pkg='Microsoft.DevHome_8wekyb3d8bbwe';                   Name='Dev Home';             Recommended=$true;  Info='Dashboard de desarrollador' }
    @{ Id='RemoveCrossDevice';   Pkg='Microsoft.CrossDeviceExperienceHost_8wekyb3d8bbwe'; Name='Experiencia dispositivos';Recommended=$true; Info='Integracion entre dispositivos' }
)

# --- Optional Windows Features toggles ---
$script:OptionalFeatures = @(
    @{ Id='EnableSandbox';       Feature='Containers-DisposableClientVM'; Name='Windows Sandbox';        Action='Enable';  Recommended=$false; Info='Entorno aislado temporal; requiere virtualizacion' }
    @{ Id='EnableWSL';           Feature='Microsoft-Windows-Subsystem-Linux'; Name='WSL';                Action='Enable';  Recommended=$false; Info='Subsistema Linux para Windows' }
    @{ Id='DisableIECompat';     Feature='Internet-Explorer-Optional-amd64'; Name='IE Compatibility';   Action='Disable'; Recommended=$true;  Info='Herramientas de compatibilidad IE legacy' }
    @{ Id='DisableMediaPlayer';  Feature='WindowsMediaPlayer';               Name='WMP Legacy';         Action='Disable'; Recommended=$false; Info='AVISO: quita reproductor clasico' }
)

# ============================================================
# Catalogo unificado: apps + optional features
# ============================================================
function Get-EmiDebloatItems {
    $items = @()

    foreach ($app in $script:BloatApps) {
        $installed = $null -ne (Get-AppxPackage -Name $app.Pkg -ErrorAction SilentlyContinue)
        $items += [pscustomobject]@{
            Id          = $app.Id
            Name        = $app.Name
            Info        = "$($app.Info)$(if (-not $installed) { ' [NO INSTALADA]' })"
            Recommended = $app.Recommended
            Tag         = "APP|$($app.Pkg)"
            Category    = 'App'
        }
    }

    foreach ($feat in $script:OptionalFeatures) {
        $featObj = Get-WindowsOptionalFeature -Online -FeatureName $feat.Feature -ErrorAction SilentlyContinue
        $state = if ($featObj) { $featObj.State } else { 'No disponible' }
        $statusText = switch ($state) { 'Enabled' { '[ACTIVA]' } 'Disabled' { '[INACTIVA]' } 'No disponible' { '[N/D en esta edicion]' } default { "[${state}]" } }
        $items += [pscustomobject]@{
            Id          = $feat.Id
            Name        = $feat.Name
            Info        = "$($feat.Info) $statusText"
            Recommended = $feat.Recommended
            Tag         = "FEAT|$($feat.Feature)|$($feat.Action)"
            Category    = 'Feature'
        }
    }

    return $items
}

# ============================================================
# Ejecutor individual
# ============================================================
function Invoke-EmiDebloatItem {
    param([Parameter(Mandatory)][string] $Id)

    $M = 'Debloat'
    $n = 0

    # Buscar en apps
    $app = $script:BloatApps | Where-Object { $_.Id -eq $Id }
    if ($app) {
        if (Remove-EmiAppxPackage -PackageFamilyName $app.Pkg -Module $M) { $n++ }
        return $n
    }

    # Buscar en optional features
    $feat = $script:OptionalFeatures | Where-Object { $_.Id -eq $Id }
    if ($feat) {
        try {
            if ($feat.Action -eq 'Enable') {
                Enable-WindowsOptionalFeature -Online -FeatureName $feat.Feature -NoRestart -WarningAction SilentlyContinue | Out-Null
                Write-EmiLog "$($feat.Name) activado." Ok
            } else {
                Disable-WindowsOptionalFeature -Online -FeatureName $feat.Feature -NoRestart -WarningAction SilentlyContinue | Out-Null
                Write-EmiLog "$($feat.Name) desactivado." Ok
            }
            Add-EmiJournalEntry @{ Kind='Command'; Undo="Write-EmiLog 'Revierte $($feat.Name) manualmente desde Panel de Control > Caracteristicas de Windows' Warn"; Module=$M }
            $n++
        } catch {
            Write-EmiLog "$($feat.Name): $($_.Exception.Message)" Warn
        }
        return $n
    }

    Write-EmiLog "Debloat item desconocido: $Id" Warn
    return 0
}

# ============================================================
# Batch executor
# ============================================================
function Invoke-EmiDebloatSet {
    param([Parameter(Mandatory)][string[]] $Ids)

    if ($Ids.Count -eq 0) { return 0 }
    $total = $Ids.Count
    $done = 0
    $changes = 0

    foreach ($id in $Ids) {
        $done++
        Set-EmiStatus "Aplicando debloat ($done/$total): $id" ([int](($done / $total) * 100))
        $changes += Invoke-EmiDebloatItem -Id $id
    }

    Set-EmiStatus "Debloat completado: $changes cambios aplicados." 100
    return $changes
}

# ============================================================
# Helper seguro de remocion AppX con journal
# ============================================================
function Remove-EmiAppxPackage {
    param(
        [Parameter(Mandatory)][string] $PackageFamilyName,
        [string] $Module = 'Debloat'
    )

    # 1. Verificar si esta instalada para el usuario actual
    $pkg = Get-AppxPackage -Name $PackageFamilyName -ErrorAction SilentlyContinue
    if (-not $pkg) {
        Write-EmiLog "$PackageFamilyName no esta instalada; omitida." Info
        return $false
    }

    try {
        # 2. Remover para usuario actual
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        Write-EmiLog "$PackageFamilyName removida (usuario actual)." Ok

        # 3. Remover provisioned package (evita reinstalacion en updates)
        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.PackageName -like "*$PackageFamilyName*" }
        if ($prov) {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
            Write-EmiLog "$PackageFamilyName removida de provisioned packages." Ok
        }

        # 4. Journal entry con comando de reinstalacion
        Add-EmiJournalEntry @{
            Kind        = 'Command'
            Undo        = "winget install --id $PackageFamilyName --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null; Write-EmiLog 'Intenta reinstalar $PackageFamilyName via winget. Si falla, busca en Microsoft Store.' Info"
            Module      = $Module
            PackageName = $PackageFamilyName
        }

        return $true
    } catch {
        Write-EmiLog "Error removiendo $PackageFamilyName : $($_.Exception.Message)" Error
        return $false
    }
}

# ============================================================
# Lista de apps instaladas para UI (filtrada)
# ============================================================
function Get-EmiAppxList {
    $allPkgs = Get-AppxPackage -ErrorAction SilentlyContinue
    $results = @()
    foreach ($app in $script:BloatApps) {
        $found = $allPkgs | Where-Object { $_.Name -eq $app.Pkg }
        if ($found) {
            $results += [pscustomobject]@{
                Id      = $app.Id
                Name    = $app.Name
                Version = $found.Version
                Size    = ''  # AppX size not trivially available
            }
        }
    }
    return $results
}

Export-ModuleMember -Function Get-EmiDebloatItems, Invoke-EmiDebloatItem, Invoke-EmiDebloatSet, Remove-EmiAppxPackage, Get-EmiAppxList