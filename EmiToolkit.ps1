<#
    Another's Toolbox - mantenimiento de equipos Windows 11
    Interfaz WPF con la transparencia nativa de Windows (estilo Frutiger Aero).

    Ejecutar:  EmiToolkit.cmd   (pide permisos de administrador)
#>

[CmdletBinding()]
param([switch] $NoElevate)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
# Cuanto tarda en abrirse: se anota una vez en el historial al pintar la ventana
$script:StartClock = [Diagnostics.Stopwatch]::StartNew()
$script:StartMarks = New-Object System.Collections.ArrayList

# --------------------------- Error Handler Global ---------------------
function Write-RuntimeError {
    param([string] $Message)
    try {
        # La carpeta de datos protegida de EmiCore (%ProgramData%\EmiToolkit); si
        # el error llega antes de cargarla, %LOCALAPPDATA%, nunca la carpeta de la app.
        $logDir = $null
        if (Get-Command Get-EmiDataDir -ErrorAction SilentlyContinue) { $logDir = Get-EmiDataDir }
        if (-not $logDir) { $logDir = Join-Path $env:LOCALAPPDATA 'EmiToolkit' }
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $logPath = Join-Path $logDir 'runtime-error.log'
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $entry = "[$timestamp] $Message`r`n"
        Add-Content -Path $logPath -Value $entry -Encoding UTF8
    } catch { }
}

