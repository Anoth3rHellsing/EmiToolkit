# =====================================================================
#  EmiSystem.psm1 - Zen Browser, inicio rapido y AnyDesk
# =====================================================================

# ------------------------------ ZEN BROWSER --------------------------

function Get-EmiZenInfo {
    <#  Detecta Zen. Si no esta instalado, no se toca nada. #>
    $paths = @(
        "$env:ProgramFiles\Zen Browser\zen.exe"
        "${env:ProgramFiles(x86)}\Zen Browser\zen.exe"
        "$env:LOCALAPPDATA\Programs\zen\zen.exe"
        "$env:LOCALAPPDATA\Zen Browser\zen.exe"
    )
    $exe = $paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if (-not $exe) {
        # Ultimo recurso: buscar el registro de clientes de Internet
        try {
            Get-ChildItem 'HKLM:\SOFTWARE\Clients\StartMenuInternet' -ErrorAction SilentlyContinue | ForEach-Object {
                $c = (Get-ItemProperty "$($_.PSPath)\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
                if ($c -match 'zen\.exe') {
                    # Recortar argumentos: quedarnos solo con la ruta del ejecutable
                    $exe = ($c -replace '"', '').Trim()
                    if ($exe -match '^(.*zen\.exe)') { $exe = $Matches[1] }
                }
            }
        } catch { }
    }

    $progId = $null
    if ($exe) {
        try {
            Get-ChildItem 'HKLM:\SOFTWARE\Clients\StartMenuInternet' -ErrorAction SilentlyContinue | ForEach-Object {
                $c = (Get-ItemProperty "$($_.PSPath)\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
                if ($c -match 'zen\.exe') { $progId = $_.PSChildName }
            }
        } catch { }
    }

    $current = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction SilentlyContinue).ProgId

    [pscustomobject]@{
        Installed  = [bool]$exe
        Path       = $exe
        ClientKey  = $progId
        CurrentDefault = $current
        IsDefault  = ($current -and $progId -and $current -like "$progId*") -or ($current -like '*Zen*')
    }
}

function Set-EmiZenDefault {
    <#  Usa el propio Zen (-setDefaultBrowser), que es el metodo admitido por
        Windows 11. Si no queda registrado, abre Configuracion para que el
        usuario confirme en dos clics. #>
    $zen = Get-EmiZenInfo

    if (-not $zen.Installed) {
        Write-EmiLog 'Zen Browser no esta instalado: no se cambia nada.' Warn
        return 'NotInstalled'
    }
    if ($zen.IsDefault) {
        Write-EmiLog 'Zen ya es el navegador predeterminado.' Ok
        return 'AlreadyDefault'
    }

    Write-EmiLog "Zen encontrado en $($zen.Path). Estableciendo como predeterminado..." Step
    try {
        # Sin privilegios y como el usuario: el navegador predeterminado es un
        # ajuste suyo (HKCU), y zen.exe suele estar en %LOCALAPPDATA%, donde
        # cualquier programa del usuario lo puede sustituir. Nunca elevado.
        [void](Start-EmiUnelevated -FilePath $zen.Path -Arguments '-setDefaultBrowser')
        Start-Sleep -Seconds 3
    }
    catch { Write-EmiLog "No se pudo invocar Zen: $($_.Exception.Message)" Warn }

    $after = Get-EmiZenInfo
    if ($after.IsDefault) {
        Write-EmiLog 'Zen es ahora el navegador predeterminado.' Ok
        return 'Done'
    }

    Write-EmiLog 'Windows pide confirmacion manual. Abriendo Configuracion > Aplicaciones predeterminadas...' Warn
    try { Open-EmiUrl 'ms-settings:defaultapps' } catch { }
    return 'NeedsUser'
}

function Open-EmiDefaultAppsSettings {
    try { Open-EmiUrl 'ms-settings:defaultapps'; return $true } catch { return $false }
}

# ---------------------------- INICIO RAPIDO --------------------------

function Get-EmiFastStartup {
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    $v = (Get-ItemProperty -LiteralPath $k -Name 'HiberbootEnabled' -ErrorAction SilentlyContinue).HiberbootEnabled
    $hiber = Test-Path -LiteralPath "$env:SystemDrive\hiberfil.sys"

    [pscustomobject]@{
        Enabled     = ($v -ne 0)
        RawValue    = $v
        HiberFile   = $hiber
        StatusText  = if ($v -eq 0) { 'Desactivado (correcto)' } else { 'ACTIVADO - conviene desactivarlo' }
    }
}

function Disable-EmiFastStartup {
    param([switch] $AlsoDisableHibernation)

    $st = Get-EmiFastStartup
    if (-not $st.Enabled) {
        Write-EmiLog 'El inicio rapido ya estaba desactivado.' Ok
        return $false
    }

    $ok = Set-EmiRegistry 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
                          'HiberbootEnabled' 0 DWord 'Energia'
    if ($ok) { Write-EmiLog 'Inicio rapido desactivado (el equipo se apagara de verdad).' Ok }

    if ($AlsoDisableHibernation) {
        try {
            & powercfg.exe /hibernate off | Out-Null
            Write-EmiLog 'Hibernacion desactivada: hiberfil.sys liberado.' Ok
        } catch { Write-EmiLog "Hibernacion: $($_.Exception.Message)" Warn }
    }
    return $ok
}

function Enable-EmiFastStartup {
    $ok = Set-EmiRegistry 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
                          'HiberbootEnabled' 1 DWord 'Energia'
    if ($ok) { Write-EmiLog 'Inicio rapido reactivado.' Ok }
    return $ok
}

# ------------------------------- ANYDESK -----------------------------

$script:AnyDeskPublisher = @('AnyDesk Software GmbH', 'philandro Software GmbH')

function Get-EmiAnyDeskId {
    <#  Lee la direccion de AnyDesk de su configuracion (ad.anynet.id) sin
        ejecutar nada. Primero la del servicio instalado, luego la del usuario. #>
    foreach ($f in @(
        "$env:ProgramData\AnyDesk\system.conf"
        "$env:ProgramData\AnyDesk\service.conf"
        "$env:APPDATA\AnyDesk\system.conf"
        "$env:APPDATA\AnyDesk\service.conf"
    )) {
        try {
            if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
            if ((Get-Item -LiteralPath $f).Length -gt 1MB) { continue }
            foreach ($l in [IO.File]::ReadAllLines($f)) {
                if ($l -match '^\s*ad\.anynet\.id\s*=\s*(\d{6,12})\s*$') { return $Matches[1] }
            }
        } catch { }
    }
    return $null
}

function Get-EmiAnyDeskInfo {
    <#  «Instalado» = AnyDesk.exe en Program Files con firma valida de AnyDesk.
        «Descargado» = hay un AnyDesk.exe en Descargas (no se ejecuta nunca:
        cualquier programa del usuario puede dejar ahi un .exe o una DLL). #>
    $exe = $null; $why = $null
    foreach ($p in @("$env:ProgramFiles\AnyDesk\AnyDesk.exe", "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe")) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        $t = Test-EmiTrustedExecutable -Path $p -Publisher $script:AnyDeskPublisher
        if ($t.Ok) { $exe = $t.Path; break }
        $why = $t.Reason
        Write-EmiLog "AnyDesk en $p no se usa: $($t.Reason)." Warn
    }
    $running = [bool](Get-Process AnyDesk -ErrorAction SilentlyContinue)

    [pscustomobject]@{
        Installed  = [bool]$exe
        Path       = $exe
        Running    = $running
        Id         = Get-EmiAnyDeskId
        Downloaded = (Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\AnyDesk.exe'))
        Rejected   = $why
    }
}

function Get-EmiAnyDeskSteps {
    @(
        [pscustomobject]@{ N=1; T='Descargar AnyDesk';        D='Pulsa el boton verde. Se abre anydesk.com y empieza la descarga del archivo AnyDesk.exe.' }
        [pscustomobject]@{ N=2; T='Abrir el archivo';         D='Cuando termine, abre AnyDesk.exe desde la carpeta Descargas (o desde la barra del navegador).' }
        [pscustomobject]@{ N=3; T='Aceptar el aviso azul';    D='Si Windows muestra "Windows protegio tu PC", pulsa Mas informacion y luego Ejecutar de todas formas.' }
        [pscustomobject]@{ N=4; T='Instalar en el equipo';    D='En la ventana de AnyDesk elige Instalar AnyDesk y acepta las opciones por defecto.' }
        [pscustomobject]@{ N=5; T='Anotar tu direccion';      D='Arriba a la izquierda aparece un numero de 9 o 10 cifras: esa es tu direccion de AnyDesk.' }
        [pscustomobject]@{ N=6; T='Compartir el numero';      D='Pasa ese numero a quien te va a asistir y acepta la solicitud cuando aparezca en pantalla.' }
    )
}

function Open-EmiAnyDeskDownload {
    <#  Abre la pagina oficial de descarga en el navegador del usuario. #>
    try {
        Open-EmiUrl 'https://anydesk.com/es/downloads/windows'
        Write-EmiLog 'Se abrio la pagina oficial de descarga de AnyDesk.' Ok
        return $true
    }
    catch { Write-EmiLog "No se pudo abrir el navegador: $($_.Exception.Message)" Warn; return $false }
}

function Open-EmiDownloadsFolder {
    try { Start-Process explorer.exe "$env:USERPROFILE\Downloads"; return $true } catch { return $false }
}

function Start-EmiAnyDesk {
    <#  Abre el AnyDesk instalado (firmado, en Program Files) como el usuario,
        sin privilegios de administrador. El de Descargas nunca se lanza. #>
    $a = Get-EmiAnyDeskInfo
    if (-not $a.Installed) { return $false }
    try { [void](Start-EmiUnelevated -FilePath $a.Path); return $true }
    catch { Write-EmiLog "No se pudo abrir AnyDesk: $($_.Exception.Message)" Warn; return $false }
}

# ----------------------------- RESUMEN GENERAL -----------------------

function Get-EmiSystemSummary {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $up   = (Get-Date) - $os.LastBootUpTime

    [pscustomobject]@{
        Computer  = $env:COMPUTERNAME
        User      = $env:USERNAME
        OS        = "$($os.Caption) ($($os.BuildNumber))"
        Cpu       = $cpu.Name.Trim()
        Ram       = Format-EmiSize ($cs.TotalPhysicalMemory)
        Uptime    = '{0}d {1}h {2}m' -f $up.Days, $up.Hours, $up.Minutes
        Admin     = Test-EmiAdmin
    }
}

Export-ModuleMember -Function *-Emi*
