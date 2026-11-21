# =====================================================================
#  EmiDisk.psm1 - Discos, analisis de espacio y limpieza
# =====================================================================

function Get-EmiDisks {
    <#  Devuelve el estado de cada volumen con letra. #>
    $out = @()
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3 OR DriveType=2' -ErrorAction SilentlyContinue |
        ForEach-Object {
            if (-not $_.Size -or $_.Size -eq 0) { return }
            $used    = $_.Size - $_.FreeSpace
            $percent = [math]::Round(($used / $_.Size) * 100, 1)
            $label   = if ($_.VolumeName) { $_.VolumeName } else { 'Disco local' }

            $out += [pscustomobject]@{
                Letter    = $_.DeviceID
                Label     = $label
                Total     = [long]$_.Size
                Free      = [long]$_.FreeSpace
                Used      = [long]$used
                Percent   = $percent
                TotalText = Format-EmiSize $_.Size
                FreeText  = Format-EmiSize $_.FreeSpace
                UsedText  = Format-EmiSize $used
                FileSystem = $_.FileSystem
                Critical  = ($_.FreeSpace / $_.Size) -lt 0.10
            }
        }
    return $out
}

function Get-EmiCleanupTargets {
    <#  Catalogo de ubicaciones limpiables. Safe=$true se marca por defecto. #>
    $u = $env:USERPROFILE
    $la = $env:LOCALAPPDATA
    $t = @(
        @{ Id='TempUser';   Name='Archivos temporales del usuario';   Path=$env:TEMP;                                                Safe=$true;  Info='Basura de instaladores y apps' }
        @{ Id='TempWin';    Name='Temporales de Windows';             Path="$env:SystemRoot\Temp";                                   Safe=$true;  OlderThanDays=7; Info='Solo archivos de mas de 7 dias (un instalador en marcha los usa)' }
        @{ Id='Prefetch';   Name='Prefetch';                          Path="$env:SystemRoot\Prefetch";                               Safe=$false; Info='No acelera nada: Windows lo usa para abrir antes las apps y el proximo arranque ira mas lento' }
        @{ Id='WU';         Name='Cache de Windows Update';           Path="$env:SystemRoot\SoftwareDistribution\Download";          Safe=$true;  OlderThanDays=7; Info='Solo descargas de mas de 7 dias; se omite si hay un reinicio pendiente'; NeedsService='wuauserv' }
        @{ Id='DO';         Name='Cache de Delivery Optimization';    Path="$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"; Safe=$true; Info='Trozos de actualizaciones P2P (se borra con el cmdlet de Windows)' }
        @{ Id='CrashDumps'; Name='Volcados de memoria y errores';     Path="$la\CrashDumps";                                         Safe=$true;  Info='Dumps de aplicaciones caidas' }
        @{ Id='WER';        Name='Informes de errores de Windows';    Path="$env:ProgramData\Microsoft\Windows\WER";                 Safe=$true;  Info='Reportes que se envian a Microsoft' }
        @{ Id='Thumbs';     Name='Cache de miniaturas e iconos';      Path="$la\Microsoft\Windows\Explorer";  Filter='*cache*.db';   Safe=$true;  Info='Se regenera solo' }
        @{ Id='Recycle';    Name='Papelera de reciclaje';             Path='__RECYCLE__';                                            Safe=$false; Info='Borra PARA SIEMPRE lo que hay en la papelera de todos los discos' }
        @{ Id='Logs';       Name='Registros (.log) de Windows';       Path="$env:SystemRoot\Logs";                                   Safe=$false; Info='CBS, DISM y SetupDiag: hacen falta para diagnosticar una actualizacion fallida' }
        @{ Id='Panther';    Name='Restos de instalacion (Panther)';   Path="$env:SystemRoot\Panther";                                Safe=$false; Info='Logs de setup de Windows: hacen falta para diagnosticar una actualizacion fallida' }
        @{ Id='Chrome';     Name='Cache de Google Chrome';            Path="$la\Google\Chrome\User Data\Default\Cache";              Safe=$true;  Info='No borra contrasenas ni sesiones' }
        @{ Id='Edge';       Name='Cache de Microsoft Edge';           Path="$la\Microsoft\Edge\User Data\Default\Cache";             Safe=$true;  Info='No borra contrasenas ni sesiones' }
        @{ Id='Zen';        Name='Cache de Zen Browser';              Path="$la\zen\Profiles";  Filter='cache2'; IsProfileCache=$true; Safe=$true; Info='No borra contrasenas ni sesiones' }
        @{ Id='Firefox';    Name='Cache de Firefox';                  Path="$la\Mozilla\Firefox\Profiles"; Filter='cache2'; IsProfileCache=$true; Safe=$true; Info='No borra contrasenas ni sesiones' }
        @{ Id='Teams';      Name='Cache de Microsoft Teams';          Path="$la\Packages\MSTeams_8wekyb3d8bbwe\LocalCache";          Safe=$false; Info='Cierra Teams antes' }
        @{ Id='NvCache';    Name='Cache de shaders NVIDIA / DirectX'; Path="$la\NVIDIA\DXCache";                                     Safe=$false; Info='Los juegos daran tirones mientras se vuelven a compilar' }
        @{ Id='DxCache';    Name='Cache de shaders D3D';              Path="$la\D3DSCache";                                          Safe=$false; Info='Los juegos daran tirones mientras se vuelven a compilar' }
        @{ Id='Downloads';  Name='Carpeta Descargas (revisar antes)'; Path="$u\Downloads";                                           Safe=$false; Info='OJO: son archivos del usuario' }
        @{ Id='WinOld';     Name='Windows.old (Windows anterior)';    Path="$env:SystemDrive\Windows.old";                           Safe=$false; Info='Elimina la opcion de volver a la version previa; se borra con el Liberador de espacio de Windows' }
    )

    $list = @()
    foreach ($x in $t) { $list += [pscustomobject]$x }
    return $list
}