# --------------------------- Elevacion --------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $NoElevate) {
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden',
            '-File', "`"$($MyInvocation.MyCommand.Path)`""
        )
        exit
    }
    catch {
        [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
        [System.Windows.Forms.MessageBox]::Show(
            'Another''s Toolbox necesita permisos de administrador. Se abrira en modo limitado.',
            'Another''s Toolbox', 'OK', 'Warning') | Out-Null
    }
}

# --------------------- Confianza en la carpeta -------------------------
# Este proceso corre como administrador y carga codigo (modulos .psm1 y el
# XAML) de su propia carpeta. Si un usuario sin privilegios puede escribir en
# ella (C:\EmiToolkit copiado con robocopy, Descargas, Escritorio, OneDrive,
# una carpeta compartida), puede meter codigo que se ejecutara como
# administrador la proxima vez que alguien abra la herramienta.
function Get-EmiFolderTrustIssues {
    param([string] $Base)
    $issues = New-Object System.Collections.ArrayList
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return @() }
    $targets = @($Base, (Join-Path $Base 'Modules'), (Join-Path $Base 'UI'))
    $targets += @(Get-ChildItem -LiteralPath $Base -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.ps1', '.cmd' } | ForEach-Object FullName)
    $targets += @(Get-ChildItem -LiteralPath (Join-Path $Base 'Modules') -Filter '*.psm1' -File -Force -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $targets += @(Get-ChildItem -LiteralPath (Join-Path $Base 'UI') -Filter '*.xaml' -File -Force -ErrorAction SilentlyContinue | ForEach-Object FullName)
    foreach ($t in $targets) {
        try {
            $who = @(Get-EmiPathWriters $t)
            if ($who.Count -gt 0) { [void]$issues.Add(('{0}: {1}' -f $t, ($who -join ', '))) }
        } catch { [void]$issues.Add("$t : no se pudo leer la ACL ($($_.Exception.Message))") }
    }
    return $issues.ToArray()
}

function Get-EmiPathWriters {
    <#  Quien, aparte de SYSTEM, Administradores, CREATOR OWNER y TrustedInstaller,
        puede modificar $Path (o es su propietario). Lanza si no se lee la ACL. #>
    param([string] $Path)
    $trusted = @('S-1-5-18', 'S-1-5-32-544', 'S-1-3-0', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    $mask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $who = New-Object System.Collections.ArrayList
    $own = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($trusted -notcontains $own) { [void]$who.Add("propietario $own") }
    foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        if (($r.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0) { continue }
        if ($trusted -contains $r.IdentityReference.Value) { continue }
        if (([int64]$r.FileSystemRights -band $mask) -ne 0) {
            $n = $r.IdentityReference.Value
            try { $n = $r.IdentityReference.Translate([Security.Principal.NTAccount]).Value } catch { }
            if (-not $who.Contains($n)) { [void]$who.Add($n) }
        }
    }
    return $who.ToArray()
}

function Install-EmiProtectedCopy {
    <#  Copia la herramienta a %ProgramFiles%\EmiToolkit (hereda la ACL de
        Program Files: solo administradores escriben) y devuelve el .ps1 nuevo. #>
    param([string] $From)
    $dest = Join-Path $env:ProgramFiles 'EmiToolkit'
    if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    $bad = @(Get-EmiFolderTrustIssues $dest | Where-Object { $_ -like "${dest}:*" })
    if ($bad.Count -gt 0) { throw "La carpeta $dest ya existe y no esta protegida: $($bad -join '; ')" }
    foreach ($sub in @('Modules', 'UI')) {
        $d = Join-Path $dest $sub
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    Get-ChildItem -LiteralPath $From -File | Where-Object { $_.Extension -in '.ps1', '.cmd', '.md', '.txt' } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop }
    Get-ChildItem -LiteralPath (Join-Path $From 'Modules') -Filter '*.psm1' -File |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest 'Modules') -Force -ErrorAction Stop }
    Get-ChildItem -LiteralPath (Join-Path $From 'UI') -Filter '*.xaml' -File |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest 'UI') -Force -ErrorAction Stop }
    # Propietario Administradores en todo (segun la directiva, los archivos
    # creados por un administrador pueden quedar a nombre de su cuenta)
    $admins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    foreach ($i in @(Get-Item -LiteralPath $dest) + @(Get-ChildItem -LiteralPath $dest -Recurse -Force)) {
        try { $a = Get-Acl -LiteralPath $i.FullName; $a.SetOwner($admins); Set-Acl -LiteralPath $i.FullName -AclObject $a } catch { }
    }
    $left = @(Get-EmiFolderTrustIssues $dest)
    if ($left.Count -gt 0) { throw "La copia en $dest sigue siendo modificable por otros usuarios: $($left -join '; ')" }
    return (Join-Path $dest 'EmiToolkit.ps1')
}

$script:TrustNote = $null
if ($isAdmin) {
    $trustIssues = @(Get-EmiFolderTrustIssues $Root)
    if ($trustIssues.Count -gt 0) {
        [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
        $shown = ($trustIssues | Select-Object -First 6) -join "`n"
        if ($trustIssues.Count -gt 6) { $shown += "`n... y $($trustIssues.Count - 6) mas" }
        $msg = 'AVISO DE SEGURIDAD' + "`n`n" +
               'Another''s Toolbox se ejecuta como administrador, pero su carpeta la pueden modificar usuarios sin privilegios:' + "`n`n" +
               $shown + "`n`n" +
               'Cualquiera de esos usuarios (o un programa malicioso que corra con su cuenta) podria cambiar el codigo y conseguir permisos de administrador la proxima vez que se abra la herramienta.' + "`n`n" +
               'Si = copiarla a ' + (Join-Path $env:ProgramFiles 'EmiToolkit') + ' (solo administradores pueden escribir ahi) y abrirla desde alli. Recomendado.' + "`n" +
               'No = continuar de todas formas desde esta carpeta (queda anotado en el registro).' + "`n" +
               'Cancelar = salir.' + "`n`n" +
               'Si sospechas que alguien ya ha tocado estos archivos, descarga de nuevo la herramienta antes de copiarla.'
        $ans = [System.Windows.Forms.MessageBox]::Show($msg, 'Another''s Toolbox - carpeta no protegida', 'YesNoCancel', 'Warning', 'Button1')
        if ($ans -eq 'Yes') {
            try {
                $newPs1 = Install-EmiProtectedCopy $Root
                Start-Process -FilePath 'powershell.exe' -WorkingDirectory (Split-Path $newPs1) -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$newPs1`""
                )
                exit
            } catch {
                [System.Windows.Forms.MessageBox]::Show('No se pudo copiar a Program Files: ' + $_.Exception.Message + "`n`nLa herramienta se cerrara.",
                    'Another''s Toolbox', 'OK', 'Error') | Out-Null
                exit 1
            }
        } elseif ($ans -eq 'No') {
            $script:TrustNote = 'Se continuo desde una carpeta modificable por usuarios sin privilegios: ' + ($trustIssues -join ' | ')
        } else {
            exit
        }
    }
}

try {
# --------------------------- Ensamblados ------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms

# ---------------------------- Modulos ---------------------------------
$ModuleDir   = Join-Path $Root 'Modules'
$ModuleNames = @('EmiCore', 'EmiDisk', 'EmiTweaks', 'EmiPrivacy', 'EmiPrivRecs', 'EmiVault', 'EmiDebloat', 'EmiApps', 'EmiFirewall', 'EmiStartup', 'EmiProcess', 'EmiVortex', 'EmiSystem')
# Cada modulo se lee de disco UNA vez, aqui, justo despues de comprobar la
# carpeta. Las tareas en segundo plano importan este mismo texto en memoria
# (Preamble) en vez de volver a leer los .psm1: asi nadie puede cambiar el
# codigo a mitad de sesion.
$script:ModuleCode = @{}
foreach ($m in $ModuleNames) {
    $script:ModuleCode[$m] = [System.IO.File]::ReadAllText((Join-Path $ModuleDir "$m.psm1"))
}
[void]$script:StartMarks.Add('lectura ' + $script:StartClock.ElapsedMilliseconds + ' ms')

# Tipos C# precompilados. Compilar con Add-Type lanza csc.exe y cuesta cerca
# de un segundo cada vez; ahora hay un solo bloque por modulo y se guarda
# compilado en %ProgramData%\EmiToolkit\cache (ACL solo de administradores),
# con el hash del codigo fuente en el nombre. Solo se carga una DLL de ahi si
# la carpeta y el archivo siguen siendo solo de administradores y el hash
# coincide con el fuente que se acaba de leer; si no, se compila en memoria
# como antes y la cache se rehace en segundo plano.
$script:TypeSpecs = @(
    @{ Module = 'EmiCore';  Var = 'EmiTypeSource';     Probe = @('EmiItem', 'EmiNative'); Refs = @() }
    @{ Module = 'EmiVault'; Var = 'HelloBridgeSource'; Probe = @('EmiHelloBridge');       Refs = @('System.Runtime.WindowsRuntime', 'System.Core', 'WindowsBase') }
)

function Get-EmiScriptStringVar {
    <#  Texto de una asignacion de primer nivel  $script:Nombre = @'...'@  de un modulo, leido con el AST (sin ejecutar nada). #>
    param([string] $Code, [string] $Name)
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tok, [ref]$err)
    foreach ($st in $ast.EndBlock.Statements) {
        if ($st -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { continue }
        if ($st.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
        if ($st.Left.VariablePath.UserPath -ne ('script:' + $Name)) { continue }
        $ex = $st.Right.Expression
        if ($ex -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $ex.Value }
    }
    return $null
}

function Get-EmiTypeCacheName {
    <#  Nombre del archivo en la cache: modulo + SHA-256 del fuente, las
        referencias y la version de .NET y PowerShell (otro fuente, otro archivo). #>
    param([string] $Module, [string] $Source, [string[]] $Refs)
    $key = $Source + '|' + ($Refs -join ',') + '|' + [Environment]::Version + '|' + $PSVersionTable.PSVersion
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key)) } finally { $sha.Dispose() }
    return ('{0}-{1}.dll' -f $Module, (-join ($h[0..11] | ForEach-Object { $_.ToString('x2') })))
}

function Test-EmiCacheTrusted {
    <#  $true si cada ruta existe, no es un enlace y solo la pueden modificar administradores. #>
    param([string[]] $Paths)
    foreach ($p in $Paths) {
        $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $it) { return $false }
        if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        try { if (@(Get-EmiPathWriters $p).Count -gt 0) { return $false } } catch { return $false }
    }
    return $true
}

$script:TypeCacheDir = $null
$script:TypeCacheMissing = New-Object System.Collections.ArrayList
$script:TypeCacheNote = 'sin cache'
if ($isAdmin -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $env:ProgramData) {
    $script:TypeCacheDir = Join-Path (Join-Path $env:ProgramData 'EmiToolkit') 'cache'
    $hits = 0
    foreach ($spec in $script:TypeSpecs) {
        $src = Get-EmiScriptStringVar $script:ModuleCode[$spec.Module] $spec.Var
        if (-not $src) { continue }
        $file = Join-Path $script:TypeCacheDir (Get-EmiTypeCacheName $spec.Module $src $spec.Refs)
        $loaded = $false
        if (Test-EmiCacheTrusted @((Split-Path $script:TypeCacheDir), $script:TypeCacheDir, $file)) {
            try {
                Add-Type -LiteralPath $file -ErrorAction Stop
                $loaded = (@($spec.Probe | Where-Object { -not ($_ -as [type]) }).Count -eq 0)
            } catch { $loaded = $false }
        }
        if ($loaded) { $hits++ }
        else { [void]$script:TypeCacheMissing.Add(@{ Module = $spec.Module; Source = $src; Refs = $spec.Refs; File = $file }) }
    }
    $script:TypeCacheNote = 'cache de tipos: ' + $hits + ' de ' + $script:TypeSpecs.Count
}

function Start-EmiTypeCacheBuild {
    <#  Compila en otro proceso (sin esperar) las DLL que faltan en la cache. En
        otro proceso porque Add-Type -OutputAssembly en este cargaria una
        segunda copia de los mismos tipos. El hijo hereda el token de
        administrador y escribe primero a un temporal en la misma carpeta. #>
    if (-not $script:TypeCacheDir -or $script:TypeCacheMissing.Count -eq 0) { return }
    if ((Get-EmiDataDir) -ne (Split-Path $script:TypeCacheDir)) { return }   # la carpeta de datos no es la protegida
    try {
        if (-not (Test-Path -LiteralPath $script:TypeCacheDir)) { New-Item -ItemType Directory -Path $script:TypeCacheDir -Force | Out-Null }
        if (-not (Test-EmiCacheTrusted @((Split-Path $script:TypeCacheDir), $script:TypeCacheDir))) {
            Write-EmiLog 'La cache de tipos no esta protegida: no se usa.' Warn; return
        }
        $q = { param($t) "'" + ([string]$t).Replace("'", "''") + "'" }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('$ErrorActionPreference = ''Stop''')
        foreach ($j in $script:TypeCacheMissing) {
            $b64  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($j.Source))
            $refs = '@(' + ((@($j.Refs) | ForEach-Object { & $q $_ }) -join ',') + ')'
            $tmp  = $j.File -replace '\.dll$', ('.' + $PID + '.tmp.dll')
            [void]$sb.AppendLine('try {')
            [void]$sb.AppendLine('  $src = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(' + (& $q $b64) + '))')
            [void]$sb.AppendLine('  $a = @{ TypeDefinition = $src; OutputAssembly = ' + (& $q $tmp) + '; Language = ''CSharp'' }; $r = ' + $refs + '; if ($r.Count) { $a.ReferencedAssemblies = $r }')
            [void]$sb.AppendLine('  Add-Type @a; Move-Item -LiteralPath ' + (& $q $tmp) + ' -Destination ' + (& $q $j.File) + ' -Force')
            [void]$sb.AppendLine('  Get-ChildItem -LiteralPath ' + (& $q $script:TypeCacheDir) + ' -Filter ' + (& $q ($j.Module + '-*.dll')) + ' | Where-Object { $_.FullName -ne ' + (& $q $j.File) + ' } | Remove-Item -Force -ErrorAction SilentlyContinue')
            [void]$sb.AppendLine('} catch { }')
        }
        $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($sb.ToString()))
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc) | Out-Null
    } catch { Write-EmiLog ('No se pudo preparar la cache de tipos: ' + $_.Exception.Message) Info }
}

foreach ($m in $ModuleNames) {
    New-Module -Name $m -ScriptBlock ([scriptblock]::Create($script:ModuleCode[$m])) | Import-Module -Force -DisableNameChecking
}
[void]$script:StartMarks.Add('modulos ' + $script:StartClock.ElapsedMilliseconds + ' ms (' + $script:TypeCacheNote + ')')

Initialize-EmiCore -RootPath $Root
if ($script:TrustNote) { Write-EmiLog $script:TrustNote Warn }
Initialize-EmiVault
Write-EmiLog ('Another''s Toolbox iniciado en ' + $env:COMPUTERNAME + ' por ' + $env:USERNAME + '.') Ok
if (-not $isAdmin) { Write-EmiLog 'Sin permisos de administrador: muchas acciones estaran limitadas.' Warn }

# ------------------------------ XAML ----------------------------------
$xamlPath = Join-Path $Root 'UI\MainWindow.xaml'
$xamlText = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$win = [Windows.Markup.XamlReader]::Parse($xamlText)
[void]$script:StartMarks.Add('XAML ' + $script:StartClock.ElapsedMilliseconds + ' ms')

function C { param([string] $Name) $win.FindName($Name) }

# Atajos a los controles
$ui = @{}
foreach ($n in @(
    'TbHeaderHint','BtnClose','BtnMax','BtnMin','SwAdvanced','TbModeHint','TbAdminBadge','TbAdvHeader',
    'NavHome','NavAnyDesk','NavDisk','NavTweaks','NavPrivacy','NavPrivRecs','NavDebloat','NavApps','NavEset','NavStartup','NavProcess','NavVortex','NavSystem','NavLog','NavStore',
    'PageHome','PageAnyDesk','PageDisk','PageTweaks','PagePrivacy','PagePrivRecs','PageDebloat','PageApps','PageEset','PageStartup','PageProcess','PageVortex','PageSystem','PageLog','PageStore',
    'TbHello','TbOneClickInfo','ChkRestore','ChkEsetInclude','ChkZenInclude','BtnOneClick','IcDisks',
    'TbStatPrivacy','TbStatFast','TbStatEset','TbStatZen','TbStatRam','TbStatPc',
    'TbAnyState','TbAnyId','BtnAnyDownload','BtnAnyFolder','BtnAnyOpen','IcAnySteps',
    'BtnDiskScan','BtnDiskClean','BtnDiskDism','TbDiskTotal','LvClean','TxtScanPath','TxtScanMin',
    'BtnScanFiles','BtnScanFolders','LvBig','BtnOpenFile','BtnDeleteBig',
    'BtnTweakApply','BtnTweakRecommended','BtnRestartExplorer','LvTweaks',
    'BtnPrivApply','BtnPrivRecommended','LvPrivacy',
    'BtnHibpOpen','TbPrivRecZenState','BtnPrivRecZenSet','BtnPrivRecZenDownload',
    'CardUblock','TbPrivRecUblockState','BtnPrivRecUblockInstall','BtnLastPassOpen',
    'BtnVaultUnlock','BtnVaultLock','TbVaultLockedMsg','SpVaultContent',
    'TxtGenPassword','BtnGenPassword','BtnGenCopy','ChkGenSpecial','TbGenLength',
    'TxtVaultAppName','TxtVaultEmail','TxtVaultPassword','BtnVaultGenForEntry','BtnVaultAdd',
    'LvVault','TbVaultCount','BtnVaultCopyPw','BtnVaultCopyEmail','BtnVaultDelete',
    'BtnDebloatApply','BtnDebloatRecommended','LvDebloat',
    'BtnAppsScan','BtnAppsUninstall','BtnAppsClearCache','LvApps',
    'BtnStoreOpenWeb','BtnStoreUninstall','BtnStoreSelectAll',
    'ChkStoreAudio','ChkStoreDraw','ChkStoreFinance','ChkStoreHub','ChkStoreMedia',
    'ChkStorePhoto','ChkStorePixel','ChkStorePresent','ChkStoreReader','ChkStoreVault','ChkStoreWriter',
    'BtnEsetApply','BtnEsetTest','BtnEsetRemove','ChkEsetDns','LvEset',
    'BtnStartupScan','BtnStartupDisable','BtnStartupEnable','LvStartup',
    'BtnProcScan','BtnProcKill','BtnProcBlock','TbRam','LvProcess',
    'BtnVortexScan','BtnVortexRemove','BtnVortexFullClean','BtnVortexSkyrimClean','LvVortex',
    'TbZenState','BtnZenSet','BtnZenSettings','TbFastState','ChkHiber','BtnFastDisable','BtnFastEnable','TbSysInfo',
    'BtnUndoAll','BtnOpenLog','TbUndoCount','IcLog','SvLog',
    'TbStatus','PbMain','EllBusy','SwContrast','BgSky','BgGloss','BgBubbles'
)) { $ui[$n] = C $n }

# Pincel original del fondo, para restaurarlo al desactivar contraste alto
$script:SkyBrush = $ui.BgSky.Fill

# ------------------------- Estado de la interfaz ----------------------
$script:LogView   = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$script:LogIndex  = 0
$script:Advanced  = $false
$script:Worker    = $null
$script:WorkHandle = $null
$script:OnDone    = $null
$ui.IcLog.ItemsSource = $script:LogView

$busyGreen = [Windows.Media.BrushConverter]::new().ConvertFrom('#FF4CA22B')
$busyAmber = [Windows.Media.BrushConverter]::new().ConvertFrom('#FFE08C1E')

# ======================================================================
#                      MOTOR DE TAREAS EN SEGUNDO PLANO
# ======================================================================

# Las rutas llegan al runspace como variables (SessionStateProxy.SetVariable en
# Start-EmiWork), no pegadas en el texto: una ruta con apostrofo, como
# C:\Users\O'Brien, romperia el script.
$script:Preamble = @'
$ErrorActionPreference = 'Continue'
foreach ($m in $EmiModuleNames) {
    New-Module -Name $m -ScriptBlock ([scriptblock]::Create($EmiModuleCode[$m])) | Import-Module -Force -DisableNameChecking -Global
}
Initialize-EmiCore -RootPath $EmiRootPath -DataPath $EmiDataPath
'@

function New-EmiWorkerRunspace {
    <#  Runspace en segundo plano con lo que necesita el preambulo. Los modulos
        se importan (del texto ya leido) la primera vez que se usa y se quedan. #>
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('EmiSync', $global:EmiSync)
    $rs.SessionStateProxy.SetVariable('EmiRootPath', $Root)
    $rs.SessionStateProxy.SetVariable('EmiModuleCode', $script:ModuleCode)
    $rs.SessionStateProxy.SetVariable('EmiDataPath', (Get-EmiDataDir))
    $rs.SessionStateProxy.SetVariable('EmiModuleNames', [string[]]$ModuleNames)
    return $rs
}

# Una sola vez por runspace: los modulos ya importados no se vuelven a importar
$script:PreambleOnce = 'if (-not $global:EmiReady) {' + "`n" + $script:Preamble + "`n" + '$global:EmiReady = $true' + "`n" + '}'

# ---------------- Estado del equipo (Inicio, Sistema, Recomendaciones) ----------------
# Las consultas CIM, del firewall y de Zen tardan; antes corrian en el hilo de
# la ventana al arrancar y tras cada tarea. Ahora van en su propio runspace
# (solo leen: no compiten con la tarea en curso) y la ventana se rellena al
# llegar el resultado. Los datos fijos del equipo se consultan una vez.
$script:StatusQuery = @'
if (-not $global:EmiStatic) { $global:EmiStatic = Get-EmiSystemSummary; $global:EmiStaticAt = Get-Date }
$s = $global:EmiStatic
$up = $s.Uptime
if ($up -match '^(\d+)d (\d+)h (\d+)m$') {
    $t = (New-TimeSpan -Days $Matches[1] -Hours $Matches[2] -Minutes $Matches[3]) + ((Get-Date) - $global:EmiStaticAt)
    $up = '{0}d {1}h {2}m' -f $t.Days, $t.Hours, $t.Minutes
}
$r = @{
    Disks    = @(Get-EmiDisks)
    Privacy  = Get-EmiPrivacyStatus
    Fast     = Get-EmiFastStartup
    Eset     = [int](Get-EmiEsetRuleCount)
    Zen      = Get-EmiZenInfo
    ZenRecs  = Get-EmiZenBrowserStatus
    Mem      = Get-EmiMemoryStatus
    Summary  = $s
    Uptime   = $up
    Undo     = @(Get-EmiJournal).Count
    Admin    = [bool](Test-EmiAdmin)
}
if ($EmiWithAnyDesk) { $r.AnyDesk = Get-EmiAnyDeskInfo; $r.AnySteps = @(Get-EmiAnyDeskSteps) }
return $r
'@
$script:StatusRs = $null; $script:StatusPs = $null; $script:StatusHandle = $null
$script:StatusPending = $false; $script:StatusWantAnyDesk = $false

function Set-EmiBusy {
    param([bool] $Busy, [string] $Text = 'Listo')
    $ui.TbStatus.Text  = $Text
    $ui.EllBusy.Fill   = if ($Busy) { $busyAmber } else { $busyGreen }
    # Mientras corre una tarea se desactiva cada pagina entera, y con ella todos
    # sus botones (una lista a mano siempre se dejaba alguno). El registro sigue
    # abierto para ver el progreso; de el solo se bloquea «Revertir todo». No se
    # toca el IsEnabled de cada boton, asi que al terminar cada uno recupera su
    # propio estado (BtnZenSet sigue apagado si Zen no esta instalado).
    if ($pages) {
        foreach ($k in $pages.Keys) {
            if ($k -ne 'Log' -and $pages[$k]) { $pages[$k].IsEnabled = -not $Busy }
        }
    }
    if ($ui.BtnUndoAll) { $ui.BtnUndoAll.IsEnabled = -not $Busy }
    if (-not $Busy) { $ui.PbMain.Value = 0 }
}

function Start-EmiWork {
    <#  Ejecuta un bloque en un runspace aparte para no congelar la interfaz. #>
    param(
        [Parameter(Mandatory)][scriptblock] $Work,
        [hashtable] $Parameters = @{},
        [scriptblock] $OnDone,
        [string] $Label = 'Trabajando...'
    )

    if ($script:Worker) { Write-EmiLog 'Ya hay una tarea en curso.' Warn; return }

    Set-EmiBusy $true $Label
    # Desde aqui se cuentan los avisos y errores de esta tarea (Get-EmiTaskIssues)
    $script:WorkLogStart = $global:EmiSync.Log.Count
    $global:EmiSync.Progress = 0
    $global:EmiSync.Status   = $Label
    $global:EmiSync.Result   = $null

    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions  = 'ReuseThread'
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('EmiSync', $global:EmiSync)
        $rs.SessionStateProxy.SetVariable('P', $Parameters)
        $rs.SessionStateProxy.SetVariable('EmiRootPath', $Root)
        $rs.SessionStateProxy.SetVariable('EmiModuleCode', $script:ModuleCode)
        $rs.SessionStateProxy.SetVariable('EmiDataPath', (Get-EmiDataDir))
        $rs.SessionStateProxy.SetVariable('EmiModuleNames', [string[]]$ModuleNames)

        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($script:Preamble + "`n" + $Work.ToString())

        $script:Worker     = $ps
        $script:WorkHandle = $ps.BeginInvoke()
        $script:OnDone     = $OnDone
    } catch {
        # Si el arranque del runspace falla, restaurar la UI o quedaria "ocupada" para siempre
        Write-EmiLog ('No se pudo iniciar la tarea: ' + $_.Exception.Message) Error
        $script:Worker = $null; $script:WorkHandle = $null; $script:OnDone = $null
        try { if ($rs) { $rs.Dispose() } } catch { }
        try { if ($ps) { $ps.Dispose() } } catch { }
        Set-EmiBusy $false 'Listo'
    }
}

# Avisos y errores de la ultima tarea: el mensaje final los cuenta en vez de
# decir siempre que todo fue bien (en modo basico el registro no se ve).
$script:WorkLogStart = 0
$script:LastWarn = 0
$script:LastErr  = 0
function Update-EmiTaskIssues {
    $script:LastWarn = 0; $script:LastErr = 0
    $log = $global:EmiSync.Log
    for ($k = $script:WorkLogStart; $k -lt $log.Count; $k++) {
        $lv = $log[$k].Level
        if ($lv -eq 'Warn') { $script:LastWarn++ } elseif ($lv -eq 'Error') { $script:LastErr++ }
    }
}

function Get-EmiTaskIssues {
    <#  '' si la ultima tarea no dejo avisos ni errores; si no, 'con 2 avisos y 1 error'. #>
    $parts = @()
    if ($script:LastErr -gt 0)  { $parts += ([string]$script:LastErr + $(if ($script:LastErr -eq 1) { ' error' } else { ' errores' })) }
    if ($script:LastWarn -gt 0) { $parts += ([string]$script:LastWarn + $(if ($script:LastWarn -eq 1) { ' aviso' } else { ' avisos' })) }
    if ($parts.Count -eq 0) { return '' }
    return 'con ' + ($parts -join ' y ')
}

$script:LogHint = 'mira el registro (Modo avanzado > Registro y deshacer, o la carpeta Data)'

function Get-EmiTaskIssueNote {
    <#  Nota para anadir a un mensaje propio: vacia si no hubo avisos ni errores. #>
    $i = Get-EmiTaskIssues
    if (-not $i) { return '' }
    return "`n`n" + 'La tarea termino ' + $i + ': ' + $script:LogHint + '.'
}

function Show-EmiTaskDone {
    <#  Mensaje final de una tarea con el recuento de avisos y errores.
        -OnlyIfIssues: no molesta si todo fue bien. -Warn: fuerza el icono de aviso. #>
    param([string] $What, [string] $Extra = '', [switch] $OnlyIfIssues, [switch] $Warn)
    $i = Get-EmiTaskIssues
    if (-not $i -and $OnlyIfIssues) { return }
    $msg  = if ($i) { $What + ' ' + $i + ': ' + $script:LogHint + '.' } else { $What + '.' }
    if ($Extra) { $msg += "`n`n" + $Extra }
    $icon = if ($i -or $Warn) { 'Warning' } else { 'Information' }
    [System.Windows.MessageBox]::Show($msg, 'Another''s Toolbox', 'OK', $icon) | Out-Null
}

# Temporizador que refresca la interfaz y recoge el resultado
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(180)
$timer.Add_Tick({
    # Volcar el log
    try {
        $total = $global:EmiSync.Log.Count
        if ($script:LogIndex -lt $total) {
            # Bajar al final solo si llegaron lineas nuevas y el usuario ya estaba
            # abajo: si ha subido para leer, no se le arrastra cada 180 ms.
            $atEnd = ($ui.SvLog.ScrollableHeight - $ui.SvLog.VerticalOffset) -lt 4
            while ($script:LogIndex -lt $total) {
                $script:LogView.Add($global:EmiSync.Log[$script:LogIndex])
                $script:LogIndex++
                if ($script:LogView.Count -gt 600) { $script:LogView.RemoveAt(0) }
            }
            if ($atEnd) { $ui.SvLog.ScrollToEnd() }
        }
    } catch { }

    try { Receive-EmiStatus } catch { }

    # Estado y progreso
    if ($script:Worker) {
        $ui.TbStatus.Text = [string]$global:EmiSync.Status
        $ui.PbMain.Value  = [double]$global:EmiSync.Progress

        if ($script:WorkHandle.IsCompleted) {
            try {
                $result = $null
                try { $result = $script:Worker.EndInvoke($script:WorkHandle) } catch { Write-EmiLog ('Error en la tarea: ' + $_.Exception.Message) Error }
                $errs = $script:Worker.Streams.Error
                if ($errs -and $errs.Count -gt 0) { foreach ($e in $errs) { Write-EmiLog ([string]$e) Warn } }
            } finally {
                try { Update-EmiTaskIssues } catch { }
                try { $script:Worker.Runspace.Close(); $script:Worker.Dispose() } catch { }
                $script:Worker = $null; $script:WorkHandle = $null
                Set-EmiBusy $false 'Listo'
            }
            if ($script:OnDone) {
                $cb = $script:OnDone; $script:OnDone = $null
                try { & $cb $result } catch { Write-EmiLog ('Error al refrescar: ' + $_.Exception.Message) Warn }
            }
            if ($null -ne $script:DebloatRetry -and -not $script:Worker) {
                $sel = $script:DebloatRetry; $script:DebloatRetry = $null
                Start-EmiDebloatLoad -SelectRecommended:$sel
            }
        }
    }
})
$timer.Start()

# ======================================================================
#                              NAVEGACION
# ======================================================================

$pages = @{
    Home    = $ui.PageHome;    AnyDesk = $ui.PageAnyDesk; Disk    = $ui.PageDisk
    Tweaks  = $ui.PageTweaks;  Privacy = $ui.PagePrivacy; PrivRecs = $ui.PagePrivRecs; Debloat = $ui.PageDebloat; Apps = $ui.PageApps; Eset    = $ui.PageEset
    Startup = $ui.PageStartup; Process = $ui.PageProcess; Vortex  = $ui.PageVortex
    System  = $ui.PageSystem;  Log     = $ui.PageLog;   Store   = $ui.PageStore
}

function Show-EmiPage {
    param([string] $Name)
    foreach ($k in $pages.Keys) {
        # Una pagina que falte en el XAML o en $ui no debe tumbar la navegacion
        if (-not $pages[$k]) { continue }
        $pages[$k].Visibility = if ($k -eq $Name) { 'Visible' } else { 'Collapsed' }
    }
}

foreach ($nav in @('NavHome','NavAnyDesk','NavDisk','NavTweaks','NavPrivacy','NavPrivRecs','NavDebloat','NavApps','NavEset','NavStartup','NavProcess','NavVortex','NavSystem','NavLog','NavStore')) {
    $ui[$nav].Add_Checked({ Show-EmiPage $this.Tag }.GetNewClosure())
}

$advNav = @('NavDisk','NavTweaks','NavPrivacy','NavPrivRecs','NavDebloat','NavApps','NavEset','NavStartup','NavProcess','NavVortex','NavSystem','NavLog','NavStore')

$ui.SwAdvanced.Add_Click({
    $script:Advanced = [bool]$ui.SwAdvanced.IsChecked
    $vis = if ($script:Advanced) { 'Visible' } else { 'Collapsed' }
    foreach ($n in $advNav) { $ui[$n].Visibility = $vis }
    $ui.TbAdvHeader.Visibility = $vis

    if ($script:Advanced) {
        $ui.TbModeHint.Text = 'Modo avanzado: cada apartado por separado.'
        Initialize-EmiAdvancedPages
    } else {
        $ui.TbModeHint.Text = 'Modo basico: un clic y listo.'
        $ui.NavHome.IsChecked = $true
        Show-EmiPage 'Home'
    }
})

$ui.SwContrast.Add_Click({
    $on = [bool]$ui.SwContrast.IsChecked
    $vis = if ($on) { 'Collapsed' } else { 'Visible' }
    # Ocultar capas decorativas translucidas y forzar fondo solido claro
    $win.Background = if ($on) { [Windows.Media.Brushes]::White } else { [Windows.Media.Brushes]::Transparent }
    $ui.BgGloss.Visibility   = $vis
    $ui.BgBubbles.Visibility  = $vis
    if ($on) { $ui.BgSky.Fill = [Windows.Media.Brushes]::White } else { $ui.BgSky.Fill = $script:SkyBrush }
})

$script:AdvLoaded = $false
function Initialize-EmiAdvancedPages {
    if ($script:AdvLoaded) { return }
    $script:AdvLoaded = $true

    # Optimizaciones
    try {
        $tw = New-Object System.Collections.ArrayList
        foreach ($t in Get-EmiTweaks) {
            $i = New-Object EmiItem
            $i.Name = $t.Name; $i.Detail = $t.Info; $i.Tag = $t.Id
            $i.Recommended = $t.Recommended; $i.Selected = $t.Recommended
            $i.SizeText = if ($t.Recommended) { 'recomendado' } else { 'opcional' }
            [void]$tw.Add($i)
        }
        $ui.LvTweaks.ItemsSource = $tw
    } catch { Write-EmiLog "Error cargando Tweaks: $($_.Exception.Message)" Warn }

    # Privacidad
    try {
        $pv = New-Object System.Collections.ArrayList
        foreach ($t in Get-EmiPrivacyItems) {
            $i = New-Object EmiItem
            $i.Name = $t.Name; $i.Detail = $t.Info; $i.Tag = $t.Id
            $i.Recommended = $t.Recommended; $i.Selected = $t.Recommended
            $i.SizeText = if ($t.Recommended) { 'recomendado' } else { 'opcional' }
            [void]$pv.Add($i)
        }
        $ui.LvPrivacy.ItemsSource = $pv
    } catch { Write-EmiLog "Error cargando Privacidad: $($_.Exception.Message)" Warn }

    # ESET
    try { $ui.LvEset.ItemsSource = Get-EmiEsetItems } catch { Write-EmiLog "Error cargando ESET: $($_.Exception.Message)" Warn }

    # Rutas por defecto del buscador
    $ui.TxtScanPath.Text = $env:USERPROFILE

    Update-EmiHome
    Update-EmiVaultUI

    # Apps preinstaladas: 25 Get-AppxPackage y 4 consultas de caracteristicas
    # de Windows; en segundo plano para que la ventana no se quede congelada.
    Start-EmiDebloatLoad -SelectRecommended
}

$script:DebloatRetry = $null
function Start-EmiDebloatLoad {
    param([switch] $SelectRecommended)
    # Con otra tarea en marcha se carga al terminar esa (lo mira el temporizador)
    if ($script:Worker) { $script:DebloatRetry = [bool]$SelectRecommended; return }
    Start-EmiWork -Label 'Cargando la lista de apps preinstaladas...' -Parameters @{ Sel = [bool]$SelectRecommended } -Work {
        $db = New-Object System.Collections.ArrayList
        foreach ($t in Get-EmiDebloatItems) {
            $i = New-Object EmiItem
            $i.Name = $t.Name; $i.Detail = $t.Info; $i.Tag = $t.Id
            $i.Recommended = $t.Recommended; $i.Selected = ($P.Sel -and $t.Recommended)
            $i.Category = $t.Category
            $i.SizeText = if ($t.Recommended) { 'recomendado' } else { 'opcional' }
            [void]$db.Add($i)
        }
        return ,$db
    } -OnDone {
        param($r)
        $ui.LvDebloat.ItemsSource = @($r)[-1]
    }
}

function Update-EmiHome {
    <#  Pide en segundo plano el estado del equipo; Set-EmiStatusView lo pinta.
        Si ya hay una consulta en marcha, se repite al acabar. #>
    param([switch] $WithAnyDesk)
    if ($WithAnyDesk) { $script:StatusWantAnyDesk = $true }
    if ($script:StatusPs) { $script:StatusPending = $true; return }
    try {
        if (-not $script:StatusRs -or $script:StatusRs.RunspaceStateInfo.State -ne 'Opened') { $script:StatusRs = New-EmiWorkerRunspace }
        $script:StatusRs.SessionStateProxy.SetVariable('EmiWithAnyDesk', [bool]$script:StatusWantAnyDesk)
        $script:StatusWantAnyDesk = $false
        $ps = [powershell]::Create()
        $ps.Runspace = $script:StatusRs
        [void]$ps.AddScript($script:PreambleOnce + "`n" + $script:StatusQuery, $true)
        $script:StatusPs = $ps
        $script:StatusHandle = $ps.BeginInvoke()
    } catch {
        Write-EmiLog ('No se pudo consultar el estado del equipo: ' + $_.Exception.Message) Warn
        $script:StatusPs = $null; $script:StatusHandle = $null
    }
}

# Las paginas de Sistema y Recomendaciones salen de la misma consulta
function Update-EmiSystemPage { Update-EmiHome }
function Update-EmiPrivRecsPage { Update-EmiHome }
function Update-EmiAnyDesk { Update-EmiHome -WithAnyDesk }

function Receive-EmiStatus {
    <#  Lo llama el temporizador: recoge la consulta de estado si ya termino. #>
    if (-not $script:StatusPs -or -not $script:StatusHandle.IsCompleted) { return }
    $ps = $script:StatusPs
    $script:StatusPs = $null
    $data = $null
    try { $data = @($ps.EndInvoke($script:StatusHandle))[-1] }
    catch { Write-EmiLog ('Error al consultar el estado del equipo: ' + $_.Exception.Message) Warn }
    try { foreach ($e in $ps.Streams.Error) { Write-EmiLog ('Estado del equipo: ' + [string]$e) Warn } } catch { }
    try { $ps.Dispose() } catch { }
    $script:StatusHandle = $null
    if ($data) {
        if ($data -is [System.Management.Automation.PSObject]) { $data = $data.BaseObject }
        try { Set-EmiStatusView $data } catch { Write-EmiLog ('Error al refrescar: ' + $_.Exception.Message) Warn }
    }
    if ($script:StatusPending) { $script:StatusPending = $false; Update-EmiHome }
}

function Set-EmiStatusView {
    param([hashtable] $D)
    $ui.IcDisks.ItemsSource = @($D.Disks)

    $p = $D.Privacy
    $ui.TbStatPrivacy.Text = if ($p.Clean) { 'Desactivada correctamente' }
                             else { 'Nivel: ' + $p.TelemetryLevel + ' / DiagTrack: ' + $p.DiagTrack }
    $f = $D.Fast
    $ui.TbStatFast.Text = $f.StatusText
    $n = [int]$D.Eset
    $ui.TbStatEset.Text = if ($n -gt 0) { [string]$n + ' reglas KB332 activas' } else { 'Sin reglas aplicadas' }

    $z = $D.Zen
    $ui.TbStatZen.Text = if (-not $z.Installed) { 'Zen no instalado (no se toca)' }
                         elseif ($z.IsDefault)  { 'Zen es el predeterminado' }
                         else { 'Predeterminado actual: ' + $z.CurrentDefault }
    $m = $D.Mem
    $ui.TbStatRam.Text = $m.UsedText + ' de ' + $m.TotalText + ' en uso (' + $m.Percent + '%)'

    $s = $D.Summary
    $ui.TbStatPc.Text  = $s.Computer + ' - ' + $s.OS
    $ui.TbHello.Text   = 'Poner a punto ' + $s.Computer
    $ui.TbUndoCount.Text = [string]$D.Undo + ' cambios registrados'
    $ui.TbAdminBadge.Text = if ($D.Admin) { 'Ejecutando como administrador.' }
                            else { 'SIN administrador: cierra y abre EmiToolkit.cmd.' }

    # Navegador y energia
    $ui.TbZenState.Text = if (-not $z.Installed) { 'Zen Browser no esta instalado en este equipo.' }
                          elseif ($z.IsDefault)  { 'Zen ya es el navegador predeterminado (' + $z.Path + ').' }
                          else { 'Zen instalado en ' + $z.Path + '. Predeterminado actual: ' + $z.CurrentDefault + '.' }
    $ui.BtnZenSet.IsEnabled = [bool]$z.Installed
    $ui.TbFastState.Text = 'Estado actual: ' + $f.StatusText
    $ui.TbSysInfo.Text = $s.Computer + ' / ' + $s.User + "`n" + $s.OS + "`n" + $s.Cpu + "`n" + 'RAM: ' + $s.Ram + '   Encendido hace: ' + $D.Uptime

    # Recomendaciones de privacidad
    $zr = $D.ZenRecs
    if (-not $zr.Installed) {
        $ui.TbPrivRecZenState.Text = 'Zen Browser no esta instalado.'
        $ui.BtnPrivRecZenSet.Visibility = 'Collapsed'
        $ui.BtnPrivRecZenDownload.Visibility = 'Visible'
        $ui.CardUblock.Visibility = 'Collapsed'
    } else {
        $ui.TbPrivRecZenState.Text = if ($zr.IsDefault) { 'Zen ya es el navegador predeterminado (' + $zr.Path + ').' }
                                     else { 'Zen instalado en ' + $zr.Path + '. Predeterminado actual: ' + $zr.CurrentDefault + '.' }
        $ui.BtnPrivRecZenSet.Visibility = if ($zr.IsDefault) { 'Collapsed' } else { 'Visible' }
        $ui.BtnPrivRecZenDownload.Visibility = 'Collapsed'
        $ui.CardUblock.Visibility = 'Visible'
        $ui.TbPrivRecUblockState.Text = if ($zr.UblockInstalled) { 'uBlock Origin ya esta instalado.' } else { 'uBlock Origin NO esta instalado. Recomendado.' }
        $ui.BtnPrivRecUblockInstall.IsEnabled = -not $zr.UblockInstalled
        $ui.BtnPrivRecUblockInstall.Content   = if ($zr.UblockInstalled) { 'Ya instalado' } else { 'Instalar uBlock Origin' }
    }

    if ($D.ContainsKey('AnyDesk') -and $D.AnyDesk) {
        $a = $D.AnyDesk
        if ($a.Installed) {
            $ui.TbAnyState.Text = 'AnyDesk ya esta instalado en este equipo.'
            $ui.TbAnyId.Text    = if ($a.Id) { 'Tu direccion de AnyDesk: ' + $a.Id } else { 'Abre AnyDesk para ver tu direccion (9 o 10 cifras).' }
            $ui.BtnAnyOpen.IsEnabled = $true
        } else {
            $ui.TbAnyState.Text = 'AnyDesk todavia no esta instalado.'
            $ui.TbAnyId.Text    = if ($a.Downloaded) { 'Ya tienes AnyDesk.exe en Descargas: abrelo para instalarlo.' }
                                  else { 'Empieza por el paso 1 para descargarlo.' }
            $ui.BtnAnyOpen.IsEnabled = $false
        }
        $ui.IcAnySteps.ItemsSource = @($D.AnySteps)
    }
}

function Get-EmiChecked {
    param($ListView)
    $sel = New-Object System.Collections.ArrayList
    if ($ListView.ItemsSource) {
        foreach ($i in $ListView.ItemsSource) { if ($i.Selected) { [void]$sel.Add($i) } }
    }
    return $sel
}

function Show-EmiConfirmList {
    <#  Ventana de confirmacion con la lista de lo que se va a hacer (con barra de
        desplazamiento si es larga). El boton por defecto es Cancelar: Intro o
        Esc no aplican nada. Devuelve $true solo si se pulsa el boton de aplicar. #>
    param(
        [string] $Title,
        [string] $Intro,
        [string] $Body,
        [string] $Warning,
        [string] $YesText = 'Aplicar'
    )
    $w = New-Object System.Windows.Window
    $w.Title  = $Title
    $w.Width  = 600; $w.Height = 560; $w.MinWidth = 420; $w.MinHeight = 320
    $w.WindowStartupLocation = 'CenterOwner'
    $w.ShowInTaskbar = $false
    $w.ResizeMode = 'CanResizeWithGrip'
    try { $w.Owner = $win } catch { $w.WindowStartupLocation = 'CenterScreen' }

    $dock = New-Object System.Windows.Controls.DockPanel
    $dock.Margin = [System.Windows.Thickness]::new(16)

    $tbIntro = New-Object System.Windows.Controls.TextBlock
    $tbIntro.Text = $Intro; $tbIntro.TextWrapping = 'Wrap'; $tbIntro.FontSize = 14
    $tbIntro.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    [System.Windows.Controls.DockPanel]::SetDock($tbIntro, 'Top')
    [void]$dock.Children.Add($tbIntro)

    if ($Warning) {
        $tbWarn = New-Object System.Windows.Controls.TextBlock
        $tbWarn.Text = $Warning; $tbWarn.TextWrapping = 'Wrap'; $tbWarn.FontWeight = 'SemiBold'
        $tbWarn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom('#FFA4262C')
        $tbWarn.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        [System.Windows.Controls.DockPanel]::SetDock($tbWarn, 'Top')
        [void]$dock.Children.Add($tbWarn)
    }

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'; $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($buttons, 'Bottom')
    $btnYes = New-Object System.Windows.Controls.Button
    $btnYes.Content = $YesText; $btnYes.MinWidth = 110; $btnYes.Padding = [System.Windows.Thickness]::new(12, 4, 12, 4)
    $btnYes.Add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    $btnNo = New-Object System.Windows.Controls.Button
    $btnNo.Content = 'Cancelar'; $btnNo.MinWidth = 110; $btnNo.Padding = [System.Windows.Thickness]::new(12, 4, 12, 4)
    $btnNo.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $btnNo.IsDefault = $true; $btnNo.IsCancel = $true
    [void]$buttons.Children.Add($btnYes)
    [void]$buttons.Children.Add($btnNo)
    [void]$dock.Children.Add($buttons)

    $tbBody = New-Object System.Windows.Controls.TextBox
    $tbBody.Text = $Body; $tbBody.IsReadOnly = $true; $tbBody.TextWrapping = 'Wrap'
    $tbBody.VerticalScrollBarVisibility = 'Auto'; $tbBody.FontFamily = 'Segoe UI'; $tbBody.FontSize = 13
    $tbBody.Padding = [System.Windows.Thickness]::new(6)
    [void]$dock.Children.Add($tbBody)

    $w.Content = $dock
    [System.Windows.Input.FocusManager]::SetFocusedElement($w, $btnNo)
    return ($w.ShowDialog() -eq $true)
}

