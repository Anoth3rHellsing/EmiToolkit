# =====================================================================
#  EmiStartup.psm1 - Programas que arrancan con Windows
#  Desactiva igual que el Administrador de tareas (StartupApproved),
#  por lo que el usuario puede volver a activarlos desde Windows.
# =====================================================================

$script:ApprovedKeys = @{
    'HKCU:Run'           = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    'HKCU:Run32'         = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
    'HKCU:StartupFolder' = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
    'HKLM:Run'           = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    'HKLM:Run32'         = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
    'HKLM:StartupFolder' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
}

# Nunca se desactivan: seguridad, audio, tactil y controladores.
$script:ProtectedStartup = @(
    'egui', 'eset', 'ekrn', 'esets', 'securityhealth', 'windows security',
    'defender', 'msmpeng', 'sophos', 'kaspersky', 'bitdefender', 'avast', 'avg',
    'rtkaud', 'realtek', 'nahimic', 'waves maxx', 'dolby', 'sound blaster',
    'synaptics', 'elan', 'touchpad', 'i2c', 'igfxtray', 'hotkey', 'atkosd',
    'dell', 'lenovo vantage', 'hp support', 'thinkpad', 'battery',
    'onedrive setup', 'ctfmon', 'securehealth',
    'mcafee', 'norton', 'malwarebytes', 'avira', 'trend micro', 'webroot', 'f-secure', 'panda'
)

# Se marcan para desactivar en modo basico (arrancan solos sin necesidad).
# No van aqui (auditoria de sistema, EmiStartup.psm1:27-39): clientes de
# sincronizacion (OneDrive, Dropbox, Drive: dejan de subir Escritorio y
# Documentos), actualizadores (Edge/WebView2 se quedaban sin parches),
# antivirus ni utilidades de perifericos (macros, DPI, ecualizador).
$script:KnownBloat = @(
    'spotify', 'discord', 'steam', 'epic games', 'epicgameslauncher', 'ea desktop', 'origin',
    'ubisoft', 'uplay', 'battle.net', 'gog galaxy', 'roblox', 'riot',
    'skype', 'zoom', 'teams', 'slack', 'telegram', 'whatsapp', 'signal',
    'adobe', 'acrotray', 'creative cloud', 'ccxprocess', 'adobegcinvoker',
    'itunes', 'ituneshelper', 'quicktime', 'bonjour',
    'cortana', 'copilot', 'microsoftedgeautolaunch', 'gamebar',
    'utorrent', 'bittorrent', 'qbittorrent',
    'ccleaner', 'iobit', 'driverbooster', 'advanced systemcare',
    'wps office', 'wpscloudsvr', 'sunlogin', 'todesk',
    'nvidia geforce experience', 'nvbackend',
    'opera', 'brave', 'vivaldi', 'yandex'
)

# Aunque casen con KnownBloat, nunca se recomiendan (se pueden desactivar a
# mano desde la lista). Actualizadores: se mira solo el NOMBRE de la entrada,
# porque Discord, Slack o Teams arrancan con el lanzador "Update.exe
# --processStart" de Squirrel. El resto (sincronizacion en la nube, antivirus
# y perifericos) se mira en el nombre y en el comando.
$script:NeverAutoName = @('update', 'updater', 'jusched')
$script:NeverAuto = @(
    'onedrive', 'dropbox', 'google drive', 'googledrivefs', 'backup and sync', 'icloud', 'megasync', 'nextcloud', 'pcloud',
    'mcafee', 'norton',
    'logitech', 'lghub', 'logioptions', 'logi options', 'razer', 'corsair', 'icue', 'steelseries', 'hyperx', 'ngenuity', 'armoury', 'msi center', 'wacom'
)

function Test-EmiProtectedName {
    param([string] $Text)
    $t = "$Text".ToLower()
    foreach ($p in $script:ProtectedStartup) { if ($t -like "*$p*") { return $true } }
    return $false
}

function Test-EmiBloatName {
    param([string] $Text)
    $t = "$Text".ToLower()
    foreach ($p in $script:KnownBloat) { if ($t -like "*$p*") { return $true } }
    return $false
}

function Test-EmiNeverAutoName {
    param([string] $Name, [string] $Command)
    $n = "$Name".ToLower(); $t = "$Name $Command".ToLower()
    foreach ($p in $script:NeverAutoName) { if ($n -like "*$p*") { return $true } }
    foreach ($p in $script:NeverAuto)     { if ($t -like "*$p*") { return $true } }
    return $false
}

