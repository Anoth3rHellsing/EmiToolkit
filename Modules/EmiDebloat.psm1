# EmiDebloat.psm1 — App removal y Optional Features (Win11Debloat integration)
# ADITIVO: no modifica ningun modulo existente. Usa helpers de EmiCore.

Set-StrictMode -Version Latest

# --- Catalogo de apps bloatware removibles ---
$script:BloatApps = @(
    @{ Id='RemoveBingNews';      Pkg='Microsoft.BingNews_8wekyb3d8bbwe';                Name='Bing News';              Recommended=$true;  Info='Noticias MSN integradas' }
    @{ Id='RemoveBingWeather';   Pkg='Microsoft.BingWeather_8wekyb3d8bbwe';               Name='Bing Weather';           Recommended=$true;  Info='App del tiempo MSN' }
    @{ Id='RemoveZuneVideo';     Pkg='Microsoft.ZuneVideo_8wekyb3d8bbwe';                 Name='Películas y TV';         Recommended=$true;  Info='Reproductor de video legacy' }
    @{ Id='RemoveZuneMusic';     Pkg='Microsoft.ZuneMusic_8wekyb3d8bbwe';                 Name='Reproductor multimedia (el actual)'; Recommended=$false; Info='AVISO: es el reproductor de audio y video por defecto de Windows 11; sin el y sin Películas y TV no queda reproductor' }
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
    @{ Id='RemoveTeamsConsumer'; Pkg='MSTeams_8wekyb3d8bbwe';                             Name='Microsoft Teams (nuevo)'; Recommended=$false; Info='AVISO: es el Teams actual, el mismo que se usa para trabajo y clase' }
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

# Paquete por PackageFamilyName o, si no, por Name (exactos).
function Find-EmiAppxByFamily {
    param([object[]] $Packages, [string] $Family)
    foreach ($p in $Packages) { if ($p.PackageFamilyName -eq $Family) { return $p } }
    foreach ($p in $Packages) { if ($p.Name -eq $Family) { return $p } }
    return $null
}

# ============================================================
# Catalogo unificado: apps + optional features
# ============================================================
function Get-EmiDebloatItems {
    $items = @()

    # Pkg es un PackageFamilyName (Nombre_IdEditor) y Get-AppxPackage -Name solo
    # compara con Name: se lee la lista una vez y se filtra por familia.
    $allPkgs = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    $rev = Get-EmiAppxReversibility -Names @($allPkgs | ForEach-Object { [string]$_.Name })
    foreach ($app in $script:BloatApps) {
        $found = Find-EmiAppxByFamily -Packages $allPkgs -Family $app.Pkg
        $installed = $null -ne $found
        # Se avisa antes: sin otro usuario que la tenga, Windows borra sus archivos
        $back = if (-not $installed) { ' [NO INSTALADA]' }
                elseif ($rev[[string]$found.Name]) { '' }
                else { ' [Revertir no la devuelve: solo desde Microsoft Store]' }
        $items += [pscustomobject]@{
            Id          = $app.Id
            Name        = $app.Name
            Info        = "$($app.Info)$back"
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
            # Estado previo, para que deshacer lo deje como estaba (y no al reves)
            $before = $null
            try { $before = [string](Get-WindowsOptionalFeature -Online -FeatureName $feat.Feature -ErrorAction Stop).State } catch { }
            $wasOn = $before -in @('Enabled', 'EnablePending')
            if ($feat.Action -eq 'Enable') {
                Enable-WindowsOptionalFeature -Online -FeatureName $feat.Feature -NoRestart -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                Write-EmiLog "$($feat.Name) activado." Ok
            } else {
                Disable-WindowsOptionalFeature -Online -FeatureName $feat.Feature -NoRestart -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                Write-EmiLog "$($feat.Name) desactivado." Ok
            }
            if ($before -and ($wasOn -ne ($feat.Action -eq 'Enable'))) {
                Add-EmiJournalEntry @{ Kind='Command'; Action='WindowsFeature'; Feature=$feat.Feature; OldState=$before; Module=$M }
            }
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

    # 1. Verificar si esta instalada para el usuario actual. La tabla guarda el
    #    PackageFamilyName (Nombre_IdEditor), que Get-AppxPackage -Name no reconoce:
    #    se busca por familia y, si no, por nombre.
    $pkg = Find-EmiAppxByFamily -Packages @(Get-AppxPackage -ErrorAction SilentlyContinue) -Family $PackageFamilyName
    if (-not $pkg) {
        Write-EmiLog "$PackageFamilyName no esta instalada; omitida." Info
        return $false
    }

    # Antes de quitarla: si ningun otro usuario la tiene, Windows borra sus
    # archivos y Revertir no la puede devolver.
    $canBack = [bool](Get-EmiAppxReversibility -Names @([string]$pkg.Name))[[string]$pkg.Name]
    try {
        # 2. Remover para usuario actual
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        Write-EmiLog "$PackageFamilyName removida (usuario actual)." Ok
        if (-not $canBack) { Write-EmiLog "$PackageFamilyName no se podra devolver desde Revertir: si la necesitas, reinstalala desde Microsoft Store." Warn }

        # 3. Remover provisioned package (evita reinstalacion en updates)
        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -eq $pkg.Name }
        if ($prov) {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
            Write-EmiLog "$PackageFamilyName removida de provisioned packages." Ok
        }

        # 4. Journal: solo datos. Undo-EmiChanges lo vuelve a registrar con
        #    Add-AppxPackage -Register si el paquete sigue en disco (un
        #    PackageFamilyName no es un id de winget). Con Reversible=$false
        #    el deshacer solo avisa y la entrada sale del diario.
        Add-EmiJournalEntry @{
            Kind              = 'Command'
            Action            = 'AppxReinstall'
            PackageName       = $pkg.Name
            PackageFamilyName = $pkg.PackageFamilyName
            Reversible        = $canBack
            Module            = $Module
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
        $found = Find-EmiAppxByFamily -Packages $allPkgs -Family $app.Pkg
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