# ======================================================================
#                            BOTON UNICO
# ======================================================================

$ui.BtnOneClick.Add_Click({
    $p = @{
        Restore = [bool]$ui.ChkRestore.IsChecked
        Eset    = [bool]$ui.ChkEsetInclude.IsChecked
        Zen     = [bool]$ui.ChkZenInclude.IsChecked
    }

    # Primero se prepara la lista exacta de lo que se hara (el arranque se
    # analiza en segundo plano) y se pide confirmacion; luego se aplica eso mismo.
    Start-EmiWork -Label 'Preparando la lista de cambios...' -Parameters $p -Work {
        $clean = @(Get-EmiCleanupTargets | Where-Object { $_.Safe })
        $eset  = @()
        if ($P.Eset) { $eset = @(Get-EmiEsetGroups | Where-Object { -not ($_.ContainsKey('Optional') -and $_.Optional) } | ForEach-Object { $_.Name }) }
        $zen = Get-EmiZenInfo
        return @{
            Restore     = $P.Restore
            CleanIds    = @($clean | ForEach-Object { $_.Id })
            CleanNames  = @($clean | ForEach-Object { $_.Name })
            Recycle     = [bool]($clean | Where-Object { $_.Id -eq 'Recycle' })
            TweakIds    = @(Get-EmiTweaks | Where-Object { $_.Recommended } | ForEach-Object { $_.Id })
            TweakNames  = @(Get-EmiTweaks | Where-Object { $_.Recommended } | ForEach-Object { $_.Name })
            PrivIds     = @(Get-EmiPrivacyItems | Where-Object { $_.Recommended } | ForEach-Object { $_.Id })
            PrivNames   = @(Get-EmiPrivacyItems | Where-Object { $_.Recommended } | ForEach-Object { $_.Name })
            Startup     = @(Get-EmiStartupItems | Where-Object { $_.Recommended -and -not $_.Locked } | ForEach-Object { [pscustomobject]@{ Tag = $_.Tag; Name = $_.Name } })
            FastOn      = [bool](Get-EmiFastStartup).Enabled
            Eset        = $P.Eset
            EsetGroups  = $eset
            Zen         = $P.Zen
            ZenInstalled = [bool]$zen.Installed
            ZenDefault  = [bool]$zen.IsDefault
        }
    } -OnDone {
        param($r)
        $plan = @($r)[-1]
        if ($plan) { $plan = $plan.PSObject.BaseObject }
        if (-not ($plan -is [hashtable])) {
            [System.Windows.MessageBox]::Show('No se pudo preparar la lista de cambios. Mira el registro.', 'Another''s Toolbox', 'OK', 'Warning') | Out-Null
            return
        }
        $nl = "`n"
        $lst = { param($names) if (@($names).Count -eq 0) { '   (nada)' } else { (@($names) | ForEach-Object { '   - ' + $_ }) -join "`n" } }

        $b  = '1. Limpieza de disco: ' + @($plan.CleanNames).Count + ' ubicaciones. NO se puede deshacer.' + $nl + (& $lst $plan.CleanNames) + $nl + $nl
        $b += '2. Optimizaciones de Windows 11: ' + @($plan.TweakNames).Count + ' ajustes (reversibles desde Registro y deshacer).' + $nl + (& $lst $plan.TweakNames) + $nl + $nl
        $b += '3. Telemetria y privacidad: ' + @($plan.PrivNames).Count + ' ajustes (reversibles desde Registro y deshacer).' + $nl + (& $lst $plan.PrivNames) + $nl + $nl
        $b += '4. Programas de arranque: se quitan ' + @($plan.Startup).Count + ' (se pueden reactivar en Arranque).' + $nl + (& $lst @($plan.Startup | ForEach-Object { $_.Name })) + $nl + $nl
        $b += '5. Inicio rapido: ' + $(if ($plan.FastOn) { 'se desactiva (reversible).' } else { 'ya esta desactivado, no se toca.' }) + $nl + $nl
        $b += '6. Firewall de ESET (KB332): ' + $(if ($plan.Eset) { [string]@($plan.EsetGroups).Count + ' grupos de reglas (se pueden quitar en ESET).' + $nl + (& $lst $plan.EsetGroups) } else { 'omitido.' }) + $nl + $nl
        $b += '7. Navegador predeterminado: ' + $(if (-not $plan.Zen) { 'omitido.' } elseif (-not $plan.ZenInstalled) { 'Zen no esta instalado, no se toca.' } elseif ($plan.ZenDefault) { 'Zen ya es el predeterminado.' } else { 'se pone Zen como predeterminado.' }) + $nl + $nl
        $b += 'Punto de restauracion antes de empezar: ' + $(if ($plan.Restore) { 'si.' } else { 'NO (desmarcado).' })

        $warn = 'Lo que NO se puede deshacer: la limpieza de disco borra para siempre el contenido de esas carpetas'
        if ($plan.Recycle) { $warn += ' y VACIA LA PAPELERA (lo que haya en ella no se podra recuperar)' }
        $warn += '. Revisa la lista antes de continuar.'

        $ok = Show-EmiConfirmList -Title 'Optimizar ahora: confirmar' -YesText 'Optimizar ahora' `
              -Intro 'Se aplicara lo siguiente en este equipo:' -Body $b -Warning $warn
        if (-not $ok) { Write-EmiLog 'Mantenimiento cancelado por el usuario.' Info; return }
        Start-EmiMaintenance $plan
    }
})

function Start-EmiMaintenance {
    param([hashtable] $Plan)
    Start-EmiWork -Label 'Mantenimiento completo...' -Parameters $Plan -Work {

        $freed = 0
        $rp = $null
        if ($P.Restore) { $rp = [bool](@(New-EmiRestorePoint)[-1]) }

        Write-EmiLog '=== 1/7  Limpieza de disco ===' Step
        $freed = Invoke-EmiCleanup -Ids $P.CleanIds

        Write-EmiLog '=== 2/7  Optimizacion de Windows 11 ===' Step
        [void](Invoke-EmiTweakSet -Ids $P.TweakIds)

        Write-EmiLog '=== 3/7  Telemetria ===' Step
        [void](Invoke-EmiPrivacySet -Ids $P.PrivIds)

        Write-EmiLog '=== 4/7  Programas de arranque ===' Step
        # Solo las entradas que se ensenaron en la confirmacion
        $tags  = @($P.Startup | ForEach-Object { $_.Tag })
        $items = @(Get-EmiStartupItems | Where-Object { $tags -contains $_.Tag -and -not $_.Locked })
        if ($items.Count -gt 0) { [void](Invoke-EmiStartupCleanup -Items $items) }
        else { Write-EmiLog 'Nada que quitar del arranque.' Ok }

        Write-EmiLog '=== 5/7  Inicio rapido ===' Step
        [void](Disable-EmiFastStartup)

        if ($P.Eset) {
            Write-EmiLog '=== 6/7  Firewall de ESET (KB332) ===' Step
            if (@($P.EsetGroups).Count -gt 0) { [void](Invoke-EmiEsetFirewall -Groups $P.EsetGroups -ResolveHostnames) }
            else { [void](Invoke-EmiEsetFirewall -ResolveHostnames) }
        } else { Write-EmiLog '=== 6/7  Firewall de ESET omitido ===' Info }

        if ($P.Zen) {
            Write-EmiLog '=== 7/7  Navegador predeterminado ===' Step
            [void](Set-EmiZenDefault)
        } else { Write-EmiLog '=== 7/7  Navegador omitido ===' Info }

        Write-EmiLog "MANTENIMIENTO TERMINADO. Espacio liberado: $(Format-EmiSize $freed)" Ok
        Set-EmiStatus 'Mantenimiento terminado' 100
        return @{ Freed = $freed; Restore = $rp }

    } -OnDone {
        param($r)
        Update-EmiHome
        $res = @($r)[-1]
        $freed = 0; if ($res -and $res.Freed) { $freed = $res.Freed }
        $extra = 'Espacio liberado: ' + (Format-EmiSize $freed) + "`n`n" + 'Conviene reiniciar el equipo para que todo se aplique.'
        $rpFailed = ($res -and $res.Restore -eq $false)
        if ($rpFailed) { $extra = 'ATENCION: no se pudo crear el punto de restauracion, asi que no hay uno de antes de estos cambios. Lo registrado se puede revertir desde Registro y deshacer.' + "`n`n" + $extra }
        Show-EmiTaskDone 'Mantenimiento terminado' -Extra $extra -Warn:$rpFailed
    }
}

# ======================================================================
#                               DISCO
# ======================================================================

$ui.BtnDiskScan.Add_Click({
    Start-EmiWork -Label 'Analizando basura...' -Work {
        return ,(Measure-EmiCleanupTargets)
    } -OnDone {
        param($r)
        $items = @($r)[-1]
        $ui.LvClean.ItemsSource = $items
        $tot = 0; foreach ($i in $items) { if ($i.Selected) { $tot += $i.Size } }
        $ui.TbDiskTotal.Text = "Seleccionado: $(Format-EmiSize $tot)"
    }
})

$ui.BtnDiskClean.Add_Click({
    $sel = Get-EmiChecked $ui.LvClean
    if ($sel.Count -eq 0) { [System.Windows.MessageBox]::Show('Analiza primero y marca que limpiar.','Another''s Toolbox','OK','Information') | Out-Null; return }

    $risky = @($sel | Where-Object { $_.Category -eq 'Revisar' })
    if ($risky.Count -gt 0) {
        $n = ($risky | ForEach-Object { $_.Name }) -join "`n - "
        $riskyMsg = 'Has marcado ubicaciones que pueden contener archivos tuyos:' + "`n`n" + ' - ' + $n + "`n`n" + 'Continuar?'
        $ans = [System.Windows.MessageBox]::Show($riskyMsg, 'Confirmar limpieza', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
        if ($ans -ne 'Yes') { return }
    }

    $ids = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Limpiando...' -Parameters @{ Ids = $ids } -Work {
        return (Invoke-EmiCleanup -Ids $P.Ids)
    } -OnDone {
        param($r)
        $freed = 0; if ($r) { $freed = @($r)[-1] }
        $ui.TbDiskTotal.Text = "Liberado: $(Format-EmiSize $freed)"
        Update-EmiHome
        Show-EmiTaskDone 'Limpieza terminada' -Extra ('Liberado: ' + (Format-EmiSize $freed))
        $ui.BtnDiskScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
})

$ui.BtnDiskDism.Add_Click({
    $dismMsg = 'Se limpiaran las versiones antiguas de los componentes de Windows (WinSxS) con DISM.' + "`n`n" + 'Puede tardar varios minutos y NO se puede deshacer: despues ya no podras desinstalar las actualizaciones de Windows que ya estan instaladas.' + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($dismMsg, 'Limpiar componentes (DISM)', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }
    Start-EmiWork -Label 'DISM: limpiando componentes...' -Work { return (Invoke-EmiComponentCleanup) } -OnDone {
        Update-EmiHome; Show-EmiTaskDone 'Limpieza de componentes (DISM) terminada'
    }
})

$ui.BtnScanFiles.Add_Click({
    $path = $ui.TxtScanPath.Text
    if (-not (Test-Path -LiteralPath $path)) { [System.Windows.MessageBox]::Show('Esa carpeta no existe.','Another''s Toolbox','OK','Warning') | Out-Null; return }
    $min = 100; [void][int]::TryParse($ui.TxtScanMin.Text, [ref]$min)

    Start-EmiWork -Label "Buscando archivos grandes..." -Parameters @{ Path = $path; Min = $min } -Work {
        return ,(Find-EmiLargeFiles -Path $P.Path -MinMB $P.Min -Top 300)
    } -OnDone { param($r) $ui.LvBig.ItemsSource = @($r)[-1] }
})

$ui.BtnScanFolders.Add_Click({
    $path = $ui.TxtScanPath.Text
    if (-not (Test-Path -LiteralPath $path)) { [System.Windows.MessageBox]::Show('Esa carpeta no existe.','Another''s Toolbox','OK','Warning') | Out-Null; return }
    Start-EmiWork -Label 'Midiendo carpetas...' -Parameters @{ Path = $path } -Work {
        return ,(Find-EmiLargeFolders -Path $P.Path)
    } -OnDone { param($r) $ui.LvBig.ItemsSource = @($r)[-1] }
})

$ui.BtnOpenFile.Add_Click({
    $it = $ui.LvBig.SelectedItem
    if (-not $it) { return }
    if (Test-Path -LiteralPath $it.Path -PathType Leaf) { Start-Process explorer.exe "/select,`"$($it.Path)`"" }
    else { Start-Process explorer.exe "`"$($it.Path)`"" }
})

$ui.BtnDeleteBig.Add_Click({
    $sel = Get-EmiChecked $ui.LvBig
    if ($sel.Count -eq 0) { return }
    $tot = ($sel | Measure-Object Size -Sum).Sum
    $recMsg = 'Se enviaran ' + $sel.Count + ' elementos a la papelera (' + (Format-EmiSize $tot) + ').' + "`n" + 'Podras recuperarlos desde la papelera.' + "`n`n" + 'Algunos pueden omitirse (unidades de red o extraibles, discos sin papelera o archivos que superan su cuota): no se borran y el motivo queda en el registro.' + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($recMsg, 'Confirmar', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }

    $paths = @($sel | ForEach-Object { $_.Path })
    Start-EmiWork -Label 'Enviando a la papelera...' -Parameters @{ Paths = $paths } -Work {
        return (Remove-EmiFilesToRecycleBin -Paths $P.Paths)
    } -OnDone { Update-EmiHome; Show-EmiTaskDone 'Archivos enviados a la papelera' }
})

# ======================================================================
#                            OPTIMIZAR
# ======================================================================

$ui.BtnTweakRecommended.Add_Click({
    foreach ($i in $ui.LvTweaks.ItemsSource) { $i.Selected = $i.Recommended }
})

$ui.BtnTweakApply.Add_Click({
    $ids = @((Get-EmiChecked $ui.LvTweaks) | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { return }
    Start-EmiWork -Label 'Optimizando Windows...' -Parameters @{ Ids = $ids } -Work {
        return (Invoke-EmiTweakSet -Ids $P.Ids)
    } -OnDone {
        Update-EmiHome
        Show-EmiTaskDone 'Optimizacion aplicada' -Extra 'Algunos cambios necesitan reiniciar el Explorador o el equipo.'
    }
})

$ui.BtnRestartExplorer.Add_Click({
    Start-EmiWork -Label 'Reiniciando el Explorador...' -Work { return (Restart-EmiExplorer) } -OnDone {
        Show-EmiTaskDone 'Reinicio del Explorador' -OnlyIfIssues
    }
})

# ======================================================================
#                            PRIVACIDAD
# ======================================================================

$ui.BtnPrivRecommended.Add_Click({
    foreach ($i in $ui.LvPrivacy.ItemsSource) { $i.Selected = $i.Recommended }
})

$ui.BtnPrivApply.Add_Click({
    $selP = @(Get-EmiChecked $ui.LvPrivacy)
    $ids  = @($selP | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { return }
    $privBody = (@($selP | ForEach-Object { ' - ' + $_.Name + '  (' + $_.Detail + ')' }) -join "`n")
    $privWarn = ''
    if ($ids -contains 'HostsBlock') { $privWarn = 'Incluye el bloqueo por el archivo hosts: modifica C:\Windows\System32\drivers\etc\hosts (se guarda una copia y se puede revertir).' }
    $ok = Show-EmiConfirmList -Title 'Telemetria: confirmar' -YesText 'Aplicar' -Body $privBody -Warning $privWarn `
          -Intro ('Se aplicaran ' + $ids.Count + ' ajustes de privacidad. Se pueden revertir desde Registro y deshacer.')
    if (-not $ok) { return }
    Start-EmiWork -Label 'Desactivando telemetria...' -Parameters @{ Ids = $ids } -Work {
        return (Invoke-EmiPrivacySet -Ids $P.Ids)
    } -OnDone { Update-EmiHome; Show-EmiTaskDone 'Ajustes de privacidad aplicados' }
})

# ======================================================================
#                   RECOMENDACIONES DE PRIVACIDAD
# ======================================================================

function Update-EmiVaultUI {
    if (Test-EmiVaultUnlocked) {
        $ui.TbVaultLockedMsg.Visibility = 'Collapsed'
        $ui.SpVaultContent.Visibility   = 'Visible'
        $ui.BtnVaultUnlock.Visibility   = 'Collapsed'
        $ui.BtnVaultLock.Visibility     = 'Visible'
        $displayEntries = Get-EmiVaultEntries
        $ui.LvVault.ItemsSource = $displayEntries
        $ui.TbVaultCount.Text = "$($displayEntries.Count) entradas guardadas"
    } else {
        $ui.TbVaultLockedMsg.Visibility = 'Visible'
        $ui.SpVaultContent.Visibility   = 'Collapsed'
        $ui.BtnVaultUnlock.Visibility   = 'Visible'
        $ui.BtnVaultLock.Visibility     = 'Collapsed'
        $ui.LvVault.ItemsSource = $null
        $ui.TbVaultCount.Text = ''
    }
}

$ui.BtnHibpOpen.Add_Click({ Open-EmiHibpPage })
$ui.BtnLastPassOpen.Add_Click({ Open-EmiLastPassPage })

$ui.BtnPrivRecZenDownload.Add_Click({ Open-EmiUrl 'https://zen-browser.app/' })   # sin elevar: el navegador no hereda el token de administrador

$ui.BtnPrivRecZenSet.Add_Click({
    Start-EmiWork -Label 'Configurando Zen...' -Work { return (Set-EmiZenDefault) } -OnDone {
        Update-EmiHome
        Show-EmiTaskDone 'Configuracion de Zen' -OnlyIfIssues
    }
})

$ui.BtnPrivRecUblockInstall.Add_Click({ Open-EmiUblockInstall })

$ui.BtnVaultUnlock.Add_Click({
    $ok = Request-EmiVaultUnlock
    if ($ok) {
        Write-EmiLog 'Almacen de contrasenas desbloqueado.' Ok
        Update-EmiVaultUI
    } else {
        Write-EmiLog 'No se pudo desbloquear el almacen de contrasenas (detalles arriba).' Warn
    }
})

$ui.BtnVaultLock.Add_Click({
    Lock-EmiVault
    Clear-EmiSecretClipboard
    Write-EmiLog 'Almacen de contrasenas bloqueado.' Info
    Update-EmiVaultUI
})

$ui.BtnGenPassword.Add_Click({
    $special = [bool]$ui.ChkGenSpecial.IsChecked
    $pw = New-EmiSecurePassword -Length 20 -IncludeSpecial:$special
    $ui.TxtGenPassword.Text = $pw
})

# Copia un secreto al portapapeles y lo limpia a los 30 segundos. Lleva los
# formatos que Windows respeta para no guardarlo en el historial (Win+V) ni
# subirlo al portapapeles en la nube. Reintenta si otro programa (AnyDesk,
# Escritorio remoto) tiene el portapapeles abierto; nunca cierra la app.
function Copy-EmiSecret {
    param([string] $Text, [string] $Label)
    $do = New-Object System.Windows.DataObject
    $do.SetData([System.Windows.DataFormats]::UnicodeText, $Text)
    $zero = [BitConverter]::GetBytes([int]0)
    $do.SetData('ExcludeClipboardContentFromMonitorProcessing', (New-Object System.IO.MemoryStream(,$zero)))
    $do.SetData('CanIncludeInClipboardHistory', (New-Object System.IO.MemoryStream(,$zero)))
    $do.SetData('CanUploadToCloudClipboard', (New-Object System.IO.MemoryStream(,$zero)))
    $ok = $false
    for ($i = 0; $i -lt 5 -and -not $ok; $i++) {
        try { [System.Windows.Clipboard]::SetDataObject($do, $true); $ok = $true }
        catch { Start-Sleep -Milliseconds 80 }
    }
    if (-not $ok) { Write-EmiLog 'No se pudo copiar: otro programa tiene el portapapeles ocupado. Prueba de nuevo.' Warn; return }
    $script:ClipTimer.Tag = "$([DateTime]::UtcNow.Ticks):$Text"
    $script:ClipTimer.Stop(); $script:ClipTimer.Start()
    Write-EmiLog "$Label copiado. El portapapeles se limpiara en 30 segundos." Ok
}
# Borra el portapapeles ya, si sigue conteniendo el ultimo secreto copiado
function Clear-EmiSecretClipboard {
    try {
        $snapshot = [string]$script:ClipTimer.Tag
        if (-not $snapshot) { return }
        $secret = $snapshot.Substring($snapshot.IndexOf(':') + 1)
        if ([System.Windows.Clipboard]::ContainsText() -and [System.Windows.Clipboard]::GetText() -eq $secret) {
            [System.Windows.Clipboard]::Clear()
            Write-EmiLog 'Portapapeles limpiado.' Info
        }
    } catch { }
    $script:ClipTimer.Tag = $null
    $script:ClipTimer.Stop()
}
# Timer que limpia el portapapeles si sigue conteniendo el secreto copiado
$script:ClipTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ClipTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:ClipTimer.Add_Tick({ Clear-EmiSecretClipboard })

$ui.BtnGenCopy.Add_Click({
    if ($ui.TxtGenPassword.Text -and $ui.TxtGenPassword.Text -ne 'Pulsa Generar para crear una contrasena') {
        Copy-EmiSecret $ui.TxtGenPassword.Text 'Contrasena'
    }
})

$ui.BtnVaultGenForEntry.Add_Click({
    $special = [bool]$ui.ChkGenSpecial.IsChecked
    $pw = New-EmiSecurePassword -Length 20 -IncludeSpecial:$special
    $ui.TxtVaultPassword.Text = $pw
})

$ui.BtnVaultAdd.Add_Click({
    $app   = $ui.TxtVaultAppName.Text.Trim()
    $email = $ui.TxtVaultEmail.Text.Trim()
    $pw    = $ui.TxtVaultPassword.Text
    if (-not $app -or -not $pw) {
        [System.Windows.MessageBox]::Show('Rellena al menos el nombre del servicio y la contrasena.', 'Another''s Toolbox', 'OK', 'Warning') | Out-Null
        return
    }
    $id = Add-EmiVaultEntry -AppName $app -Email $email -Password $pw -Notes ''
    if ($id) {
        $ui.TxtVaultAppName.Text  = ''
        $ui.TxtVaultEmail.Text    = ''
        $ui.TxtVaultPassword.Text = ''
        Update-EmiVaultUI
        Write-EmiLog 'Entrada guardada en el almacen.' Ok   # sin el nombre del servicio: el log no es secreto
    }
})

$ui.BtnVaultCopyPw.Add_Click({
    $sel = $ui.LvVault.SelectedItem
    if (-not $sel) { return }
    $entry = Get-EmiVaultEntryPlain -Id $sel.Id
    if ($entry) {
        Copy-EmiSecret $entry.Password 'Contrasena'
    }
})

$ui.BtnVaultCopyEmail.Add_Click({
    $sel = $ui.LvVault.SelectedItem
    if (-not $sel) { return }
    $entry = Get-EmiVaultEntryPlain -Id $sel.Id
    if ($entry -and $entry.Email) {
        Copy-EmiSecret $entry.Email 'Correo'
    }
})

$ui.BtnVaultDelete.Add_Click({
    $sel = $ui.LvVault.SelectedItem
    if (-not $sel) { return }
    $delMsg = 'Eliminar la entrada ''' + $sel.AppName + '''? Esta accion no se puede deshacer.'
    $ans = [System.Windows.MessageBox]::Show($delMsg, 'Confirmar', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }
    $removed = Remove-EmiVaultEntry -Id $sel.Id
    Update-EmiVaultUI
    if ($removed) { Write-EmiLog 'Entrada eliminada del almacen.' Ok }
})

# ======================================================================
#                              DEBLOAT
# ======================================================================

$ui.BtnDebloatRecommended.Add_Click({
    foreach ($i in $ui.LvDebloat.ItemsSource) { $i.Selected = $i.Recommended }
})

$ui.BtnDebloatApply.Add_Click({
    $selD = @(Get-EmiChecked $ui.LvDebloat)
    $ids  = @($selD | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { return }
    $dbBody = (@($selD | ForEach-Object { ' - ' + $_.Name + $(if ($_.Category) { '  [' + $_.Category + ']' } else { '' }) }) -join "`n")
    $ok = Show-EmiConfirmList -Title 'Debloat: confirmar' -YesText 'Quitar' -Body $dbBody `
          -Intro ('Se quitaran ' + $ids.Count + ' apps o caracteristicas de Windows:') `
          -Warning 'Las apps se desinstalan de tu usuario y dejan de instalarse en los usuarios nuevos. Algunas solo se recuperan reinstalandolas desde Microsoft Store y otras no se pueden reinstalar. Las caracteristicas de Windows se pueden volver a activar.'
    if (-not $ok) { return }
    Start-EmiWork -Label 'Aplicando debloat...' -Parameters @{ Ids = $ids } -Work {
        return (Invoke-EmiDebloatSet -Ids $P.Ids)
    } -OnDone {
        Update-EmiHome
        Show-EmiTaskDone 'Debloat terminado' -Extra 'Algunos cambios de caracteristicas de Windows necesitan reiniciar.'
        # Volver a leer el catalogo (apps quitadas, caracteristicas cambiadas), en segundo plano
        Start-EmiDebloatLoad
    }
})

# ======================================================================
#                          APLICACIONES
# ======================================================================

$ui.BtnAppsScan.Add_Click({
    Start-EmiWork -Label 'Analizando apps instaladas...' -Work {
        return ,(Get-EmiInstalledApps)
    } -OnDone {
        param($r)
        $items = @($r)[-1]
        $list = New-Object System.Collections.ArrayList
        foreach ($a in $items) {
            $i = New-Object EmiItem
            $i.Name = $a.Name; $i.Detail = $a.Detail; $i.Tag = $a.Id
            $i.Status = $a.Version
            $i.Size = $a.CacheSize
            $i.SizeText = if ($a.CacheSize -gt 0) { Format-EmiSize $a.CacheSize } else { '' }
            [void]$list.Add($i)
        }
        $ui.LvApps.ItemsSource = $list
        Write-EmiLog ($list.Count.ToString() + ' apps instaladas encontradas.') Ok
    }
})

$ui.BtnAppsUninstall.Add_Click({
    $sel = @(Get-EmiChecked $ui.LvApps)
    if ($sel.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Analiza primero y marca que apps desinstalar.','Another''s Toolbox','OK','Information') | Out-Null
        return
    }
    $names = ($sel | ForEach-Object { $_.Name }) -join "`n - "
    $uninstAppsMsg = 'Se desinstalaran ' + $sel.Count + ' apps del usuario actual:' + "`n`n" + ' - ' + $names + "`n`n" + 'La app puede volver a instalarse desde Microsoft Store o con el comando registrado en Deshacer. Continuar?'
    $ans = [System.Windows.MessageBox]::Show($uninstAppsMsg, 'Confirmar desinstalacion', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }

    $ids = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Desinstalando apps...' -Parameters @{ Ids = $ids } -Work {
        $n = 0
        foreach ($id in $P.Ids) { if (Remove-EmiInstalledApp -PackageFullName $id) { $n++ } }
        Write-EmiLog "$n apps desinstaladas." Ok
        return $n
    } -OnDone {
        param($r)
        Show-EmiTaskDone 'Desinstalacion terminada' -Extra ([string](@($r)[-1]) + ' apps desinstaladas.')
        $ui.BtnAppsScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        Update-EmiHome
    }
})

$ui.BtnAppsClearCache.Add_Click({
    $sel = @(Get-EmiChecked $ui.LvApps)
    if ($sel.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Marca las apps cuya cache quieres limpiar.','Another''s Toolbox','OK','Information') | Out-Null
        return
    }
    $cacheMsg = 'Se borrara la cache (LocalCache, Temp e INetCache) de ' + $sel.Count + ' apps. La app se regenerara sola al abrirse. Continuar?'
    $ans = [System.Windows.MessageBox]::Show($cacheMsg, 'Limpiar cache', 'YesNo', 'Question', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }

    # El Tag guarda el PackageFullName; el modulo resuelve la familia desde ahi
    $ids = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Limpiando cache...' -Parameters @{ Ids = $ids } -Work {
        $freed = 0
        foreach ($id in $P.Ids) { $freed += (Clear-EmiAppCacheByFullName -PackageFullName $id) }
        Write-EmiLog "Cache limpiada: $(Format-EmiSize $freed) liberados en total." Ok
        return $freed
    } -OnDone {
        param($r)
        $cf = 0; if ($r) { $cf = @($r)[-1] }
        Show-EmiTaskDone 'Cache limpiada' -Extra ('Liberado: ' + (Format-EmiSize $cf))
        $ui.BtnAppsScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        Update-EmiHome
    }
})

# ======================================================================
#                          ANOTHER STORE
# ======================================================================

$ui.BtnStoreOpenWeb.Add_Click({
    Open-EmiUrl 'https://anotherstore.neocities.org/'   # sin elevar
    Write-EmiLog 'Another Store: navegador abierto.' Ok
})

$ui.BtnStoreSelectAll.Add_Click({
    $checks = @(
        $ui.ChkStoreAudio, $ui.ChkStoreDraw, $ui.ChkStoreFinance, $ui.ChkStoreHub,
        $ui.ChkStoreMedia, $ui.ChkStorePhoto, $ui.ChkStorePixel, $ui.ChkStorePresent,
        $ui.ChkStoreReader, $ui.ChkStoreVault, $ui.ChkStoreWriter
    )
    foreach ($c in $checks) { $c.IsChecked = $true }
})

$ui.BtnStoreUninstall.Add_Click({
    $map = @{
        ChkStoreAudio   = 'Another Suite Audio'
        ChkStoreDraw    = 'Another Suite Draw'
        ChkStoreFinance = 'Another Suite Finance'
        ChkStoreHub     = 'Another Suite Hub'
        ChkStoreMedia   = 'Another Suite Media'
        ChkStorePhoto   = 'Another Suite Photo'
        ChkStorePixel   = 'Another Suite Pixel'
        ChkStorePresent = 'Another Suite Present'
        ChkStoreReader  = 'Another Suite Reader'
        ChkStoreVault   = 'Another Suite Vault'
        ChkStoreWriter  = 'Another Suite Writer'
    }
    $selected = @()
    foreach ($key in $map.Keys) {
        if ($ui.$key.IsChecked) { $selected += $map[$key] }
    }
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            'Marca al menos una app de Another Suite para desinstalar.',
            'Another''s Toolbox', 'OK', 'Information') | Out-Null
        return
    }
    $list = ($selected -join "`n - ")
    $uninstMsg = 'Se buscaran y desinstalaran ' + $selected.Count + ' apps de Another Suite:' + "`n`n" + ' - ' + $list + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($uninstMsg, 'Confirmar desinstalacion', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }

    # Editores admitidos en ...\Uninstall para las apps de Another Suite (exactos)
    $publishers = @('Another Suite', 'Anoth3rHellsing', 'Another')
    Start-EmiWork -Label 'Desinstalando apps de Another Store...' -Parameters @{ Names = $selected; Publishers = $publishers } -Work {
        $ok = 0; $fail = 0
        foreach ($name in $P.Names) {
            # DisplayName y Publisher exactos; las entradas de HKCU o de carpetas
            # del usuario se desinstalan sin privilegios (Invoke-EmiSafeUninstall)
            $found = @(Find-EmiUninstallEntry -DisplayName $name -Publisher $P.Publishers) | Select-Object -First 1
            if ($found -and ($found.QuietUninstallString -or $found.UninstallString)) {
                try {
                    $code = Invoke-EmiSafeUninstall -Entry $found
                    # 3010/1641: MSI pide reiniciar, pero desinstalo bien
                    if ($code -notin @(0, 3010, 1641)) { throw ('el desinstalador devolvio el codigo ' + $code) }
                    $ok++
                    Write-EmiLog ('Another Store: ' + $name + ' desinstalado.') Ok
                } catch {
                    $fail++
                    Write-EmiLog ('Another Store: fallo al desinstalar ' + $name + ' — ' + $_.Exception.Message) Error
                }
            } else {
                $fail++
                Write-EmiLog ('Another Store: ' + $name + ' no encontrado en el registro.') Warn
            }
        }
        return @{ Ok = $ok; Fail = $fail }
    } -OnDone {
        $r = $args[0]
        if ($r.Ok -gt 0) {
            $storeResultMsg = [string]$r.Ok + ' app(s) desinstalada(s). ' + $r.Fail + ' no encontrada(s) o con error.'
            [System.Windows.MessageBox]::Show($storeResultMsg, 'Another''s Toolbox', 'OK', 'Information') | Out-Null
        } else {
            [System.Windows.MessageBox]::Show(
                'No se pudo desinstalar ninguna app. Puede que no esten instaladas.',
                'Another''s Toolbox', 'OK', 'Warning') | Out-Null
        }
    }
})