function Measure-EmiCleanupTargets {
    <#  Calcula el tamano de cada objetivo y devuelve EmiItem para la UI. #>
    param([switch] $OnlySafe)

    $targets = Get-EmiCleanupTargets
    $items   = New-Object System.Collections.ArrayList
    $i = 0

    foreach ($t in $targets) {
        $i++
        Set-EmiStatus "Analizando: $($t.Name)" ([int](($i / $targets.Count) * 100))

        $size = 0
        if ($t.Id -eq 'Recycle') {
            $size = Get-EmiRecycleBinSize
        }
        elseif ($t.IsProfileCache) {
            if (Test-Path -LiteralPath $t.Path) {
                Get-ChildItem -LiteralPath $t.Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $c = Join-Path $_.FullName 'cache2'
                    if (Test-Path -LiteralPath $c) { $size += Get-EmiFolderSize $c }
                }
            }
        }
        else {
            $size = Get-EmiFolderSize $t.Path
        }

        if ($OnlySafe -and -not $t.Safe) { continue }

        $it = New-Object EmiItem
        $it.Name        = $t.Name
        $it.Detail      = $t.Info
        $it.Path        = $t.Path
        $it.Tag         = $t.Id
        $it.Size        = $size
        $it.SizeText    = Format-EmiSize $size
        $it.Category    = if ($t.Safe) { 'Seguro' } else { 'Revisar' }
        $it.Recommended = [bool]$t.Safe
        $it.Selected    = ([bool]$t.Safe -and $size -gt 0)
        $it.Status      = if ($size -eq 0) { 'Vacio' } else { '' }
        [void]$items.Add($it)
    }

    Set-EmiStatus 'Analisis terminado' 100
    return $items
}

function Get-EmiRecycleBinSize {
    $total = 0
    try {
        $shell = New-Object -ComObject Shell.Application
        $bin   = $shell.NameSpace(0x0a)
        if ($bin) { foreach ($it in $bin.Items()) { $total += $it.Size } }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    } catch { }
    return $total
}

function Clear-EmiPath {
    <#  Vacia el contenido de una carpeta sin borrar la carpeta. Devuelve bytes liberados. #>
    param([string] $Path, [switch] $DeleteRoot)

    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $before = Get-EmiFolderSize $Path
    $freed  = 0

    try {
        # Sin seguir uniones ni enlaces (Temp y Windows\Temp los puede crear
        # cualquier usuario): ver Remove-EmiTreeSafe en EmiCore.
        Remove-EmiTreeSafe -Path $Path -ContentsOnly   # archivos en uso: se saltan
        if ($DeleteRoot) { try { Remove-EmiTreeSafe -Path $Path } catch { } }

        $after = if (Test-Path -LiteralPath $Path) { Get-EmiFolderSize $Path } else { 0 }
        $freed = [math]::Max(0, $before - $after)
    }
    catch { Write-EmiLog "Limpieza de '$Path': $($_.Exception.Message)" Warn }

    return $freed
}