function Test-EmiStartupRecommended {
    <#  Logica pura: se recomienda desactivar (y el modo basico lo hace) solo
        una entrada Run o de la carpeta Inicio, no protegida, que case con
        KnownBloat y no con NeverAuto. Las tareas programadas nunca: una
        tarea como MicrosoftEdgeUpdateTaskMachineCore tiene tambien su
        disparador diario y se desactivaba entera.  #>
    param([string] $Name, [string] $Command, [ValidateSet('REG','FOLDER','TASK')][string] $Kind)
    if ($Kind -eq 'TASK') { return $false }
    $text = "$Name $Command"
    if (Test-EmiProtectedName $text) { return $false }
    if (Test-EmiNeverAutoName -Name $Name -Command $Command) { return $false }
    return (Test-EmiBloatName $text)
}

function Get-EmiStartupState {
    <#  Lee el estado (habilitado/deshabilitado) desde StartupApproved. #>
    param([string] $ApprovedKey, [string] $Name)
    try {
        $v = (Get-ItemProperty -LiteralPath $ApprovedKey -Name $Name -ErrorAction SilentlyContinue).$Name
        if ($null -eq $v) { return $true }                 # sin entrada = habilitado
        if ($v -is [byte[]] -and $v.Length -ge 1) { return -not ($v[0] -band 0x01) }
        return $true
    } catch { return $true }
}

function Set-EmiStartupState {
    <#  Habilita o deshabilita una entrada usando el mismo formato que Windows. #>
    param([string] $ApprovedKey, [string] $Name, [bool] $Enabled)

    try {
        if (-not (Test-Path -LiteralPath $ApprovedKey)) { New-Item -Path $ApprovedKey -Force | Out-Null }

        $blob = New-Object byte[] 12
        if ($Enabled) {
            $blob[0] = 2       # habilitado
        } else {
            $blob[0] = 3       # deshabilitado + marca de tiempo
            $ticks = [BitConverter]::GetBytes([DateTime]::Now.ToFileTime())
            [Array]::Copy($ticks, 0, $blob, 4, 8)
        }

        $old = (Get-ItemProperty -LiteralPath $ApprovedKey -Name $Name -ErrorAction SilentlyContinue).$Name
        Add-EmiJournalEntry @{
            Kind='Registry'; Path=$ApprovedKey; Name=$Name; Existed=($null -ne $old)
            OldValue=$old; OldType='Binary'; Module='Arranque'
        }

        New-ItemProperty -LiteralPath $ApprovedKey -Name $Name -Value $blob -PropertyType Binary -Force -ErrorAction Stop | Out-Null
        return $true
    }
    catch { Write-EmiLog "Arranque '$Name': $($_.Exception.Message)" Warn; return $false }
}

function Get-EmiStartupItems {
    <#  Enumera Run, RunOnce, carpetas de Inicio y tareas de inicio de sesion. #>
    $items = New-Object System.Collections.ArrayList

    $runKeys = @(
        @{ Key='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';                    Approved='HKCU:Run';   Scope='Usuario' }
        @{ Key='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';                    Approved='HKLM:Run';   Scope='Equipo'  }
        @{ Key='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';        Approved='HKLM:Run32'; Scope='Equipo (32b)' }
    )

    foreach ($rk in $runKeys) {
        if (-not (Test-Path -LiteralPath $rk.Key)) { continue }
        $props = Get-ItemProperty -LiteralPath $rk.Key -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            $cmd     = [string]$p.Value
            $enabled = Get-EmiStartupState -ApprovedKey $script:ApprovedKeys[$rk.Approved] -Name $p.Name
            $prot    = (Test-EmiProtectedName "$($p.Name) $cmd")

            $it = New-Object EmiItem
            $it.Name        = $p.Name
            $it.Detail      = $cmd
            $it.Path        = $rk.Key
            $it.Tag         = "REG|$($rk.Approved)|$($p.Name)"
            $it.Category    = $rk.Scope
            $it.Status      = if ($enabled) { 'Activo' } else { 'Desactivado' }
            $it.Locked      = $prot
            $it.Recommended = Test-EmiStartupRecommended -Name $p.Name -Command $cmd -Kind 'REG'
            $it.Selected    = $it.Recommended -and $enabled
            $it.SizeText    = if ($prot) { 'protegido' } elseif ($it.Recommended) { 'innecesario' } else { '' }
            [void]$items.Add($it)
        }
    }

    # Carpetas de inicio
    $folders = @(
        @{ P=[Environment]::GetFolderPath('Startup');       S='Usuario'; A='HKCU:StartupFolder' }
        @{ P=[Environment]::GetFolderPath('CommonStartup'); S='Equipo';  A='HKLM:StartupFolder' }
    )
    foreach ($f in $folders) {
        if (-not $f.P -or -not (Test-Path -LiteralPath $f.P)) { continue }
        Get-ChildItem -LiteralPath $f.P -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object {
                $enabled = Get-EmiStartupState -ApprovedKey $script:ApprovedKeys[$f.A] -Name $_.Name
                $prot    = Test-EmiProtectedName $_.Name

                $it = New-Object EmiItem
                $it.Name        = [IO.Path]::GetFileNameWithoutExtension($_.Name)
                $it.Detail      = $_.FullName
                $it.Path        = $f.P
                $it.Tag         = "FOLDER|$($f.A)|$($_.Name)"
                $it.Category    = "Carpeta Inicio ($($f.S))"
                $it.Status      = if ($enabled) { 'Activo' } else { 'Desactivado' }
                $it.Locked      = $prot
                $it.Recommended = Test-EmiStartupRecommended -Name $_.Name -Kind 'FOLDER'
                $it.Selected    = $it.Recommended -and $enabled
                $it.SizeText    = if ($prot) { 'protegido' } elseif ($it.Recommended) { 'innecesario' } else { '' }
                [void]$items.Add($it)
            }
    }

    # Tareas programadas que arrancan al iniciar sesion
    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\Windows\*' -and
                           ($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' }) } |
            ForEach-Object {
                $prot = Test-EmiProtectedName "$($_.TaskName) $($_.TaskPath)"
                $it = New-Object EmiItem
                $it.Name        = $_.TaskName
                $it.Detail      = "Tarea programada  $($_.TaskPath)"
                $it.Path        = $_.TaskPath
                $it.Tag         = "TASK|$($_.TaskPath)|$($_.TaskName)"
                $it.Category    = 'Tarea de inicio'
                $it.Status      = 'Activo'
                $it.Locked      = $prot
                $it.Recommended = Test-EmiStartupRecommended -Name $_.TaskName -Kind 'TASK'   # siempre $false
                $it.Selected    = $false
                $it.SizeText    = if ($prot) { 'protegido' } else { 'revisar' }
                [void]$items.Add($it)
            }
    } catch { }

    Write-EmiLog "$($items.Count) programas de arranque encontrados." Ok
    return $items
}