# ======================================================================
#                               ESET
# ======================================================================

$ui.BtnEsetApply.Add_Click({
    $g = @((Get-EmiChecked $ui.LvEset) | ForEach-Object { $_.Tag })
    if ($g.Count -eq 0) { return }
    $dns = [bool]$ui.ChkEsetDns.IsChecked
    $esetMsg = 'Se crearan reglas en el Firewall de Windows para ' + $g.Count + ' grupos de servidores de ESET (KB332).' + "`n`n" + 'Se pueden quitar despues con «Quitar reglas». Continuar?'
    $ans = [System.Windows.MessageBox]::Show($esetMsg, 'Reglas de ESET', 'YesNo', 'Question', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }

    Start-EmiWork -Label 'Aplicando reglas de ESET...' -Parameters @{ G = $g; Dns = $dns } -Work {
        if ($P.Dns) { return (Invoke-EmiEsetFirewall -Groups $P.G -ResolveHostnames) }
        return (Invoke-EmiEsetFirewall -Groups $P.G)
    } -OnDone { Update-EmiHome; Show-EmiTaskDone 'Reglas de ESET aplicadas' }
})

$ui.BtnEsetTest.Add_Click({
    Start-EmiWork -Label 'Probando conexion con ESET...' -Work {
        return ,(Test-EmiEsetConnectivity)
    } -OnDone {
        param($r)
        $items = @($r)[-1]
        $bad = @($items | Where-Object { $_.Category -eq 'fail' })
        $msg = if ($bad.Count -eq 0) { 'Todos los servidores de ESET responden correctamente.' }
               else { 'No responden ' + $bad.Count + ' de ' + $items.Count + ':' + "`n`n" + ' - ' + (($bad | ForEach-Object { $_.Name + ' ' + $_.Path }) -join "`n - ") }
        [System.Windows.MessageBox]::Show($msg, 'Prueba de conexion', 'OK', 'Information') | Out-Null
    }
})

