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
        @{ Id='TempWin';    Name='Temporales de Windows';             Path="$env:SystemRoot\Temp";                                   Safe=$true;  Info='Cache temporal del sistema' }
        @{ Id='Prefetch';   Name='Prefetch';                          Path="$env:SystemRoot\Prefetch";                               Safe=$true;  Info='Se regenera solo; util si esta corrupto' }
        @{ Id='WU';         Name='Cache de Windows Update';           Path="$env:SystemRoot\SoftwareDistribution\Download";          Safe=$true;  Info='Instaladores ya aplicados'; NeedsService='wuauserv' }
        @{ Id='DO';         Name='Cache de Delivery Optimization';    Path="$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"; Safe=$true; Info='Trozos de actualizaciones P2P' }
        @{ Id='CrashDumps'; Name='Volcados de memoria y errores';     Path="$la\CrashDumps";                                         Safe=$true;  Info='Dumps de aplicaciones caidas' }
        @{ Id='WER';        Name='Informes de errores de Windows';    Path="$env:ProgramData\Microsoft\Windows\WER";                 Safe=$true;  Info='Reportes que se envian a Microsoft' }
        @{ Id='Thumbs';     Name='Cache de miniaturas e iconos';      Path="$la\Microsoft\Windows\Explorer";  Filter='*cache*.db';   Safe=$true;  Info='Se regenera solo' }
        @{ Id='Recycle';    Name='Papelera de reciclaje';             Path='__RECYCLE__';                                            Safe=$true;  Info='Vacia la papelera de todos los discos' }
        @{ Id='Logs';       Name='Registros (.log) de Windows';       Path="$env:SystemRoot\Logs";                                   Safe=$true;  Info='Historial de instalacion y CBS' }
        @{ Id='Panther';    Name='Restos de instalacion (Panther)';   Path="$env:SystemRoot\Panther";                                Safe=$true;  Info='Logs de setup de Windows' }
        @{ Id='Chrome';     Name='Cache de Google Chrome';            Path="$la\Google\Chrome\User Data\Default\Cache";              Safe=$true;  Info='No borra contrasenas ni sesiones' }
        @{ Id='Edge';       Name='Cache de Microsoft Edge';           Path="$la\Microsoft\Edge\User Data\Default\Cache";             Safe=$true;  Info='No borra contrasenas ni sesiones' }
        @{ Id='Zen';        Name='Cache de Zen Browser';              Path="$la\zen\Profiles";  Filter='cache2'; IsProfileCache=$true; Safe=$true; Info='No borra contrasenas ni sesiones' }
        @{ Id='Firefox';    Name='Cache de Firefox';                  Path="$la\Mozilla\Firefox\Profiles"; Filter='cache2'; IsProfileCache=$true; Safe=$true; Info='No borra contrasenas ni sesiones' }
        @{ Id='Teams';      Name='Cache de Microsoft Teams';          Path="$la\Packages\MSTeams_8wekyb3d8bbwe\LocalCache";          Safe=$false; Info='Cierra Teams antes' }
        @{ Id='NvCache';    Name='Cache de shaders NVIDIA / DirectX'; Path="$la\NVIDIA\DXCache";                                     Safe=$true;  Info='Se regenera al jugar' }
        @{ Id='DxCache';    Name='Cache de shaders D3D';              Path="$la\D3DSCache";                                          Safe=$true;  Info='Se regenera solo' }
        @{ Id='Downloads';  Name='Carpeta Descargas (revisar antes)'; Path="$u\Downloads";                                           Safe=$false; Info='OJO: son archivos del usuario' }
        @{ Id='WinOld';     Name='Windows.old (Windows anterior)';    Path="$env:SystemDrive\Windows.old";                           Safe=$false; Info='Elimina la opcion de volver a la version previa' }
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
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop }
            catch { }   # archivos en uso: se ignoran
        }
        if ($DeleteRoot) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue }

        $after = if (Test-Path -LiteralPath $Path) { Get-EmiFolderSize $Path } else { 0 }
        $freed = [math]::Max(0, $before - $after)
    }
    catch { Write-EmiLog "Limpieza de '$Path': $($_.Exception.Message)" Warn }

    return $freed
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
                    $svc = Get-Service wuauserv -ErrorAction SilentlyContinue
                    $wasRunning = ($svc -and $svc.Status -eq 'Running')
                    if ($wasRunning) { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue }
                    try {
                        $f = Clear-EmiPath $t.Path
                    } finally {
                        if ($wasRunning) { Start-Service wuauserv -ErrorAction SilentlyContinue }
                    }
                    $freed += $f
                    Write-EmiLog "Cache de Windows Update: $(Format-EmiSize $f)" Ok
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
                    $f = Clear-EmiPath $t.Path -DeleteRoot
                    $freed += $f
                    Write-EmiLog "Windows.old eliminado: $(Format-EmiSize $f)" Ok
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

function Invoke-EmiComponentCleanup {
    <#  DISM: limpia versiones antiguas de componentes (WinSxS). Lento. #>
    Write-EmiLog 'Ejecutando limpieza de componentes (DISM). Puede tardar varios minutos...' Step
    Set-EmiStatus 'Limpiando WinSxS con DISM...'
    try {
        $p = Start-Process -FilePath 'dism.exe' -ArgumentList '/Online','/Cleanup-Image','/StartComponentCleanup','/Quiet','/NoRestart' -Wait -PassThru -WindowStyle Hidden
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

function Remove-EmiFilesToRecycleBin {
    <#  Envia archivos a la papelera (reversible) en vez de borrarlos. #>
    param([string[]] $Paths)

    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    $freed = 0
    foreach ($p in $Paths) {
        try {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $sz = (Get-Item -LiteralPath $p -Force).Length
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $p,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            $freed += $sz
            Write-EmiLog "A la papelera: $p" Ok
        }
        catch { Write-EmiLog "No se pudo mover '$p': $($_.Exception.Message)" Warn }
    }
    return $freed
}

Export-ModuleMember -Function *-Emi*
