# =====================================================================
#  EmiVortex.psm1 - Deteccion y eliminacion de mods de Vortex
# =====================================================================

# --------------------- Deteccion de Vortex ---------------------------

function Get-EmiVortexInfo {
    <#  Detecta si Vortex esta instalado y devuelve rutas y juegos. #>
    $info = [pscustomobject]@{
        Installed       = $false
        InstallPath     = $null
        AppDataPath     = $null
        Games           = @()
        TotalStagingSize = 0
        TotalDownloadSize = 0
    }

    # Buscar en registro (HKCU y HKLM)
    $regPaths = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Vortex'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Vortex'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Vortex'
    )
    foreach ($rp in $regPaths) {
        if (Test-Path -LiteralPath $rp) {
            $props = Get-ItemProperty -LiteralPath $rp -ErrorAction SilentlyContinue
            if ($props) {
                $info.Installed = $true
                $info.InstallPath = $props.InstallLocation
                break
            }
        }
    }

    # Buscar AppData (modo normal y shared)
    $appDataNormal = Join-Path $env:APPDATA 'Vortex'
    $appDataShared = Join-Path $env:ProgramData 'Vortex'

    if (Test-Path -LiteralPath $appDataNormal) {
        $info.AppDataPath = $appDataNormal
        $info.Installed = $true
    } elseif (Test-Path -LiteralPath $appDataShared) {
        $info.AppDataPath = $appDataShared
        $info.Installed = $true
    }

    if (-not $info.Installed) { return $info }

    # Fallback para InstallPath si no estaba en registro
    if (-not $info.InstallPath) {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Vortex')
            'C:\Program Files\Black Tree Gaming Ltd\Vortex'
            'C:\Program Files (x86)\Black Tree Gaming Ltd\Vortex'
        )
        foreach ($c in $candidates) {
            if (Test-Path -LiteralPath (Join-Path $c 'Vortex.exe')) {
                $info.InstallPath = $c
                break
            }
        }
    }

    # Enumerar juegos con staging folder
    $games = New-Object System.Collections.ArrayList
    $modsRoot = Join-Path $info.AppDataPath '*'
    $totalStaging = 0
    $totalDownloads = 0

    Get-ChildItem -LiteralPath $info.AppDataPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $gameId = $_.Name
        # Saltar carpetas internas de Vortex que no son juegos
        if ($gameId -in @('downloads', 'temp', 'shared', 'plugins', 'extensions', 'locales', 'resources', 'node_modules', '.git')) { return }

        $modsDir = Join-Path $_.FullName 'mods'
        if (Test-Path -LiteralPath $modsDir) {
            $sz = Get-EmiFolderSize $modsDir
            $modCount = @(Get-ChildItem -LiteralPath $modsDir -Directory -ErrorAction SilentlyContinue).Count
            $totalStaging += $sz
            [void]$games.Add([pscustomobject]@{
                GameId      = $gameId
                ModsPath    = $modsDir
                ModCount    = $modCount
                StagingSize = $sz
            })
        }
    }

    # Tamano de descargas
    $dlDir = Join-Path $info.AppDataPath 'downloads'
    if (Test-Path -LiteralPath $dlDir) {
        $totalDownloads = Get-EmiFolderSize $dlDir
    }

    $info.Games = $games.ToArray()
    $info.TotalStagingSize = $totalStaging
    $info.TotalDownloadSize = $totalDownloads

    return $info
}

# ------------------- Items para la UI ListView -----------------------