$ui.BtnEsetRemove.Add_Click({
    $ans = [System.Windows.MessageBox]::Show('Se eliminaran todas las reglas ESET KB332 creadas por esta app. Continuar?',
        'Confirmar', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }
    Start-EmiWork -Label 'Quitando reglas...' -Work { return (Remove-EmiEsetFirewall) } -OnDone { Update-EmiHome; Show-EmiTaskDone 'Reglas de ESET quitadas' }
})

# ======================================================================
#                              ARRANQUE
# ======================================================================

$ui.BtnStartupScan.Add_Click({
    Start-EmiWork -Label 'Analizando el arranque...' -Work {
        return ,(Get-EmiStartupItems)
    } -OnDone { param($r) $ui.LvStartup.ItemsSource = @($r)[-1] }
})

$ui.BtnStartupDisable.Add_Click({
    $sel = @((Get-EmiChecked $ui.LvStartup) | Where-Object { -not $_.Locked })
    if ($sel.Count -eq 0) { return }
    $tags = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Quitando del arranque...' -Parameters @{ Tags = $tags } -Work {
        $n = 0
        foreach ($t in $P.Tags) { if (Disable-EmiStartupItem -Tag $t) { $n++ } }
        Write-EmiLog "$n programas quitados del arranque." Ok
        return $n
    } -OnDone { Show-EmiTaskDone ([string](@($args[0])[-1]) + ' programas quitados del arranque'); $ui.BtnStartupScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
})