function Test-EmiOlderThan {
    <#  Cierto si el elemento lleva mas de $Days dias sin crearse ni
        modificarse (lo mismo que hace cleanmgr con los temporales).  #>
    param([Parameter(Mandatory)] $Item, [int] $Days = 7, [datetime] $Now = (Get-Date))
    $limit = $Now.AddDays(-$Days)
    return ($Item.LastWriteTime -lt $limit -and $Item.CreationTime -lt $limit)
}

function Clear-EmiOldFiles {
    <#  Borra solo los archivos de mas de $Days dias dentro de $Path y luego
        las subcarpetas que hayan quedado vacias. Recorre a mano, sin
        -Recurse, y no entra en uniones ni enlaces simbolicos (Windows
        PowerShell 5.1 los sigue con -Recurse). Devuelve bytes liberados.  #>
    param([Parameter(Mandatory)][string] $Path, [int] $Days = 7)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return 0 }
    $now   = Get-Date
    $freed = [long]0
    $dirs  = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push((New-Object IO.DirectoryInfo $Path))

    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        $children = @()
        try { $children = @($d.GetFileSystemInfos()) } catch { continue }
        foreach ($c in $children) {
            if ($c.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($c -is [IO.DirectoryInfo]) { [void]$dirs.Add($c); $stack.Push($c); continue }
            if (-not (Test-EmiOlderThan -Item $c -Days $Days -Now $now)) { continue }
            $len = $c.Length
            try { Remove-Item -LiteralPath $c.FullName -Force -ErrorAction Stop; $freed += $len }
            catch { }   # en uso: se deja
        }
    }
    # Subcarpetas vacias, de la mas profunda a la mas alta (nunca la raiz).
    for ($i = $dirs.Count - 1; $i -ge 0; $i--) {
        $d = $dirs[$i]
        try {
            $d.Refresh()
            if ($d.Exists -and @($d.GetFileSystemInfos()).Count -eq 0 -and $d.CreationTime -lt $now.AddDays(-$Days)) { $d.Delete() }
        } catch { }
    }
    return $freed
}

function Test-EmiRebootPending {
    <#  Windows Update o el servicio de componentes esperan un reinicio. Borrar
        su cache en ese estado obliga a descargar otra vez o deja la
        actualizacion a medias.  #>
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    )
    foreach ($k in $keys) { if (Test-Path -LiteralPath $k) { return $true } }
    return $false
}

