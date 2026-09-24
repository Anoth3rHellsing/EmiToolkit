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
        Start-Process -FilePath $zen.Path -ArgumentList '-setDefaultBrowser' -WindowStyle Hidden -ErrorAction Stop
        Start-Sleep -Seconds 3
    }
    catch { Write-EmiLog "No se pudo invocar Zen: $($_.Exception.Message)" Warn }

    $after = Get-EmiZenInfo
    if ($after.IsDefault) {
        Write-EmiLog 'Zen es ahora el navegador predeterminado.' Ok
        return 'Done'
    }

    Write-EmiLog 'Windows pide confirmacion manual. Abriendo Configuracion > Aplicaciones predeterminadas...' Warn
    try { Start-Process 'ms-settings:defaultapps' } catch { }
    return 'NeedsUser'
}

function Open-EmiDefaultAppsSettings {
    try { Start-Process 'ms-settings:defaultapps'; return $true } catch { return $false }
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

function Get-EmiAnyDeskInfo {
    $paths = @(
        "$env:ProgramFiles\AnyDesk\AnyDesk.exe"
        "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe"
        "$env:APPDATA\AnyDesk\AnyDesk.exe"
        "$env:ProgramData\AnyDesk\AnyDesk.exe"
        "$env:USERPROFILE\Downloads\AnyDesk.exe"
    )
    $exe = $paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $running = [bool](Get-Process AnyDesk -ErrorAction SilentlyContinue)

    # El ID se guarda en el archivo de servicio cuando esta instalado como servicio
    $id = $null
    if ($exe) {
        try {
            $out = & $exe --get-id 2>$null
            if ($out) { $id = ("$out").Trim() }
        } catch { }
    }

    [pscustomobject]@{
        Installed = [bool]$exe
        Path      = $exe
        Running   = $running
        Id        = $id
        Downloaded = (Test-Path -LiteralPath "$env:USERPROFILE\Downloads\AnyDesk.exe")
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
        Start-Process 'https://anydesk.com/es/downloads/windows'
        Write-EmiLog 'Se abrio la pagina oficial de descarga de AnyDesk.' Ok
        return $true
    }
    catch { Write-EmiLog "No se pudo abrir el navegador: $($_.Exception.Message)" Warn; return $false }
}

function Open-EmiDownloadsFolder {
    try { Start-Process explorer.exe "$env:USERPROFILE\Downloads"; return $true } catch { return $false }
}

function Start-EmiAnyDesk {
    $a = Get-EmiAnyDeskInfo
    if (-not $a.Installed) { return $false }
    try { Start-Process $a.Path; return $true } catch { return $false }
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