function Disable-EmiStartupItem {
    <#  Desactiva por Tag: "REG|clave|nombre", "FOLDER|clave|archivo", "TASK|ruta|nombre". #>
    param([Parameter(Mandatory)][string] $Tag)

    $parts = $Tag -split '\|', 3
    if ($parts.Count -lt 3) { return $false }

    switch ($parts[0]) {
        'REG'    { return Set-EmiStartupState -ApprovedKey $script:ApprovedKeys[$parts[1]] -Name $parts[2] -Enabled $false }
        'FOLDER' { return Set-EmiStartupState -ApprovedKey $script:ApprovedKeys[$parts[1]] -Name $parts[2] -Enabled $false }
        'TASK'   { return Disable-EmiScheduledTask -TaskPath $parts[1] -TaskName $parts[2] -Module 'Arranque' }
    }
    return $false
}

function Enable-EmiStartupItem {
    param([Parameter(Mandatory)][string] $Tag)
    $parts = $Tag -split '\|', 3
    if ($parts.Count -lt 3) { return $false }
    switch ($parts[0]) {
        'REG'    { return Set-EmiStartupState -ApprovedKey $script:ApprovedKeys[$parts[1]] -Name $parts[2] -Enabled $true }
        'FOLDER' { return Set-EmiStartupState -ApprovedKey $script:ApprovedKeys[$parts[1]] -Name $parts[2] -Enabled $true }
        'TASK'   { try { Enable-ScheduledTask -TaskPath $parts[1] -TaskName $parts[2] -ErrorAction Stop | Out-Null; return $true } catch { return $false } }
    }
    return $false
}

function Invoke-EmiStartupCleanup {
    <#  Desactiva las entradas indicadas (o las recomendadas si no se pasa ninguna). #>
    param([EmiItem[]] $Items)

    if (-not $Items -or $Items.Count -eq 0) {
        # Modo basico: solo entradas Run/carpeta Inicio recomendadas, nunca tareas.
        $Items = @(Get-EmiStartupItems | Where-Object { $_.Recommended -and -not $_.Locked -and $_.Tag -notlike 'TASK|*' })
    }

    $n = 0; $i = 0
    foreach ($it in $Items) {
        $i++
        if ($it.Locked) { Write-EmiLog "Se omite '$($it.Name)' (protegido)." Warn; continue }
        Set-EmiStatus "Desactivando $($it.Name)" ([int](($i / [math]::Max(1, $Items.Count)) * 100))

        if (Disable-EmiStartupItem -Tag $it.Tag) {
            $it.Status = 'Desactivado'
            $it.Selected = $false
            Write-EmiLog "Ya no arranca con Windows: $($it.Name)" Ok
            $n++
        }
    }

    Write-EmiLog "$n programas quitados del arranque." Ok
    Set-EmiStatus 'Arranque optimizado' 100
    return $n
}

Export-ModuleMember -Function *-Emi*