function Invoke-EmiCleanup {
    <#  Ejecuta la limpieza de los objetivos indicados (por Id). Devuelve bytes liberados. #>
    param([string[]] $Ids)

    $targets = Get-EmiCleanupTargets | Where-Object { $Ids -contains $_.Id }
    $freed   = 0
    $i = 0

    foreach ($t in $targets) {
        $i++
        Set-EmiStatus "Limpiando: $($t.Name)" ([int](($i / [math]::Max(1, $targets.Count)) * 100))
        Write-EmiLog "Limpiando $($t.Name)..." Step

        try {
            switch ($t.Id) {
                'Recycle' {
                    $sz = Get-EmiRecycleBinSize
                    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                    $freed += $sz
                    Write-EmiLog "Papelera vaciada ($(Format-EmiSize $sz))" Ok
                }
                'WU' {
                    if (Test-EmiRebootPending) {
                        Write-EmiLog 'Cache de Windows Update omitida: hay un reinicio pendiente. Reinicia y vuelve a limpiar.' Warn
                        break
                    }
                    $svc = Get-Service wuauserv -ErrorAction SilentlyContinue
                    $wasRunning = ($svc -and $svc.Status -eq 'Running')
                    if ($wasRunning) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }
                    try {
                        $f = Clear-EmiOldFiles -Path $t.Path -Days $t.OlderThanDays
                    } finally {
                        if ($wasRunning) { Start-Service wuauserv -ErrorAction SilentlyContinue }
                    }
                    $freed += $f
                    Write-EmiLog "Cache de Windows Update (mas de $($t.OlderThanDays) dias): $(Format-EmiSize $f)" Ok
                }
                'TempWin' {
                    $f = Clear-EmiOldFiles -Path $t.Path -Days $t.OlderThanDays
                    $freed += $f
                    Write-EmiLog "$($t.Name) (mas de $($t.OlderThanDays) dias): $(Format-EmiSize $f)" Ok
                }
                'DO' {
                    $before = Get-EmiFolderSize $t.Path
                    if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                        # El cmdlet de Windows sabe donde esta la cache y respeta al
                        # servicio DoSvc, que sigue en marcha.
                        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop }
                        catch { Write-EmiLog "Delivery Optimization: $($_.Exception.Message)" Warn }
                        $after = Get-EmiFolderSize $t.Path
                        $f = [math]::Max(0, $before - $after)
                    } else {
                        $f = Clear-EmiPath $t.Path
                        $f += Clear-EmiPath "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
                    }
                    $freed += $f
                    Write-EmiLog "$($t.Name): $(Format-EmiSize $f)" Ok
                }
                'Thumbs' {
                    $f = 0
                    Get-ChildItem -LiteralPath $t.Path -Filter '*cache*.db' -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        $f += $_.Length
                        try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch { }
                    }
                    $freed += $f
                    Write-EmiLog "Cache de miniaturas: $(Format-EmiSize $f)" Ok
                }
                { $_ -in 'Zen', 'Firefox' } {
                    $f = 0
                    if (Test-Path -LiteralPath $t.Path) {
                        Get-ChildItem -LiteralPath $t.Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                            $c = Join-Path $_.FullName 'cache2'
                            if (Test-Path -LiteralPath $c) { $f += Clear-EmiPath $c }
                        }
                    }
                    $freed += $f
                    Write-EmiLog "$($t.Name): $(Format-EmiSize $f)" Ok
                }
                'WinOld' {
                    $f = Remove-EmiWindowsOld -Path $t.Path
                    $freed += $f
                }
                default {
                    $f = Clear-EmiPath $t.Path
                    $freed += $f
                    Write-EmiLog "$($t.Name): $(Format-EmiSize $f)" Ok
                }
            }
        }
        catch { Write-EmiLog "Error limpiando $($t.Name): $($_.Exception.Message)" Warn }
    }

    Set-EmiStatus 'Limpieza terminada' 100
    Write-EmiLog "Espacio liberado: $(Format-EmiSize $freed)" Ok
    return $freed
}

