# =====================================================================
#  EmiPrivRecs.psm1 - Recomendaciones de privacidad y herramientas
#  Detecta estado de Zen, uBlock Origin, y abre enlaces externos.
# =====================================================================

function Get-EmiZenBrowserStatus {
    <# Devuelve objeto con Installed, IsDefault, Path, CurrentDefault, UblockInstalled #>
    $zenPaths = @(
        "$env:LOCALAPPDATA\Programs\Zen Browser\zen.exe"
        "$env:LOCALAPPDATA\Zen Browser\zen.exe"
        "$env:ProgramFiles\Zen Browser\zen.exe"
        "${env:ProgramFiles(x86)}\Zen Browser\zen.exe"
    )

    $zenPath = $null
    foreach ($p in $zenPaths) {
        if (Test-Path -LiteralPath $p) { $zenPath = $p; break }
    }

    # Fallback: buscar en registro
    if (-not $zenPath) {
        $regBase = 'HKLM:\SOFTWARE\Clients\StartMenuInternet'
        if (Test-Path $regBase) {
            foreach ($key in (Get-ChildItem $regBase -ErrorAction SilentlyContinue)) {
                $cmd = (Get-ItemProperty "$($key.PSPath)\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
                if ($cmd -and $cmd -like '*zen.exe*') {
                    $candidate = ($cmd -replace '"', '').Trim()
                    if (Test-Path -LiteralPath $candidate) { $zenPath = $candidate; break }
                }
            }
        }
    }

    $installed = [bool]$zenPath
    $isDefault = $false
    $currentDefault = ''

    if ($installed) {
        try {
            $userChoice = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction Stop
            $progId = $userChoice.ProgId
            if ($progId) {
                $cmdReg = "HKCR:\$progId\shell\open\command"
                if (-not (Test-Path $cmdReg)) { $cmdReg = "HKLM:\SOFTWARE\Classes\$progId\shell\open\command" }
                if (Test-Path $cmdReg) {
                    $defCmd = (Get-ItemProperty $cmdReg -ErrorAction SilentlyContinue).'(default)'
                    if ($defCmd -and $defCmd -like '*zen.exe*') { $isDefault = $true }
                }
                $currentDefault = $progId
            }
        } catch { }
    }

    # Detectar uBlock Origin en perfiles de Zen
    $ublockInstalled = $false
    $zenProfileRoot = Join-Path $env:APPDATA 'Zen Browser\Profiles'
    if (Test-Path $zenProfileRoot) {
        $xpiPattern = Join-Path $zenProfileRoot '*\extensions\uBlock0@raymondhill.net.xpi'
        if (Get-Item $xpiPattern -ErrorAction SilentlyContinue) { $ublockInstalled = $true }
    }
    # Fallback: carpeta de extensiones desempaquetadas
    if (-not $ublockInstalled -and (Test-Path $zenProfileRoot)) {
        $dirPattern = Join-Path $zenProfileRoot '*\extensions\uBlock0@raymondhill.net'
        if (Get-Item $dirPattern -ErrorAction SilentlyContinue) { $ublockInstalled = $true }
    }

    [pscustomobject]@{
        Installed       = $installed
        IsDefault       = $isDefault
        Path            = $zenPath
        CurrentDefault  = $currentDefault
        UblockInstalled = $ublockInstalled
    }
}

# Las paginas se abren sin privilegios (Open-EmiUrl, via explorer.exe): un
# navegador abierto desde este proceso de administrador seria administrador.
function Open-EmiHibpPage {
    Open-EmiUrl 'https://haveibeenpwned.com/'
}

function Open-EmiLastPassPage {
    Open-EmiUrl 'https://www.lastpass.com/es'
}

function Open-EmiUblockInstall {
    $z = Get-EmiZenBrowserStatus
    $url = 'https://addons.mozilla.org/firefox/addon/ublock-origin/'
    if ($z.Installed) {
        # zen.exe (normalmente en %LOCALAPPDATA%) nunca se lanza elevado
        try { [void](Start-EmiUnelevated -FilePath $z.Path -Arguments $url); return }
        catch { Write-EmiLog "No se pudo abrir Zen sin privilegios: $($_.Exception.Message)" Warn }
    }
    Open-EmiUrl $url
}

Export-ModuleMember -Function *-Emi*