function Get-EmiVortexItems {
    <#  Devuelve ArrayList de EmiItem con todos los mods detectados. #>
    $info = Get-EmiVortexInfo
    $items = New-Object System.Collections.ArrayList

    if (-not $info.Installed) {
        Write-EmiLog 'Vortex no esta instalado en este equipo.' Warn
        Set-EmiStatus 'Vortex no encontrado' 100
        return $items
    }

    Write-EmiLog "Vortex detectado en $($info.AppDataPath)" Ok
    Set-EmiStatus 'Analizando mods de Vortex...' 0

    $gameIndex = 0
    $totalGames = [math]::Max(1, $info.Games.Count)

    foreach ($game in $info.Games) {
        $gameIndex++
        Set-EmiStatus "Analizando: $($game.GameId)" ([int](($gameIndex / $totalGames) * 80))

        $modsDir = $game.ModsPath
        if (-not (Test-Path -LiteralPath $modsDir)) { continue }

        # Verificar si hay deployment manifest para este juego
        $deployedFiles = @{}
        $manifestPaths = _Get-EmiVortexManifestPaths -GameId $game.GameId
        foreach ($mp in $manifestPaths) {
            if (Test-Path -LiteralPath $mp) {
                try {
                    $manifest = Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($manifest.files) {
                        foreach ($f in $manifest.files) {
                            if ($f.source) { $deployedFiles[$f.source] = $true }
                        }
                    }
                } catch { }
            }
        }

        Get-ChildItem -LiteralPath $modsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $modName = $_.Name
            $modPath = $_.FullName
            $modSize = Get-EmiFolderSize $modPath

            $isDeployed = $false
            # Comprobar si algun archivo del manifiesto apunta a este mod
            foreach ($key in $deployedFiles.Keys) {
                if ($key -like "*$modName*") { $isDeployed = $true; break }
            }

            $it = New-Object EmiItem
            $it.Name        = $modName
            $it.Detail      = $game.GameId
            $it.Path        = $modPath
            $it.Tag         = "$($game.GameId)|$modName"
            $it.Size        = $modSize
            $it.SizeText    = Format-EmiSize $modSize
            $it.Category    = $game.GameId
            $it.Status      = if ($isDeployed) { '[OK] Activo' } else { '[STAGING] En staging' }
            $it.Locked      = $false
            $it.Recommended = $true
            $it.Selected    = $true
            [void]$items.Add($it)
        }
    }

    # Entrada especial: descargas
    $dlDir = Join-Path $info.AppDataPath 'downloads'
    if (Test-Path -LiteralPath $dlDir) {
        $dlSize = Get-EmiFolderSize $dlDir
        if ($dlSize -gt 0) {
            $it = New-Object EmiItem
            $it.Name        = '[CACHE] Descargas (seguro de borrar)'
            $it.Detail      = 'Archivos .7z/.zip originales - NO afecta mods instalados'
            $it.Path        = $dlDir
            $it.Tag         = '__DOWNLOADS__'
            $it.Size        = $dlSize
            $it.SizeText    = Format-EmiSize $dlSize
            $it.Category    = '[ESPACIO] Espacio recuperable'
            $it.Status      = '[CACHE] Solo cache'
            $it.Locked      = $false
            $it.Recommended = $false
            $it.Selected    = $false
            [void]$items.Add($it)
        }
    }

    # Entrada especial: base de datos state.v2
    $stateDir = Join-Path $info.AppDataPath 'state.v2'
    if (Test-Path -LiteralPath $stateDir) {
        $stSize = Get-EmiFolderSize $stateDir
        $it = New-Object EmiItem
        $it.Name        = 'Base de datos (state.v2)'
        $it.Detail      = 'Estado interno de Vortex: load order, perfiles, reglas'
        $it.Path        = $stateDir
        $it.Tag         = '__STATE__'
        $it.Size        = $stSize
        $it.SizeText    = Format-EmiSize $stSize
        $it.Category    = 'Datos de Vortex'
        $it.Status      = 'LevelDB'
        $it.Locked      = $false
        $it.Recommended = $false
        $it.Selected    = $false
        [void]$items.Add($it)
    }

    Set-EmiStatus 'Analisis terminado' 100
    Write-EmiLog "$($items.Count) elementos encontrados en Vortex." Ok
    return $items
}

# -------------------- Purgar mods seleccionados ----------------------