$ui.BtnStartupEnable.Add_Click({
    $sel = @(Get-EmiChecked $ui.LvStartup)
    if ($sel.Count -eq 0) { return }
    $tags = @($sel | ForEach-Object { $_.Tag })
    Start-EmiWork -Label 'Reactivando...' -Parameters @{ Tags = $tags } -Work {
        $n = 0
        foreach ($t in $P.Tags) { if (Enable-EmiStartupItem -Tag $t) { $n++ } }
        Write-EmiLog "$n programas reactivados." Ok
        return $n
    } -OnDone { Show-EmiTaskDone ([string](@($args[0])[-1]) + ' programas reactivados'); $ui.BtnStartupScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
})

# ======================================================================
#                              PROCESOS
# ======================================================================

$ui.BtnProcScan.Add_Click({
    Start-EmiWork -Label 'Analizando procesos...' -Work {
        return ,(Get-EmiProcessItems)
    } -OnDone {
        param($r)
        $ui.LvProcess.ItemsSource = @($r)[-1]
        $m = Get-EmiMemoryStatus
        $pct = $m.Percent
        $ui.TbRam.Text = 'RAM: ' + $m.UsedText + ' / ' + $m.TotalText + ' (' + $pct + '%)'
}
})

function Invoke-EmiProcAction {
    param([bool] $Block)
    $sel = @((Get-EmiChecked $ui.LvProcess) | Where-Object { -not $_.Locked })
    if ($sel.Count -eq 0) { return }

    $names = ($sel | ForEach-Object { $_.Name }) -join ', '
    $extra = if ($Block) { "`n`n" + 'Ademas, a los procesos de la categoria Telemetria se les cortara Internet con una regla de firewall (reversible desde Registro y deshacer). Al resto solo se les cierra.' } else { '' }
    $procMsg = 'Se cerraran: ' + $names + $extra + "`n`n" + 'Guarda tu trabajo antes. Continuar?'
    $ans = [System.Windows.MessageBox]::Show($procMsg, 'Confirmar', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }

    $data = @($sel | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.Path } })
    Start-EmiWork -Label 'Cerrando procesos...' -Parameters @{ D = $data; B = $Block } -Work {
        $n = 0
        foreach ($x in $P.D) {
            if (Stop-EmiProcessByName -Name $x.Name) { $n++ }
            if ($P.B -and $x.Path) { [void](Block-EmiProcessNetwork -ExePath $x.Path -Label $x.Name) }
        }
        Write-EmiLog "$n procesos cerrados." Ok
        return $n
    } -OnDone { Show-EmiTaskDone ([string](@($args[0])[-1]) + ' procesos cerrados'); $ui.BtnProcScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
}