function Remove-EmiWindowsOld {
    <#  Windows.old es de TrustedInstaller: Remove-Item como administrador lo
        deja a medias (sin volver atras y sin liberar casi nada). Se usa el
        Liberador de espacio, que es lo que hace Windows ("Instalaciones
        anteriores de Windows"), con /sagerun (Microsoft, "Automating Disk
        Cleanup"); StateFlags se pone solo para esa categoria y se quita al
        terminar. Despues se mide lo que queda y se dice tal cual. #>
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { Write-EmiLog 'No hay Windows.old.' Ok; return 0 }
    $before = Get-EmiFolderSize $Path
    $vc   = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Previous Installations'
    $flag = 'StateFlags0742'
    $cm   = Join-Path $env:SystemRoot 'System32\cleanmgr.exe'
    if ((Test-Path -LiteralPath $cm) -and (Test-Path -LiteralPath $vc)) {
        $old = (Get-ItemProperty -LiteralPath $vc -Name $flag -ErrorAction SilentlyContinue).$flag
        try {
            New-ItemProperty -LiteralPath $vc -Name $flag -Value 2 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-EmiLog 'Borrando Windows.old con el Liberador de espacio de Windows (puede tardar)...' Step
            $p = Start-Process -FilePath $cm -ArgumentList '/sagerun:742' -PassThru -WindowStyle Hidden
            if (-not $p.WaitForExit(3600000)) { Write-EmiLog 'El Liberador de espacio sigue trabajando despues de una hora; se deja terminar solo.' Warn }
        } catch { Write-EmiLog "Liberador de espacio: $($_.Exception.Message)" Warn }
        finally {
            try {
                if ($null -ne $old) { New-ItemProperty -LiteralPath $vc -Name $flag -Value $old -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
                else { Remove-ItemProperty -LiteralPath $vc -Name $flag -Force -ErrorAction Stop }
            } catch { }
        }
    } else {
        # Sin Liberador: se intenta, sin seguir uniones, y se informa de lo que quede
        Write-EmiLog 'No esta el Liberador de espacio: se borra Windows.old archivo por archivo.' Warn
        try { Remove-EmiTreeSafe -Path $Path } catch { }
    }
    $left = if (Test-Path -LiteralPath $Path) { Get-EmiFolderSize $Path } else { 0 }
    $freed = [math]::Max(0, $before - $left)
    if ($left -eq 0 -and -not (Test-Path -LiteralPath $Path)) {
        Write-EmiLog "Windows.old eliminado: $(Format-EmiSize $freed)" Ok
    } else {
        Write-EmiLog "Windows.old no se borro entero: liberado $(Format-EmiSize $freed), quedan $(Format-EmiSize $left). Ya no se puede volver a la version anterior. Para quitar el resto: Configuracion > Sistema > Almacenamiento > Archivos temporales > Instalaciones anteriores de Windows." Warn
    }
    return $freed
}

function Get-EmiComponentStoreAdvice {
    <#  Logica pura sobre la salida de DISM /AnalyzeComponentStore: la ultima
        linea "clave : valor" es "Limpieza recomendada : Si/No" en todos los
        idiomas. Devuelve $true, $false o $null (no se entiende). La consola
        de Windows PowerShell puede estropear la tilde de "Si", asi que se mira
        la primera letra: Y/S/O/J = si (Yes, Si, Sim, Oui, Ja); N = no. #>
    param([string[]] $Lines)
    $last = $null
    foreach ($l in $Lines) { if ("$l" -match ':\s*(\S+)\s*$' -and "$l" -notmatch '^\s*\[') { $last = $Matches[1] } }
    if (-not $last) { return $null }
    $c = $last.Substring(0, 1).ToUpperInvariant()
    if ($c -in @('Y', 'S', 'O', 'J')) { return $true }
    if ($c -eq 'N') { return $false }
    return $null
}

function Invoke-EmiComponentCleanup {
    <#  DISM: limpia versiones antiguas de componentes (WinSxS). Primero
        /AnalyzeComponentStore y solo limpia si DISM lo recomienda (o con
        -Force). /ResetBase solo con -ResetBase: impide desinstalar las
        actualizaciones ya instaladas (Microsoft, "Clean up the WinSxS
        folder"; ideas.md n.6). Lento. #>
    param([switch] $ResetBase, [switch] $Force)
    try {
        if (-not $Force) {
            Write-EmiLog 'Analizando el almacen de componentes (DISM /AnalyzeComponentStore)...' Step
            Set-EmiStatus 'Analizando WinSxS con DISM...'
            $out = @(& dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | ForEach-Object { "$_" })
            $code = $LASTEXITCODE
            $advice = if ($code -eq 0) { Get-EmiComponentStoreAdvice -Lines $out } else { $null }
            if ($code -ne 0) { Write-EmiLog "El analisis de DISM devolvio el codigo $code; se limpia igualmente." Warn }
            elseif ($advice -eq $false) { Write-EmiLog 'DISM dice que no hace falta limpiar los componentes: no se toca nada.' Ok; return $true }
            elseif ($null -eq $advice) { Write-EmiLog 'No se pudo leer la recomendacion de DISM; se limpia igualmente.' Warn }
        }
        $dargs = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
        if ($ResetBase) {
            $dargs += '/ResetBase'
            Write-EmiLog 'Con /ResetBase: despues ya no se podra desinstalar ninguna actualizacion instalada.' Warn
        }
        $dargs += @('/Quiet', '/NoRestart')
        Write-EmiLog 'Ejecutando limpieza de componentes (DISM). Puede tardar varios minutos...' Step
        Set-EmiStatus 'Limpiando WinSxS con DISM...'
        $p = Start-Process -FilePath 'dism.exe' -ArgumentList $dargs -Wait -PassThru -WindowStyle Hidden
        if ($p.ExitCode -eq 0) { Write-EmiLog 'Limpieza de componentes completada.' Ok; return $true }
        Write-EmiLog "DISM devolvio el codigo $($p.ExitCode)." Warn
        return $false
    }
    catch { Write-EmiLog "DISM: $($_.Exception.Message)" Warn; return $false }
}

function Find-EmiLargeFiles {
    <#  Busca los archivos mas pesados de una ruta. #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [int]    $MinMB = 100,
        [int]    $Top   = 200,
        [string] $Pattern = '*'
    )

    Write-EmiLog "Buscando archivos de mas de $MinMB MB en $Path ..." Step
    Set-EmiStatus "Escaneando $Path ..." 0

    $minBytes = $MinMB * 1MB
    $found    = New-Object System.Collections.ArrayList
    $count    = 0

    try {
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force -Filter $Pattern -ErrorAction SilentlyContinue |
            ForEach-Object {
                $count++
                if ($count % 2000 -eq 0) { Set-EmiStatus "Escaneando... $count archivos revisados" }
                if ($_.Length -ge $minBytes) { [void]$found.Add($_) }
            }
    }
    catch { Write-EmiLog "Escaneo: $($_.Exception.Message)" Warn }

    $items = New-Object System.Collections.ArrayList
    $found | Sort-Object Length -Descending | Select-Object -First $Top | ForEach-Object {
        $it = New-Object EmiItem
        $it.Name     = $_.Name
        $it.Detail   = $_.DirectoryName
        $it.Path     = $_.FullName
        $it.Size     = $_.Length
        $it.SizeText = Format-EmiSize $_.Length
        $it.Category = $_.Extension.ToLower()
        $it.Status   = $_.LastWriteTime.ToString('yyyy-MM-dd')
        $it.Selected = $false
        [void]$items.Add($it)
    }

    Write-EmiLog "$($items.Count) archivos grandes encontrados (de $count revisados)." Ok
    Set-EmiStatus 'Escaneo terminado' 100
    return $items
}

function Find-EmiLargeFolders {
    <#  Carpetas de primer nivel ordenadas por tamano. #>
    param([Parameter(Mandatory)][string] $Path, [int] $Top = 40)

    Write-EmiLog "Midiendo carpetas dentro de $Path ..." Step
    $dirs  = @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue)
    $items = New-Object System.Collections.ArrayList
    $i = 0

    foreach ($d in $dirs) {
        $i++
        Set-EmiStatus "Midiendo $($d.Name) ..." ([int](($i / [math]::Max(1, $dirs.Count)) * 100))
        $sz = Get-EmiFolderSize $d.FullName

        $it = New-Object EmiItem
        $it.Name     = $d.Name
        $it.Detail   = $d.FullName
        $it.Path     = $d.FullName
        $it.Size     = $sz
        $it.SizeText = Format-EmiSize $sz
        $it.Category = 'Carpeta'
        [void]$items.Add($it)
    }

    $sorted = New-Object System.Collections.ArrayList
    $items | Sort-Object Size -Descending | Select-Object -First $Top | ForEach-Object { [void]$sorted.Add($_) }

    Set-EmiStatus 'Medicion terminada' 100
    return $sorted
}

function Get-EmiRecycleRefusal {
    <#  Logica pura: por que un elemento NO puede ir a la papelera, o $null
        si cabe. Si no cabe o la unidad no tiene papelera, el shell lo borra
        para siempre sin avisar (con OnlyErrorDialogs), asi que se rechaza.  #>
    param(
        [bool]   $IsUnc,
        [string] $DriveType,          # Fixed, Removable, Network, CDRom, Ram...
        [long]   $SizeBytes,
        [long]   $MaxCapacityMB = -1, # -1 = desconocido
        [int]    $NukeOnDelete = 0,
        [long]   $VolumeBytes = 0
    )
    if ($IsUnc -or $DriveType -eq 'Network') { return 'esta en una unidad de red, que no tiene papelera' }
    if ($DriveType -ne 'Fixed') { return 'esta en una unidad extraible o sin papelera (USB, tarjeta...)' }
    if ($NukeOnDelete -eq 1) { return 'la papelera de esa unidad esta configurada para borrar sin guardar' }
    $cap = if ($MaxCapacityMB -ge 0) { $MaxCapacityMB * 1MB } elseif ($VolumeBytes -gt 0) { [long]($VolumeBytes * 0.05) } else { -1 }
    if ($cap -ge 0 -and $SizeBytes -gt $cap) {
        return "ocupa $(Format-EmiSize $SizeBytes) y la papelera de esa unidad admite $(Format-EmiSize $cap)"
    }
    return $null
}

function Get-EmiRecycleInfo {
    <#  Reune los datos de la unidad de $Path para Get-EmiRecycleRefusal.  #>
    param([string] $Path)
    $root  = [IO.Path]::GetPathRoot($Path)
    $info  = @{ IsUnc = $root.StartsWith('\\'); DriveType = 'Unknown'; MaxCapacityMB = -1; NukeOnDelete = 0; VolumeBytes = 0 }
    if ($info.IsUnc) { return $info }
    try { $di = New-Object IO.DriveInfo $root; $info.DriveType = "$($di.DriveType)"; $info.VolumeBytes = $di.TotalSize } catch { }
    try {
        $letter = $root.TrimEnd('\')
        $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$letter'" -ErrorAction Stop | Select-Object -First 1
        if ($vol -and $vol.DeviceID -match '(\{[0-9A-Fa-f-]+\})') {
            $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\$($Matches[1])"
            $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
            if ($p -and $null -ne $p.MaxCapacity)  { $info.MaxCapacityMB = [long]$p.MaxCapacity }
            if ($p -and $null -ne $p.NukeOnDelete) { $info.NukeOnDelete  = [int]$p.NukeOnDelete }
        }
    } catch { }
    return $info
}

function Remove-EmiFilesToRecycleBin {
    <#  Envia archivos o carpetas a la papelera (reversible). Rechaza lo que
        el shell borraria para siempre: unidades sin papelera y elementos
        mas grandes que su cuota. Si aun asi Windows no puede reciclarlo,
        SHFileOperation con FOF_WANTNUKEWARNING pregunta antes de borrar.  #>
    param([string[]] $Paths)

    if (-not ('EmiRecycle' -as [type])) {
        try {
            Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EmiRecycle
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd; public uint wFunc;
        [MarshalAs(UnmanagedType.LPWStr)] public string pFrom;
        [MarshalAs(UnmanagedType.LPWStr)] public string pTo;
        public ushort fFlags; public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszProgressTitle;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHFileOperation(ref SHFILEOPSTRUCT op);
    const uint FO_DELETE = 3;
    const ushort FOF_SILENT = 0x4, FOF_NOCONFIRMATION = 0x10, FOF_ALLOWUNDO = 0x40, FOF_NOERRORUI = 0x400, FOF_WANTNUKEWARNING = 0x4000;
    // 0 = enviado; 1 = el usuario cancelo; otro = codigo de error del shell.
    public static int ToRecycleBin(string path)
    {
        SHFILEOPSTRUCT op = new SHFILEOPSTRUCT();
        op.wFunc = FO_DELETE;
        op.pFrom = path + "\0\0";
        op.fFlags = (ushort)(FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI | FOF_WANTNUKEWARNING);
        int r = SHFileOperation(ref op);
        if (r == 0 && op.fAnyOperationsAborted) return 1;
        return r;
    }
}
'@ -ErrorAction Stop
        } catch { Write-EmiLog "No se pudo preparar la papelera: $($_.Exception.Message)" Warn; return 0 }
    }

    $freed = 0
    foreach ($p in $Paths) {
        try {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $item = Get-Item -LiteralPath $p -Force
            $sz = if ($item.PSIsContainer) { Get-EmiFolderSize $p } else { $item.Length }
            $ri = Get-EmiRecycleInfo -Path $item.FullName
            $why = Get-EmiRecycleRefusal -IsUnc $ri.IsUnc -DriveType $ri.DriveType -SizeBytes $sz `
                       -MaxCapacityMB $ri.MaxCapacityMB -NukeOnDelete $ri.NukeOnDelete -VolumeBytes $ri.VolumeBytes
            if ($why) {
                Write-EmiLog "No se envia a la papelera '$p': $why. Se borraria para siempre; si de verdad quieres borrarlo, hazlo desde el Explorador." Warn
                continue
            }
            $r = [EmiRecycle]::ToRecycleBin($item.FullName)
            if ($r -eq 0 -and -not (Test-Path -LiteralPath $p)) {
                $freed += $sz
                Write-EmiLog "A la papelera: $p" Ok
            }
            elseif ($r -eq 1) { Write-EmiLog "Cancelado, no se borra: $p" Warn }
            else { Write-EmiLog "No se pudo mover '$p' (codigo $r)." Warn }
        }
        catch { Write-EmiLog "No se pudo mover '$p': $($_.Exception.Message)" Warn }
    }
    return $freed
}

Export-ModuleMember -Function *-Emi*