function Remove-EmiVortexMods {
    <#  Elimina los mods indicados por Tag. Devuelve numero de mods purgados. #>
    param([string[]] $Tags)

    if (-not $Tags -or $Tags.Count -eq 0) { return 0 }

    # Verificar que Vortex no esta corriendo
    if (Get-Process -Name 'Vortex' -ErrorAction SilentlyContinue) {
        Write-EmiLog 'Cierra Vortex antes de eliminar mods.' Warn
        return 0
    }

    $n = 0
    $i = 0
    $total = $Tags.Count

    foreach ($tag in $Tags) {
        $i++
        Set-EmiStatus "Purgando mod $i/$total" ([int](($i / $total) * 100))

        if ($tag -eq '__DOWNLOADS__') {
            $info = Get-EmiVortexInfo
            $dlDir = Join-Path $info.AppDataPath 'downloads'
            if (Test-Path -LiteralPath $dlDir) {
                Add-EmiJournalEntry @{ Kind='File'; Path=$dlDir; Backup=$null; Module='Vortex' }
                $freed = Clear-EmiPath $dlDir
                Write-EmiLog "Descargas eliminadas: $(Format-EmiSize $freed)" Ok
                $n++
            }
            continue
        }

        if ($tag -eq '__STATE__') {
            $info = Get-EmiVortexInfo
            $stateDir = Join-Path $info.AppDataPath 'state.v2'
            if (Test-Path -LiteralPath $stateDir) {
                Add-EmiJournalEntry @{ Kind='File'; Path=$stateDir; Backup=$null; Module='Vortex' }
                Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-EmiLog 'Base de datos state.v2 eliminada.' Ok
                $n++
            }
            continue
        }

        # Formato: GAMEID|MODNAME
        $parts = $tag.Split('|', 2)
        if ($parts.Count -ne 2) { Write-EmiLog "Tag invalido: $tag" Warn; continue }
        $gameId  = $parts[0]
        $modName = $parts[1]

        $info = Get-EmiVortexInfo
        $modPath = Join-Path $info.AppDataPath "$gameId\mods\$modName"

        if (-not (Test-Path -LiteralPath $modPath)) {
            Write-EmiLog "Mod no encontrado: $modName ($gameId)" Warn
            continue
        }

        # Intentar purgar hardlinks desde el manifiesto de despliegue
        $purged = _Purge-EmiVortexDeployedFiles -GameId $gameId -ModName $modName

        # Eliminar carpeta del mod en staging
        Add-EmiJournalEntry @{ Kind='File'; Path=$modPath; Backup=$null; Module='Vortex' }
        try {
            Remove-Item -LiteralPath $modPath -Recurse -Force -ErrorAction Stop
            $msg = 'Mod eliminado: ' + $modName + ' (' + $gameId + ') - ' + $purged + ' enlaces purgados'
            Write-EmiLog $msg Ok
            $n++
        }
        catch {
            $msg = 'No se pudo eliminar ' + $modName + ': ' + $_.Exception.Message
            Write-EmiLog $msg Warn
        }
    }

    Set-EmiStatus 'Purga terminada' 100
    Write-EmiLog "$n mods eliminados." Ok
    return $n
}

# -------------------- Eliminacion completa ---------------------------

