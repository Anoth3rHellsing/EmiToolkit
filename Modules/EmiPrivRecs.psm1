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

function Open-EmiHibpPage {
    Start-Process 'https://haveibeenpwned.com/'
}

function Open-EmiLastPassPage {
    Start-Process 'https://www.lastpass.com/es'
}

function Open-EmiUblockInstall {
    $z = Get-EmiZenBrowserStatus
    if ($z.Installed) {
        Start-Process $z.Path 'https://addons.mozilla.org/firefox/addon/ublock-origin/'
    } else {
        Start-Process 'https://addons.mozilla.org/firefox/addon/ublock-origin/'
    }
}

Export-ModuleMember -Function *-Emi*