$ui.BtnProcKill.Add_Click({ Invoke-EmiProcAction $false })
$ui.BtnProcBlock.Add_Click({ Invoke-EmiProcAction $true })

# ======================================================================
#                          VORTEX MODS
# ======================================================================

$ui.BtnVortexScan.Add_Click({
    Start-EmiWork -Label 'Analizando Vortex...' -Work {
        return ,(Get-EmiVortexItems)
    } -OnDone { param($r) $ui.LvVortex.ItemsSource = @($r)[-1] }
})

$ui.BtnVortexRemove.Add_Click({
    $sel = @((Get-EmiChecked $ui.LvVortex) | Where-Object { -not $_.Locked })
    if ($sel.Count -eq 0) { return }
    $tags = @($sel | ForEach-Object { $_.Tag })
    $purgeMsg = 'Se purgaran ' + $sel.Count + ' mods de las carpetas de juego y se eliminaran del staging.' + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($purgeMsg, 'Confirmar purga', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }
    Start-EmiWork -Label 'Purgando mods de Vortex...' -Parameters @{ Tags = $tags } -Work {
        return (Remove-EmiVortexMods -Tags $P.Tags)
    } -OnDone { Show-EmiTaskDone 'Purga de mods terminada'; $ui.BtnVortexScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
})

$ui.BtnVortexFullClean.Add_Click({
    # Buscar Vortex lee el registro y el disco: en segundo plano
    Start-EmiWork -Label 'Buscando Vortex...' -Work { return (Get-EmiVortexInfo) } -OnDone {
        param($r)
        $info = @($r)[-1]
        if (-not $info -or -not $info.Installed) {
            [System.Windows.MessageBox]::Show('Vortex no esta instalado en este equipo.', 'Another''s Toolbox', 'OK', 'Information') | Out-Null
            return
        }
        Confirm-EmiVortexFullClean
    }
})

function Confirm-EmiVortexFullClean {
    $vortexMsg = 'ELIMINACION COMPLETA DE VORTEX' + "`n`n" + 'Se purgaran TODOS los mods desplegados, se borrara APPDATA\Vortex (staging, descargas, perfiles, base de datos) y se desinstalara Vortex.' + "`n`n" + 'Esta accion es IRREVERSIBLE.' + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($vortexMsg, 'Confirmar eliminacion total', 'YesNo', 'Error', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }
    Start-EmiWork -Label 'Eliminando Vortex completamente...' -Work {
        return (Remove-EmiVortexFull)
    } -OnDone {
        Update-EmiHome
        Show-EmiTaskDone 'Eliminacion de Vortex terminada'
        $ui.BtnVortexScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
}

$ui.BtnVortexSkyrimClean.Add_Click({
    $skyrimMsg = 'FORCE CLEAN SKYRIM' + "`n`n" + 'Esta accion ELIMINARA COMPLETAMENTE:' + "`n`n" + '1. TODOS los mods de Vortex' + "`n" + '2. TODOS los datos de Vortex' + "`n" + '3. Vortex se desinstalara' + "`n" + '4. TODAS las carpetas de Skyrim (Data, Mods, configuraciones)' + "`n" + '5. TODOS los archivos de usuario (Skyrim.ini, SkyrimPrefs.ini)' + "`n" + '6. Manifiestos de despliegue de Vortex' + "`n" + '7. Carpetas en Documentos\My Games\Skyrim' + "`n`n" + 'Esta accion es IRREVERSIBLE y borrara completamente Skyrim.' + "`n`n" + 'Continuar?'
    $ans = [System.Windows.MessageBox]::Show($skyrimMsg, 'Confirmar Force Clean Skyrim', 'YesNo', 'Error', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }
    Start-EmiWork -Label 'Ejecutando Force Clean Skyrim...' -Work {
        return (Remove-EmiVortexSkyrimFull)
    } -OnDone {
        Update-EmiHome
        Show-EmiTaskDone 'Force Clean Skyrim terminado'
        $ui.BtnVortexScan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
})

# ======================================================================
#                       NAVEGADOR / ENERGIA
# ======================================================================

$ui.BtnZenSet.Add_Click({
    Start-EmiWork -Label 'Configurando Zen...' -Work { return (Set-EmiZenDefault) } -OnDone {
        param($r)
        $res = @($r)[-1]
        Update-EmiHome
        $msg = switch ($res) {
            'Done'           { 'Zen ya es el navegador predeterminado.' }
            'AlreadyDefault' { 'Zen ya era el navegador predeterminado.' }
            'NotInstalled'   { 'Zen no esta instalado: no se ha cambiado nada.' }
            default          { 'Windows pide confirmarlo a mano. Se abrio Configuracion > Aplicaciones predeterminadas: busca Zen y pulsa "Establecer como predeterminado".' }
        }
        $msg += Get-EmiTaskIssueNote
        $zenIcon = if (Get-EmiTaskIssues) { 'Warning' } else { 'Information' }
        [System.Windows.MessageBox]::Show($msg, 'Zen Browser', 'OK', $zenIcon) | Out-Null
    }
})

$ui.BtnZenSettings.Add_Click({ [void](Open-EmiDefaultAppsSettings) })

$ui.BtnFastDisable.Add_Click({
    $h = [bool]$ui.ChkHiber.IsChecked
    Start-EmiWork -Label 'Desactivando inicio rapido...' -Parameters @{ H = $h } -Work {
        if ($P.H) { return (Disable-EmiFastStartup -AlsoDisableHibernation) }
        return (Disable-EmiFastStartup)
    } -OnDone { Update-EmiHome; Show-EmiTaskDone 'Inicio rapido desactivado' -OnlyIfIssues }
})

$ui.BtnFastEnable.Add_Click({
    # En segundo plano y por la cola de tareas: escribir en el diario desde la
    # UI mientras otra tarea lo reescribe perdia entradas
    Start-EmiWork -Label 'Reactivando inicio rapido...' -Work { return (Enable-EmiFastStartup) } -OnDone {
        Update-EmiHome; Show-EmiTaskDone 'Inicio rapido reactivado' -OnlyIfIssues
    }
})

# ======================================================================
#                              ANYDESK
# ======================================================================

$ui.BtnAnyDownload.Add_Click({
    $anyMsg = 'Se abrira anydesk.com en tu navegador para descargar AnyDesk.' + "`n`n" + 'Descarga solo desde esa pagina oficial. Continuar?'
    $ans = [System.Windows.MessageBox]::Show($anyMsg, 'Descargar AnyDesk', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    [void](Open-EmiAnyDeskDownload)
})
$ui.BtnAnyFolder.Add_Click({ [void](Open-EmiDownloadsFolder) })
$ui.BtnAnyOpen.Add_Click({
    if (-not (Start-EmiAnyDesk)) {
        [System.Windows.MessageBox]::Show('AnyDesk todavia no esta instalado. Sigue los pasos 1 a 4.','AnyDesk','OK','Information') | Out-Null
    }
})

# ======================================================================
#                        REGISTRO / DESHACER
# ======================================================================

$ui.BtnUndoAll.Add_Click({
    $c = @(Get-EmiJournal).Count
    if ($c -eq 0) { [System.Windows.MessageBox]::Show('No hay cambios registrados.','Another''s Toolbox','OK','Information') | Out-Null; return }
    $undoMsg = 'Se revertiran ' + $c + ' cambios (registro, servicios, tareas y reglas de firewall). Continuar?'
    $ans = [System.Windows.MessageBox]::Show($undoMsg, 'Revertir todo', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { return }

    Start-EmiWork -Label 'Revirtiendo cambios...' -Work { return (Undo-EmiChanges) } -OnDone {
        Update-EmiHome
        $left = @(Get-EmiJournal).Count
        if ($left -gt 0) {
            $undoDone = 'Se revirtieron ' + [string](@($args[0])[-1]) + ' cambios. ' + $left + ' no se pudieron revertir y siguen registrados (detalles en el registro). Reinicia el equipo y vuelve a intentarlo.'
            [System.Windows.MessageBox]::Show($undoDone + (Get-EmiTaskIssueNote), 'Another''s Toolbox', 'OK', 'Warning') | Out-Null
        } else {
            Show-EmiTaskDone 'Cambios revertidos' -Extra 'Reinicia el equipo para que todo vuelva a su estado anterior.'
        }
    }
})

$ui.BtnOpenLog.Add_Click({ Start-Process explorer.exe (Get-EmiDataDir) })

# ======================================================================
#                        VENTANA Y ARRANQUE
# ======================================================================

$ui.BtnClose.Add_Click({ $win.Close() })
$ui.BtnMin.Add_Click({ $win.WindowState = 'Minimized' })
$ui.BtnMax.Add_Click({
    $win.WindowState = if ($win.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
})

# Red de seguridad: un error en cualquier manejador de la interfaz (un clic,
# el temporizador, el portapapeles ocupado por AnyDesk o RDP...) no debe
# cerrar la aplicacion. Se registra, se avisa y se marca como manejado.
$script:UiStarted   = $false
$script:InUiFailure = $false
$win.Dispatcher.Add_UnhandledException({
    param($sender, $e)
    $e.Handled = $true
    if ($script:InUiFailure) { return }
    $script:InUiFailure = $true
    try {
        $ex  = $e.Exception
        $msg = $ex.GetBaseException().Message
        $where = ''
        if ($ex -is [System.Management.Automation.IContainsErrorRecord] -and $ex.ErrorRecord.InvocationInfo) {
            $where = ' (linea ' + $ex.ErrorRecord.InvocationInfo.ScriptLineNumber + ')'
        }
        try { Write-EmiLog ('Error en la interfaz' + $where + ': ' + $msg) Error } catch { }
        Write-RuntimeError -Message ('Error en la interfaz' + $where + ': ' + $ex.ToString())
        $uiErrMsg = 'Esta accion ha fallado, pero la aplicacion sigue abierta.' + "`n`n" + $msg + "`n`n" + 'Los detalles estan en el registro.'
        [System.Windows.MessageBox]::Show($uiErrMsg, 'Another''s Toolbox', 'OK', 'Warning') | Out-Null
    } catch { } finally { $script:InUiFailure = $false }
})

$win.Add_SourceInitialized({
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
        [void](Enable-EmiBackdrop -Handle $h -Style 'Acrylic')
    } catch { }
})

$win.Add_Loaded({
    $script:UiStarted = $true
    # Estado del equipo y AnyDesk (su firma puede tardar sin red): en segundo plano
    Update-EmiHome -WithAnyDesk
    $ui.TbHeaderHint.Text = $env:COMPUTERNAME + ' - mantenimiento de Windows 11'
    [void]$script:StartMarks.Add('ventana ' + $script:StartClock.ElapsedMilliseconds + ' ms')
    Write-EmiLog ('Arranque: ' + $script:StartClock.ElapsedMilliseconds + ' ms (' + ($script:StartMarks -join ', ') + ').') Info
    $script:StartClock.Stop()
    Start-EmiTypeCacheBuild
})

# Cerrar la ventana con una tarea en marcha la corta a medias (DISM, una
# desinstalacion, la reversion...): se pide confirmacion, con No por defecto.
$win.Add_Closing({
    param($sender, $e)
    if (-not $script:Worker) { return }
    $closeMsg = 'Hay una tarea en curso: ' + [string]$global:EmiSync.Status + "`n`n" + 'Si cierras ahora se cortara a medias y algunos cambios pueden quedar aplicados solo en parte.' + "`n`n" + 'Cerrar igualmente?'
    $ans = [System.Windows.MessageBox]::Show($closeMsg, 'Tarea en curso', 'YesNo', 'Warning', [System.Windows.MessageBoxResult]::No)
    if ($ans -ne 'Yes') { $e.Cancel = $true }
    else { Write-EmiLog 'Ventana cerrada con una tarea en curso: se ha interrumpido.' Warn }
})

$win.Add_Closed({
    try { $timer.Stop() } catch { }
    Clear-EmiSecretClipboard   # una contrasena copiada no sobrevive a la app
    if ($script:Worker) { try { $script:Worker.Stop(); $script:Worker.Dispose() } catch { } }
    try { if ($script:StatusPs) { $script:StatusPs.Stop(); $script:StatusPs.Dispose() } } catch { }
    try { if ($script:StatusRs) { $script:StatusRs.Dispose() } } catch { }
    Write-EmiLog 'Another''s Toolbox cerrado.' Info
})

[void]$win.ShowDialog()

} catch {
    $errMsg = $_.Exception.Message
    $errLine = $_.InvocationInfo.ScriptLineNumber
    $errFile = $_.InvocationInfo.ScriptName
    # Solo es un fallo de arranque si la ventana no llego a cargarse; despues,
    # lo que llegue aqui ha cerrado la aplicacion en plena sesion.
    $errHead = if ($script:UiStarted) { 'Another''s Toolbox se ha cerrado por un error inesperado:' } else { 'Error al iniciar Another''s Toolbox:' }
    $fullMsg = $errHead + "`n`n" + $errMsg + "`n`n" + 'Línea: ' + $errLine + "`n" + 'en ' + $errFile
    Write-RuntimeError -Message $fullMsg
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    [System.Windows.Forms.MessageBox]::Show($fullMsg + "`n`nLog: " + $(try { Join-Path (Get-EmiDataDir) 'runtime-error.log' } catch { Join-Path $env:LOCALAPPDATA 'EmiToolkit\runtime-error.log' }), 'EmiToolkit Error', 'OK', 'Error') | Out-Null
}