function Remove-EmiVortexFull {
    <#  Elimina Vortex completamente: mods, datos, desinstalacion. #>

    # Verificar que Vortex no esta corriendo
    $vortexProc = Get-Process -Name 'Vortex' -ErrorAction SilentlyContinue
    if ($vortexProc) {
        Write-EmiLog 'Cerrando Vortex...' Step
        Stop-Process -Name 'Vortex' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $info = Get-EmiVortexInfo
    if (-not $info.Installed) {
        Write-EmiLog 'Vortex no esta instalado.' Warn
        return 0
    }

    $steps = 5
    $current = 0

    # Paso 1: Purgar todos los mods desplegados
    $current++
    Set-EmiStatus "Paso $current/$steps : Purgando mods desplegados..." ([int](($current / $steps) * 100))
    Write-EmiLog '=== Purgando todos los mods desplegados ===' Step

    foreach ($game in $info.Games) {
        $manifestPaths = _Get-EmiVortexManifestPaths -GameId $game.GameId
        foreach ($mp in $manifestPaths) {
            if (Test-Path -LiteralPath $mp) {
                try {
                    $manifest = Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($manifest.files) {
                        $removed = 0
                        foreach ($f in $manifest.files) {
                            if ($f.relPath) {
                                $targetPath = $f.relPath
                                # Si es ruta relativa al directorio del juego, construir ruta absoluta
                                $gameDir = Split-Path $mp -Parent
                                $fullTarget = Join-Path $gameDir $targetPath
                                if (Test-Path -LiteralPath $fullTarget) {
                                    if (_Test-EmiVortexHardlink -FilePath $fullTarget) {
                                        try {
                                            Remove-Item -LiteralPath $fullTarget -Force -ErrorAction Stop
                                            $removed++
                                        } catch { }
                                    }
                                }
                            }
                        }
                        if ($removed -gt 0) {
                            Write-EmiLog "$removed enlaces purgados de $($game.GameId)" Ok
                        }
                    }
                    # Borrar manifiesto
                    Add-EmiJournalEntry @{ Kind='File'; Path=$mp; Backup=$null; Module='Vortex' }
                    Remove-Item -LiteralPath $mp -Force -ErrorAction SilentlyContinue
                } catch { Write-EmiLog "Error procesando manifiesto: $($_.Exception.Message)" Warn }
            }
        }
    }

    # Paso 2: Eliminar AppData completo
    $current++
    Set-EmiStatus "Paso $current/$steps : Eliminando datos de Vortex..." ([int](($current / $steps) * 100))
    Write-EmiLog "Eliminando $($info.AppDataPath)..." Step

    Add-EmiJournalEntry @{ Kind='File'; Path=$info.AppDataPath; Backup=$null; Module='Vortex' }
    try {
        Remove-Item -LiteralPath $info.AppDataPath -Recurse -Force -ErrorAction Stop
        Write-EmiLog 'Datos de Vortex eliminados.' Ok
    }
    catch { Write-EmiLog "No se pudo eliminar AppData: $($_.Exception.Message)" Warn }

    # Paso 3: Ejecutar desinstalador silencioso
    $current++
    Set-EmiStatus "Paso $current/$steps : Desinstalando Vortex..." ([int](($current / $steps) * 100))

    if ($info.InstallPath) {
        $uninstaller = Join-Path $info.InstallPath 'Uninstall Vortex.exe'
        if (Test-Path -LiteralPath $uninstaller) {
            Write-EmiLog 'Ejecutando desinstalador de Vortex...' Step
            try {
                $proc = Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
                if ($proc -and $proc.ExitCode -eq 0) {
                    Write-EmiLog 'Vortex desinstalado correctamente.' Ok
                } else {
                    Write-EmiLog "Desinstalador devolvio codigo $($proc.ExitCode)." Warn
                }
            }
            catch { Write-EmiLog "Error ejecutando desinstalador: $($_.Exception.Message)" Warn }
        } else {
            Write-EmiLog 'Desinstalador no encontrado; se omite.' Warn
        }
    }

    # Paso 4: Limpiar registro
    $current++
    Set-EmiStatus "Paso $current/$steps : Limpiando registro..." ([int](($current / $steps) * 100))
    Write-EmiLog 'Limpiando claves de registro de Vortex...' Step

    $regKeys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Vortex'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Vortex'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Vortex'
        'HKCU:\SOFTWARE\Vortex'
    )
    foreach ($rk in $regKeys) {
        if (Test-Path -LiteralPath $rk) {
            Add-EmiJournalEntry @{ Kind='Registry'; Path=$rk; Name='(clave completa)'; Existed=$true; OldValue=$null; OldType='String'; NewValue=$null; Module='Vortex' }
            try {
                Remove-Item -LiteralPath $rk -Recurse -Force -ErrorAction Stop
                Write-EmLog "Clave eliminada: $rk" Ok
            }
            catch { Write-EmiLog "No se pudo eliminar $rk : $($_.Exception.Message)" Warn }
        }
    }

    # Paso 5: Limpiar manifests residuales en carpetas de juego
    $current++
    Set-EmiStatus "Paso $current/$steps : Limpiando residuos..." ([int](($current / $steps) * 100))
    Write-EmiLog 'Buscando vortex.deployment.json residuales...' Step

    $knownGameDirs = _Get-EmiVortexKnownGameDirs
    $residuals = 0
    foreach ($gd in $knownGameDirs) {
        $manifest = Join-Path $gd 'vortex.deployment.json'
        if (Test-Path -LiteralPath $manifest) {
            Add-EmiJournalEntry @{ Kind='File'; Path=$manifest; Backup=$null; Module='Vortex' }
            Remove-Item -LiteralPath $manifest -Force -ErrorAction SilentlyContinue
            $residuals++
        }
        # Variantes como vortex.deployment.bepinex-5.json
        Get-ChildItem -LiteralPath $gd -Filter 'vortex.deployment*.json' -ErrorAction SilentlyContinue | ForEach-Object {
            Add-EmiJournalEntry @{ Kind='File'; Path=$_.FullName; Backup=$null; Module='Vortex' }
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            $residuals++
        }
    }
    if ($residuals -gt 0) { Write-EmiLog "$residuals manifiestos residuales eliminados." Ok }

    Set-EmiStatus 'Eliminacion completa terminada' 100
    Write-EmiLog 'ELIMINACION COMPLETA DE VORTEX TERMINADA.' Ok
    return 1
}

# ======================== Helpers internos ============================

function _Get-EmiVortexManifestPaths {
    <#  Devuelve rutas posibles de vortex.deployment.json para un gameId. #>
    param([string] $GameId)

    $paths = New-Object System.Collections.ArrayList
    $knownDirs = _Get-EmiVortexKnownGameDirs -GameId $GameId

    foreach ($dir in $knownDirs) {
        if (Test-Path -LiteralPath $dir) {
            [void]$paths.Add((Join-Path $dir 'vortex.deployment.json'))
            # Buscar tambien en subcarpetas comunes
            $subDirs = @('Data', 'Mods', 'archive\pc\mod', 'Data\Paks\~mods')
            foreach ($sub in $subDirs) {
                $full = Join-Path $dir $sub
                if (Test-Path -LiteralPath $full) {
                    [void]$paths.Add((Join-Path $full 'vortex.deployment.json'))
                }
            }
        }
    }
    return $paths.ToArray()
}

function _Get-EmiVortexKnownGameDirs {
    <#  Devuelve carpetas de juego conocidas donde Vortex puede haber desplegado. #>
    param([string] $GameId)

    # Busqueda generica en unidades comunes
    $searchRoots = New-Object System.Collections.ArrayList
    foreach ($drive in @('C:', 'D:', 'E:', 'F:')) {
        if (Test-Path -LiteralPath $drive) { [void]$searchRoots.Add($drive) }
    }

    $dirs = New-Object System.Collections.ArrayList

    # Patrones conocidos por gameId
    $gamePatterns = @{
        'skyrimse'        = @('Steam\steamapps\common\Skyrim Special Edition', 'GOG Galaxy\Games\Skyrim Special Edition')
        'skyrim'          = @('Steam\steamapps\common\Skyrim', 'GOG Galaxy\Games\Skyrim')
        'fallout4'        = @('Steam\steamapps\common\Fallout 4', 'GOG Galaxy\Games\Fallout 4')
        'falloutnv'       = @('Steam\steamapps\common\Fallout New Vegas')
        'fallout3'        = @('Steam\steamapps\common\Fallout 3')
        'oblivion'        = @('Steam\steamapps\common\Oblivion')
        'cyberpunk2077'   = @('Steam\steamapps\common\Cyberpunk 2077', 'GOG Galaxy\Games\Cyberpunk 2077', 'Epic Games\Cyberpunk 2077')
        'stardewvalley'   = @('Steam\steamapps\common\Stardew Valley', 'GOG Galaxy\Games\Stardew Valley')
        'baldursgate3'    = @('Steam\steamapps\common\Baldurs Gate 3', 'GOG Galaxy\Games\Baldurs Gate 3')
        'Witcher3'        = @('Steam\steamapps\common\The Witcher 3', 'GOG Galaxy\Games\The Witcher 3')
        'starfield'       = @('Steam\steamapps\common\Starfield')
        'enderal'         = @('Steam\steamapps\common\Enderal')
        'morrowind'       = @('Steam\steamapps\common\Morrowind')
    }

    if ($GameId -and $gamePatterns.ContainsKey($GameId)) {
        foreach ($pattern in $gamePatterns[$GameId]) {
            foreach ($root in $searchRoots) {
                $full = Join-Path $root $pattern
                if (Test-Path -LiteralPath $full) { [void]$dirs.Add($full) }
                # Tambien buscar bajo Program Files
                $pf = Join-Path "${root}\Program Files" $pattern
                if (Test-Path -LiteralPath $pf) { [void]$dirs.Add($pf) }
                $pf86 = Join-Path "${root}\Program Files (x86)" $pattern
                if (Test-Path -LiteralPath $pf86) { [void]$dirs.Add($pf86) }
            }
        }
    } else {
        # Sin gameId especifico: devolver todas las carpetas de juego conocidas
        foreach ($gid in $gamePatterns.Keys) {
            foreach ($pattern in $gamePatterns[$gid]) {
                foreach ($root in $searchRoots) {
                    $full = Join-Path $root $pattern
                    if (Test-Path -LiteralPath $full) { [void]$dirs.Add($full) }
                }
            }
        }
    }

    return $dirs.ToArray()
}

function _Purge-EmiVortexDeployedFiles {
    <#  Purga hardlinks/symlinks desplegados de un mod concreto. Devuelve count. #>
    param([string] $GameId, [string] $ModName)

    $removed = 0
    $manifestPaths = _Get-EmiVortexManifestPaths -GameId $GameId

    foreach ($mp in $manifestPaths) {
        if (-not (Test-Path -LiteralPath $mp)) { continue }
        try {
            $manifest = Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $manifest.files) { continue }

            $gameDir = Split-Path $mp -Parent

            foreach ($f in $manifest.files) {
                if ($f.source -and $f.source -like "*$ModName*") {
                    $targetPath = if ($f.relPath) { Join-Path $gameDir $f.relPath } else { $null }
                    if ($targetPath -and (Test-Path -LiteralPath $targetPath)) {
                        if (_Test-EmiVortexHardlink -FilePath $targetPath) {
                            try {
                                Remove-Item -LiteralPath $targetPath -Force -ErrorAction Stop
                                $removed++
                            }
                            catch { Write-EmiLog "No se pudo purgar: $targetPath" Warn }
                        } else {
                            Write-EmiLog "Archivo real (no hardlink), se conserva: $targetPath" Warn
                        }
                    }
                }
            }
        }
        catch { Write-EmiLog "Error leyendo manifiesto: $($_.Exception.Message)" Warn }
    }
    return $removed
}

function _Test-EmiVortexHardlink {
    <#  Verifica si un archivo es hardlink (link count > 1). #>
    param([string] $FilePath)

    try {
        $fileInfo = [System.IO.FileInfo]::new($FilePath)
        # En .NET Framework 4.8 no hay LinkCount directo; usar fsutil como fallback
        $result = & fsutil hardlink list $FilePath 2>$null
        if ($result) {
            $lines = @($result | Where-Object { $_.Trim() -ne '' })
            return ($lines.Count -gt 1)
        }
        # Si fsutil falla, verificar atributo reparse point (symlink)
        $attrs = [System.IO.File]::GetAttributes($FilePath)
        if ($attrs -band [System.IO.FileAttributes]::ReparsePoint) { return $true }
        return $false
    }
    catch { return $false }
}

function Remove-EmiVortexSkyrimFull {
    <#  Elimina completamente Vortex y TODOS los archivos de Skyrim. #>

    Write-EmiLog '=== INICIANDO FORCE CLEAN SKYRIM ===' Step

    # Verificar que Vortex no esta corriendo
    $vortexProc = Get-Process -Name 'Vortex' -ErrorAction SilentlyContinue
    if ($vortexProc) {
        Write-EmiLog 'Cerrando Vortex...' Step
        Stop-Process -Name 'Vortex' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # Paso 1: Purgar todos los mods desplegados
    Write-EmiLog '=== Paso 1/6: Purgando mods desplegados ===' Step
    $info = Get-EmiVortexInfo
    if ($info.Installed) {
        foreach ($game in $info.Games) {
            $manifestPaths = _Get-EmiVortexManifestPaths -GameId $game.GameId
            foreach ($mp in $manifestPaths) {
                if (Test-Path -LiteralPath $mp) {
                    try {
                        $manifest = Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($manifest.files) {
                            $removed = 0
                            foreach ($f in $manifest.files) {
                                if ($f.relPath) {
                                    $targetPath = $f.relPath
                                    $gameDir = Split-Path $mp -Parent
                                    $fullTarget = Join-Path $gameDir $targetPath
                                    if (Test-Path -LiteralPath $fullTarget) {
                                        if (_Test-EmiVortexHardlink -FilePath $fullTarget) {
                                            try {
                                                Remove-Item -LiteralPath $fullTarget -Force -ErrorAction Stop
                                                $removed++
                                            } catch { }
                                        }
                                    }
                                }
                            }
                            if ($removed -gt 0) {
                                Write-EmiLog "$removed enlaces purgados de $($game.GameId)" Ok
                            }
                        }
                        # Borrar manifiesto
                        Add-EmiJournalEntry @{ Kind='File'; Path=$mp; Backup=$null; Module='Vortex' }
                        Remove-Item -LiteralPath $mp -Force -ErrorAction SilentlyContinue
                    } catch { Write-EmiLog "Error procesando manifiesto: $($_.Exception.Message)" Warn }
                }
            }
        }

        # Paso 2: Eliminar AppData completo
        Write-EmiLog '=== Paso 2/6: Eliminando datos de Vortex ===' Step
        Add-EmiJournalEntry @{ Kind='File'; Path=$info.AppDataPath; Backup=$null; Module='Vortex' }
        try {
            Remove-Item -LiteralPath $info.AppDataPath -Recurse -Force -ErrorAction Stop
            Write-EmiLog 'Datos de Vortex eliminados.' Ok
        } catch { Write-EmiLog "No se pudo eliminar AppData: $($_.Exception.Message)" Warn }

        # Paso 3: Ejecutar desinstalador silencioso
        Write-EmiLog '=== Paso 3/6: Desinstalando Vortex ===' Step
        if ($info.InstallPath) {
            $uninstaller = Join-Path $info.InstallPath 'Uninstall Vortex.exe'
            if (Test-Path -LiteralPath $uninstaller) {
                try {
                    $proc = Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
                    if ($proc -and $proc.ExitCode -eq 0) {
                        Write-EmiLog 'Vortex desinstalado correctamente.' Ok
                    } else {
                        Write-EmiLog "Desinstalador devolvio codigo $($proc.ExitCode)." Warn
                    }
                } catch { Write-EmiLog "Error ejecutando desinstalador: $($_.Exception.Message)" Warn }
            }
        }

        # Paso 4: Limpiar registro
        Write-EmiLog '=== Paso 4/6: Limpiando registro ===' Step
        $regKeys = @(
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Vortex'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Vortex'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Vortex'
            'HKCU:\SOFTWARE\Vortex'
        )
        foreach ($rk in $regKeys) {
            if (Test-Path -LiteralPath $rk) {
                Add-EmiJournalEntry @{ Kind='Registry'; Path=$rk; Name='(clave completa)'; Existed=$true; OldValue=$null; OldType='String'; NewValue=$null; Module='Vortex' }
                try {
                    Remove-Item -LiteralPath $rk -Recurse -Force -ErrorAction Stop
                    Write-Log "Clave eliminada: $rk" Ok
                } catch { Write-EmiLog "No se pudo eliminar $rk : $($_.Exception.Message)" Warn }
            }
        }
    }

    # Paso 5: Buscar y eliminar carpetas de Skyrim
    Write-EmiLog '=== Paso 5/6: Buscando carpetas de Skyrim ===' Step

    # Rutas comunes de Skyrim SE (Steam y GOG)
    $skyrimPaths = @(
        'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition',
        'C:\Program Files (x86)\GOG Galaxy\Games\Skyrim Special Edition',
        'D:\Steam\steamapps\common\Skyrim Special Edition',
        'D:\GOG Galaxy\Games\Skyrim Special Edition',
        'E:\Steam\steamapps\common\Skyrim Special Edition',
        'E:\GOG Galaxy\Games\Skyrim Special Edition'
    )

    # Rutas comunes de Skyrim LE (Steam y GOG)
    $skyrimLePaths = @(
        'C:\Program Files (x86)\Steam\steamapps\common\Skyrim',
        'C:\Program Files (x86)\GOG Galaxy\Games\Skyrim',
        'D:\Steam\steamapps\common\Skyrim',
        'D:\GOG Galaxy\Games\Skyrim',
        'E:\Steam\steamapps\common\Skyrim',
        'E:\GOG Galaxy\Games\Skyrim'
    )

    $skyrimDirs = New-Object System.Collections.ArrayList
    foreach ($path in $skyrimPaths) {
        if (Test-Path -LiteralPath $path) {
            [void]$skyrimDirs.Add($path)
            Write-EmiLog "Skyrim SE encontrado en: $path" Ok
        }
    }
    foreach ($path in $skyrimLePaths) {
        if (Test-Path -LiteralPath $path) {
            [void]$skyrimDirs.Add($path)
            Write-EmiLog "Skyrim LE encontrado en: $path" Ok
        }
    }

    # Buscar en discos adicionales
    $drives = @('C:', 'D:', 'E:', 'F:', 'G:', 'H:')
    foreach ($drive in $drives) {
        if (Test-Path -LiteralPath $drive) {
            # Buscar Skyrim SE
            $steamSe = Join-Path $drive 'Steam\steamapps\common\Skyrim Special Edition'
            if (Test-Path -LiteralPath $steamSe -and $steamSe -notin $skyrimDirs) {
                [void]$skyrimDirs.Add($steamSe)
                Write-EmiLog "Skyrim SE encontrado en: $steamSe" Ok
            }

            # Buscar Skyrim LE
            $steamLe = Join-Path $drive 'Steam\steamapps\common\Skyrim'
            if (Test-Path -LiteralPath $steamLe -and $steamLe -notin $skyrimDirs) {
                [void]$skyrimDirs.Add($steamLe)
                Write-EmiLog "Skyrim LE encontrado en: $steamLe" Ok
            }

            # Buscar en GOG Galaxy
            $gogSe = Join-Path $drive 'GOG Galaxy\Games\Skyrim Special Edition'
            if (Test-Path -LiteralPath $gogSe -and $gogSe -notin $skyrimDirs) {
                [void]$skyrimDirs.Add($gogSe)
                Write-EmiLog "Skyrim SE (GOG) encontrado en: $gogSe" Ok
            }

            $gogLe = Join-Path $drive 'GOG Galaxy\Games\Skyrim'
            if (Test-Path -LiteralPath $gogLe -and $gogLe -notin $skyrimDirs) {
                [void]$skyrimDirs.Add($gogLe)
                Write-EmiLog "Skyrim LE (GOG) encontrado en: $gogLe" Ok
            }
        }
    }

    if ($skyrimDirs.Count -eq 0) {
        Write-EmiLog 'No se encontraron instalaciones de Skyrim.' Warn
    } else {
        foreach ($dir in $skyrimDirs) {
            Write-EmiLog "Eliminando Skyrim en: $dir" Step

            # Eliminar carpetas de mods
            $modFolders = @(
                (Join-Path $dir 'Data'),
                (Join-Path $dir 'Mods'),
                (Join-Path $dir 'Optional'),
                (Join-Path $dir 'overwrite'),
                (Join-Path $dir 'Docs'),
                (Join-Path $dir 'Tools'),
                (Join-Path $dir 'ModOrganizer'),
                (Join-Path $dir 'Mod Organizer')
            )

            foreach ($folder in $modFolders) {
                if (Test-Path -LiteralPath $folder) {
                    Add-EmiJournalEntry @{ Kind='File'; Path=$folder; Backup=$null; Module='Vortex' }
                    try {
                        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop
                        Write-EmiLog "Carpeta eliminada: $folder" Ok
                    } catch {
                        Write-EmiLog "Error eliminando $folder : $($_.Exception.Message)" Warn
                    }
                }
            }

            # Eliminar archivos de configuracion de mods
            $configFiles = @(
                (Join-Path $dir 'SKSE'),
                (Join-Path $dir 'ENB'),
                (Join-Path $dir 'SkyrimPrefs.ini'),
                (Join-Path $dir 'skyrim.ini'),
                (Join-Path $dir 'vortex.deployment.json'),
                (Join-Path $dir 'vortex.deployment.bepinex-5.json'),
                (Join-Path $dir 'vortex.deployment.f4se.json'),
                (Join-Path $dir 'loadorder.txt'),
                (Join-Path $dir 'plugins.txt')
            )

            foreach ($file in $configFiles) {
                if (Test-Path -LiteralPath $file) {
                    Add-EmiJournalEntry @{ Kind='File'; Path=$file; Backup=$null; Module='Vortex' }
                    try {
                        Remove-Item -LiteralPath $file -Recurse -Force -ErrorAction Stop
                        Write-EmiLog "Archivo eliminado: $file" Ok
                    } catch {
                        Write-EmiLog "Error eliminando $file : $($_.Exception.Message)" Warn
                    }
                }
            }

            # Eliminar manifiestos de despliegue de Vortex
            Get-ChildItem -LiteralPath $dir -Filter 'vortex.deployment*.json' -ErrorAction SilentlyContinue | ForEach-Object {
                Add-EmiJournalEntry @{ Kind='File'; Path=$_.FullName; Backup=$null; Module='Vortex' }
                try {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    Write-EmiLog "Manifiesto eliminado: ($($_.FullName))" Ok
                } catch {
                    Write-EmiLog "Error eliminando manifiesto: ($($_.Exception.Message))" Warn
                }
            }
        }
    }

    # Paso 6: Limpiar documentos de usuario y AppData relacionados con Skyrim
    Write-EmiLog '=== Paso 6/6: Limpiando archivos de usuario ===' Step

    $userPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Skyrim'),
        (Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition'),
        (Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition VR'),
        (Join-Path $env:APPDATA 'Skyrim'),
        (Join-Path $env:APPDATA 'Skyrim Special Edition'),
        (Join-Path $env:APPDATA 'Skyrim Special Edition VR'),
        (Join-Path $env:DOCUMENTS 'My Games\Skyrim'),
        (Join-Path $env:DOCUMENTS 'My Games\Skyrim Special Edition'),
        (Join-Path $env:DOCUMENTS 'My Games\Skyrim Special Edition VR')
    )

    foreach ($path in $userPaths) {
        if (Test-Path -LiteralPath $path) {
            Add-EmiJournalEntry @{ Kind='File'; Path=$path; Backup=$null; Module='Vortex' }
            try {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                Write-EmiLog "Carpeta de usuario eliminada: $path" Ok
            } catch {
                Write-EmiLog "Error eliminando $path : $($_.Exception.Message)" Warn
            }
        }
    }

    # Buscar y eliminar carpetas residuales de Vortex en unidades
    Write-EmiLog 'Buscando residuos de Vortex...' Step
    $vortexResiduals = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Vortex'),
        (Join-Path $env:APPDATA 'Vortex'),
        (Join-Path $env:APPDATA '..\Local\Vortex')
    )

    foreach ($residual in $vortexResiduals) {
        if (Test-Path -LiteralPath $residual) {
            Add-EmiJournalEntry @{ Kind='File'; Path=$residual; Backup=$null; Module='Vortex' }
            try {
                Remove-Item -LiteralPath $residual -Recurse -Force -ErrorAction Stop
                Write-EmiLog "Residuo de Vortex eliminado: $residual" Ok
            } catch {
                Write-EmiLog "Error eliminando residuo: ($($_.Exception.Message))" Warn
            }
        }
    }

    Set-EmiStatus 'Force Clean Skyrim terminado' 100
    Write-EmiLog 'FORCE CLEAN SKYRIM COMPLETADO.' Ok
    return 1
}

Export-ModuleMember -Function *-Emi*