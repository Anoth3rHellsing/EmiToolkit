# =====================================================================
#  EmiFirewall.psm1 - Reglas de firewall para ESET (KB332)
#  Fuente: ESET KB332, revision 24-jul-2026
# =====================================================================

$script:FwGroup = 'ESET KB332'

function Get-EmiEsetGroups {
@(
    @{ Name='Update'; Description='Actualizaciones del motor de deteccion, modulos y Pico'; Direction='Outbound'
       Ports=@{ TCP=@('80','443') }
       Hostnames=@('update.eset.com','eu-update.eset.com','us-update.eset.com','pico.eset.com')
       Addresses=@('91.228.166.13','91.228.166.14','91.228.166.15','91.228.166.16','91.228.167.132','91.228.167.133',
                   '91.228.167.170','91.228.167.92','91.228.167.26','91.228.167.21','38.90.226.36','38.90.226.37',
                   '38.90.226.38','38.90.226.39','38.90.226.40','38.90.226.44','185.94.157.10','185.94.157.11',
                   '185.94.157.14','43.154.209.149',
                   '2a05:e800:1001:f00:b13d:71f1:e7c5:5e27','2a05:e800:1001:f00:f76e:548c:f14f:779e',
                   '2a05:e800:1001:f00:8390:1b8a:7f23:1323','2a05:e800:1001:f00:fd92:22a9:7f09:a2cf',
                   '2a05:e800:1003:f00:f837:6670:c755:2549','2a05:e800:1003:f00:85ae:64dd:5a9a:7134',
                   '2a05:e800:1003:f00:d1b1:9b14:34bc:bffc','2a05:e800:1003:f00:eaf6:af3:268d:a2c1',
                   '2a05:e800:1003:f00:1007:8fef:4d49:7f20','2a05:e800:1003:f00:ff1a:68c9:d694:b6c0',
                   '2a05:e800:1007:f00:f89f:41c9:473f:855a','2a05:e800:1007:f00:93ab:650b:a906:5b06',
                   '2a05:e800:1007:f00:9df6:e953:8f27:659c','2a05:e802:1005:f00:7141:7e00:1138:faa5',
                   '2a05:e802:1005:f00:8116:9e87:7a0f:157e','2a05:e802:1005:f00:cfc9:bf14:a574:15e7',
                   '2a05:e802:1005:f00:956f:8fa9:7691:791b','2a05:e802:1005:f00:ea77:854f:2816:bf72',
                   '2a05:e802:1005:f00:1111:106e:b385:d36e') }

    @{ Name='Download'; Description='Descarga de instaladores y actualizaciones'; Direction='Outbound'
       Ports=@{ TCP=@('80','443') }
       Hostnames=@('download.eset.com','download.liveinstaller.eset.systems')
       Addresses=@('91.228.166.154','91.228.167.190','38.90.226.111','20.224.75.204') }

    @{ Name='Activation'; Description='Activacion, caducidad, PKI, versioncheck, iploc y EDF'; Direction='Outbound'
       Ports=@{ TCP=@('80','443'); UDP=@('443') }
       Hostnames=@('edf.eset.com','expire.eset.com','iploc.eset.com','pki.eset.com','versioncheck.eset.com','ecp.eset.systems')
       Addresses=@('138.91.165.201','13.93.203.130','20.224.75.204','4.184.128.167','23.99.12.158','52.160.70.199',
                   '4.184.181.74','91.228.165.79','91.228.167.123','91.228.166.181','91.228.167.181','38.90.227.50',
                   '91.228.165.81','91.228.167.125') }

    @{ Name='Services'; Description='Proxy, trace, IPM, banner y deteccion de certificado SSL'; Direction='Outbound'
       Ports=@{ TCP=@('80','443') }
       Hostnames=@('proxy.eset.com','trace.eset.com','ipm.eset.com','banner.eset.com','proxy-detection.eset.com','redirector.eset.systems')
       Addresses=@('138.91.165.201','13.93.203.130','20.224.75.204','4.184.128.167','91.228.165.79','91.228.167.123',
                   '91.228.167.30','38.90.226.28','91.228.166.91','91.228.167.91') }

    @{ Name='LiveGrid'; Description='ESET LiveGrid: TCP 80 y TCP/UDP 53535'; Direction='Outbound'
       Ports=@{ TCP=@('80','53535'); UDP=@('53535') }
       Hostnames=@('livegrid.eset.systems','a.livegrid.eset.systems','i1.livegrid.eset.systems','i3.livegrid.eset.systems',
                   'i4.livegrid.eset.systems','i5.livegrid.eset.systems','u.eset.com','c.eset.com','a.c.eset.com',
                   'i1.c.eset.com','i3.c.eset.com','i4.c.eset.com','i5.c.eset.com','avcloud.e5.sk','dnsj.e5.sk')
       Addresses=@('91.228.166.45','91.228.166.46','91.228.166.52','91.228.165.43','91.228.165.44','91.228.165.12',
                   '91.228.165.40','91.228.167.137','91.228.167.43','91.228.167.46','91.228.167.103','91.228.167.104',
                   '91.228.167.105','91.228.167.106','38.90.226.11','38.90.226.12','38.90.226.13','38.90.226.46','38.90.226.47') }

    @{ Name='AdvancedML'; Description='Aprendizaje automatico avanzado (Augur)'; Direction='Outbound'
       Ports=@{ TCP=@('80','443') }
       Hostnames=@('augur.scanners.eset.systems')
       Addresses=@('91.228.166.137','91.228.167.184','38.90.226.41') }

    @{ Name='ThreatLab'; Description='Muestras y estadisticas anonimas al laboratorio'; Direction='Outbound'
       Ports=@{ TCP=@('80','443') }
       Hostnames=@('edtd-ts.eset.com')
       Addresses=@('91.228.166.11','91.228.166.148','91.228.166.149','91.228.166.150','91.228.166.152','91.228.166.95',
                   '91.228.166.96','91.228.166.74','91.228.167.144','91.228.167.145','91.228.167.146','91.228.167.151',
                   '91.228.167.155','91.228.167.70','91.228.167.71','91.228.167.83','91.228.167.32') }

    @{ Name='WebControl'; Description='Control web / parental (ARSP)'; Direction='Outbound'
       Ports=@{ TCP=@('53','53535'); UDP=@('53','53535') }
       Hostnames=@()
       Addresses=@('91.228.166.42','91.228.166.43','91.228.167.141','91.228.167.142','38.90.226.14','38.90.226.15') }

    @{ Name='Antispam'; Description='Modulo Antispam (ARS / Tesla)'; Direction='Outbound'
       Ports=@{ TCP=@('53535'); UDP=@('53535') }
       Hostnames=@('dns.e5.sk','salt.e5.sk','rsys.e5.sk','arb.e5.sk','asplog.e5.sk','mri.e5.sk','ipt.e5.sk',
                   'sample.e5.sk','stat.e5.sk','setting.e5.sk','gid.e5.sk')
       Addresses=@('91.228.166.61','91.228.166.62','91.228.166.63','91.228.166.64','91.228.166.65','91.228.166.119',
                   '91.228.166.110','91.228.165.57','91.228.165.59','91.228.167.36','91.228.167.67','91.228.167.68',
                   '91.228.167.74','91.228.167.116','91.228.167.136','91.228.167.57','91.228.167.56','91.228.167.169',
                   '91.228.167.63','38.90.226.21','38.90.226.22','38.90.226.23','38.90.226.24','38.90.226.25',
                   '38.90.226.19','38.90.226.31') }

    @{ Name='PasswordManager'; Description='ESET Password Manager'; Direction='Outbound'
       Ports=@{ TCP=@('443') }
       Hostnames=@('eset-prod-ca48648d0ce7cadf.elb.eu-central-1.amazonaws.com')
       Addresses=@('18.159.98.220') }

    @{ Name='DataFramework'; Description='ESET Data Framework / Antirrobo (ARSE)'; Direction='Outbound'
       Ports=@{ TCP=@('53','80','443','53535'); UDP=@('53','80','443','53535') }
       Hostnames=@('edf.eset.com','ecp.eset.systems')
       Addresses=@('91.228.166.104','91.228.166.71','91.228.167.64','91.228.167.81','91.228.165.74','91.228.167.40',
                   '38.90.226.16','38.90.226.17','38.90.226.42','38.90.226.34','23.99.12.158','52.160.70.199',
                   '4.184.181.74','138.91.165.201','13.93.203.130','4.184.128.167') }

    @{ Name='Gui'; Description='Enlaces y redireccion de la ventana principal'; Direction='Outbound'
       Ports=@{ TCP=@('80','443') }
       Hostnames=@('go.eset.com','go.eset.eu','support-go.eset.eu')
       Addresses=@('52.166.8.11','91.228.166.47','91.228.167.128','91.228.166.78','91.228.167.98') }

    @{ Name='Support'; Description='Solicitudes de asistencia, ayuda y base de conocimiento'; Direction='Outbound'
       Ports=@{ TCP=@('80','443') }
       Hostnames=@('suppreq.eset.eu','help.eset.com','support.eset.com','int.form.eset.com')
       Addresses=@('91.228.165.114','91.228.167.111','91.228.165.46','91.228.167.61','38.90.227.28',
                   '34.198.154.246','52.4.210.140','91.228.166.22','91.228.166.154') }

    @{ Name='TwoFactor'; Description='ESET Secure Authentication (2FA)'; Direction='Outbound'
       Ports=@{ TCP=@('443') }
       Hostnames=@('esa.eset.com','m.esa.eset.com','ecp.eset.systems')
       Addresses=@('138.91.165.201','13.93.203.130','4.184.128.167','91.228.167.115','91.228.167.120','91.228.167.122',
                   '91.228.167.152','91.228.165.162','91.228.165.163','91.228.165.164','91.228.165.166') }

    @{ Name='DnsLoadBalancers'; Description='Balanceadores DNS de ESET (F5)'; Direction='Outbound'
       Ports=@{ TCP=@('53','53535'); UDP=@('53','53535') }
       Hostnames=@()
       Addresses=@('91.228.165.117','91.228.167.16','38.90.226.53','91.228.165.72','91.228.167.185','38.90.226.59') }

    @{ Name='Telemetry'; Description='Telemetria de ESET (gallup)'; Direction='Outbound'
       Ports=@{ TCP=@('443') }; Hostnames=@('gallup.eset.com'); Addresses=@() }

    @{ Name='Ocsp'; Description='Revocacion de certificados (OCSP) por HTTP'; Direction='Outbound'
       Ports=@{ TCP=@('80') }; Hostnames=@()
       Addresses=@('93.184.220.29','72.21.91.29','192.16.58.8','117.18.237.29','66.225.197.197') }

    @{ Name='Repository'; Description='Repositorio de ESET (despliegue y Micro PCU)'; Direction='Outbound'
       Ports=@{ TCP=@('80','443') }
       Hostnames=@('repository.eset.com','repositorynocdn.eset.com','us-repository.eset.com')
       Addresses=@('38.90.226.20','91.228.166.19','91.228.166.23','91.228.167.25','161.189.152.208') }

    @{ Name='Protect'; Description='ESET PROTECT (consola, agente, XDR, notificaciones)'; Direction='Outbound'
       Ports=@{ TCP=@('443') }
       Hostnames=@('protect.eset.com','protecthub.eset.com','identity.eset.com','eba.eset.com','msp.eset.com',
                   'eu02.protect.eset.com','us02.protect.eset.com','jp02.protect.eset.com','ca01.protect.eset.com',
                   'de01.protect.eset.com','eu.download.protect.eset.com','us.download.protect.eset.com',
                   'de.download.protect.eset.com','jp.download.protect.eset.com','ca.download.protect.eset.com',
                   'redirector.eset.systems')
       Addresses=@('20.82.100.209','20.245.38.118','20.194.197.189','4.172.129.94','98.67.237.69','63.178.104.239',
                   '63.178.158.139','63.178.49.118','63.179.32.177','3.75.145.97','3.78.191.228','35.75.92.47',
                   '175.41.232.243','13.159.32.201','35.167.194.40','44.230.146.78','16.145.39.107','16.52.231.96',
                   '16.52.195.67','16.52.231.57','13.69.61.76','20.31.123.179','23.99.91.144','159.60.151.106',
                   '20.46.163.70','52.140.234.249','4.172.67.88','20.175.250.3','4.182.183.59','4.182.168.113',
                   '20.170.86.116','91.228.165.2','91.228.167.118') }

    @{ Name='ProtectUpload'; Description='Subida de archivos de ESET PROTECT (TCP 444)'; Direction='Outbound'
       Ports=@{ TCP=@('444') }
       Hostnames=@('epx-k8s-prod-eu-a.westeurope.cloudapp.azure.com','epx-k8s-prod-us-a.westus.cloudapp.azure.com',
                   'epx-k8s-prod-de-a.germanywestcentral.cloudapp.azure.com','epx-k8s-prod-jp-a.japaneast.cloudapp.azure.com',
                   'epx-k8s-prod-ca-a.canadacentral.cloudapp.azure.com')
       Addresses=@('20.13.64.213','20.253.203.21','20.191.183.169','4.172.24.110','4.182.194.64') }

    @{ Name='Epns'; Description='ESET Push Notification Service (TCP 8883 y 443)'; Direction='Outbound'
       Ports=@{ TCP=@('443','8883') }
       Hostnames=@('epns.eset.com')
       Addresses=@('91.228.165.144','91.228.165.145','91.228.165.146','91.228.165.147','91.228.165.148','91.228.165.159',
                   '91.228.165.160','91.228.167.171','91.228.167.172','91.228.167.187','91.228.167.188','91.228.167.192',
                   '91.228.167.193','91.228.167.194','38.90.226.51','38.90.226.52','38.90.226.62','38.90.226.63',
                   '38.90.226.64','38.90.226.65','38.90.226.66') }

    @{ Name='Inspect'; Description='ESET Inspect (EDR): 443 y 8093'; Direction='Outbound'
       Ports=@{ TCP=@('443','8093') }
       Hostnames=@('inspect.eset.com','eu01.inspect.eset.com','us01.inspect.eset.com','jp01.inspect.eset.com',
                   'ca01.inspect.eset.com','de01.inspect.eset.com','eu01.agent.edr.eset.systems',
                   'us01.agent.edr.eset.systems','jp01.agent.edr.eset.systems','ca01.agent.edr.eset.systems',
                   'de01.agent.edr.eset.systems')
       Addresses=@('52.166.186.239','40.83.252.19','20.188.24.252','52.233.40.229','20.113.169.211') }

    @{ Name='LiveGuard'; Description='ESET LiveGuard Advanced (sandbox)'; Direction='Outbound'
       Ports=@{ TCP=@('443') }
       Hostnames=@('r.edtd.eset.com','d.edtd.eset.com')
       Addresses=@('137.117.138.135','13.83.244.211','20.31.87.92','20.43.231.148') }

    @{ Name='Mdm'; Description='Cloud MDM de ESET PROTECT'; Direction='Outbound'
       Ports=@{ TCP=@('443') }
       Hostnames=@('mdm.eset.com','eu.mdm.eset.com','us.mdm.eset.com','jp.mdm.eset.com','ca.mdm.eset.com','de.mdm.eset.com',
                   'checkin.eu.mdm.eset.com','checkin.us.mdm.eset.com','checkin.jp.mdm.eset.com','checkin.ca.mdm.eset.com',
                   'checkin.de.mdm.eset.com','mdmcomm.eu.mdm.eset.com','mdmcomm.us.mdm.eset.com','mdmcomm.jp.mdm.eset.com',
                   'mdmcomm.ca.mdm.eset.com','mdmcomm.de.mdm.eset.com')
       Addresses=@() }

    @{ Name='Msp'; Description='ESET MSP Utility (EMU)'; Direction='Outbound'
       Ports=@{ TCP=@('80','443') }
       Hostnames=@('ftp.eset.sk','mspapi.esetsoftware.com')
       Addresses=@('91.228.166.130','168.62.212.42') }

    @{ Name='Bridge'; Description='ESET Bridge: OAuth2 para notificaciones por correo'; Direction='Outbound'
       Ports=@{ TCP=@('443') }; Hostnames=@('login.microsoftonline.com'); Addresses=@() }

    @{ Name='ProtectDeployment'; Description='OPCIONAL: Remote Deployment Tool (SMB en la LAN)'; Direction='Outbound'; Optional=$true
       Ports=@{ TCP=@('139','445'); UDP=@('137','138') }; Hostnames=@(); Addresses=@('LocalSubnet') }

    @{ Name='SyslogInbound'; Description='OPCIONAL: entrada Syslog TLS desde ESET PROTECT (6514)'; Direction='Inbound'; Optional=$true
       Ports=@{ TCP=@('6514') }; Hostnames=@()
       Addresses=@('51.136.106.164','51.136.106.165','51.136.106.166','51.136.106.167','20.16.120.5',
                   '40.81.8.148','40.81.8.149','40.81.8.150','40.81.8.151','40.86.163.190',
                   '20.78.10.184','20.78.10.185','20.78.10.186','20.78.10.187','48.210.54.247',
                   '20.48.241.160','20.48.241.161','20.48.241.162','20.48.241.163','52.138.52.138',
                   '20.170.86.116','4.184.232.133') }
)
}

function Get-EmiEsetItems {
    <#  Convierte el catalogo en EmiItem para la lista de la UI. #>
    $items = New-Object System.Collections.ArrayList
    foreach ($g in Get-EmiEsetGroups) {
        $ports = ($g.Ports.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value -join ',')" }) -join '  |  '
        $opt   = ($g.ContainsKey('Optional') -and $g.Optional)

        $it = New-Object EmiItem
        $it.Name        = $g.Name
        $it.Detail      = $g.Description
        $it.Path        = $ports
        $it.Tag         = $g.Name
        $it.Category    = $g.Direction
        $it.SizeText    = "$($g.Addresses.Count) IP / $($g.Hostnames.Count) host"
        $it.Recommended = -not $opt
        $it.Selected    = -not $opt
        $it.Status      = if ($opt) { 'opcional' } else { '' }
        [void]$items.Add($it)
    }
    return $items
}

function Resolve-EmiHostnames {
    param([string[]] $Hostnames)
    $ips = New-Object System.Collections.ArrayList
    foreach ($h in $Hostnames) {
        try {
            Resolve-DnsName -Name $h -ErrorAction Stop |
                Where-Object { $_.PSObject.Properties.Name -contains 'IPAddress' -and $_.IPAddress } |
                ForEach-Object { [void]$ips.Add($_.IPAddress) }
        } catch { }
    }
    return $ips.ToArray()
}

function Invoke-EmiEsetFirewall {
    <#  Crea/actualiza las reglas del firewall para los grupos indicados. #>
    param(
        [string[]] $Groups,
        [switch]   $ResolveHostnames,
        [string[]] $FirewallProfile = @('Any')
    )

    if (-not (Test-EmiAdmin)) { Write-EmiLog 'Se requieren permisos de administrador.' Error; return 0 }

    $all = Get-EmiEsetGroups
    if (-not $Groups -or $Groups.Count -eq 0) {
        $sel = $all | Where-Object { -not ($_.ContainsKey('Optional') -and $_.Optional) }
    } else {
        $sel = $all | Where-Object { $Groups -contains $_.Name }
    }

    Write-EmiLog "Aplicando reglas ESET KB332 para $($sel.Count) grupos..." Step
    $count = 0
    $i = 0

    foreach ($g in $sel) {
        $i++
        Set-EmiStatus "ESET: $($g.Name)" ([int](($i / [math]::Max(1, $sel.Count)) * 100))

        $addr = @($g.Addresses)
        if ($ResolveHostnames -and $g.Hostnames.Count -gt 0) {
            $r = @(Resolve-EmiHostnames -Hostnames $g.Hostnames)
            if ($r.Count -gt 0) { $addr += $r }
        }
        $addr = @($addr | Sort-Object -Unique)

        if ($addr.Count -eq 0) {
            Write-EmiLog "Grupo '$($g.Name)' omitido: sin direcciones (activa 'resolver DNS')." Warn
            continue
        }

        foreach ($proto in @($g.Ports.Keys)) {
            $ports = $g.Ports[$proto]
            $name  = "ESET KB332 - $($g.Name) ($proto $($ports -join ','))"

            $p = @{
                DisplayName = $name; Description = $g.Description; Direction = $g.Direction
                Action = 'Allow'; Enabled = 'True'; Profile = ($FirewallProfile -join ',')
                Protocol = $proto; RemoteAddress = $addr; Group = $script:FwGroup
            }
            if ($g.Direction -eq 'Outbound') { $p['RemotePort'] = $ports } else { $p['LocalPort'] = $ports }

            try {
                $existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
                if ($existing) {
                    $u = @{}
                    foreach ($k in $p.Keys) { $u[$k] = $p[$k] }
                    $u.Remove('Group') | Out-Null
                    $u.Remove('DisplayName') | Out-Null
                    Set-NetFirewallRule -DisplayName $name @u -ErrorAction Stop | Out-Null
                } else {
                    New-NetFirewallRule @p -ErrorAction Stop | Out-Null
                    Add-EmiJournalEntry @{ Kind='Firewall'; RuleName=$name; Module='ESET' }
                }
                $count++
            }
            catch { Write-EmiLog "Regla '$name': $($_.Exception.Message)" Warn }
        }
        Write-EmiLog "$($g.Name): $($addr.Count) direcciones permitidas." Ok
    }

    Write-EmiLog "Firewall ESET listo: $count reglas procesadas." Ok
    Set-EmiStatus 'Firewall de ESET configurado' 100
    return $count
}

function Remove-EmiEsetFirewall {
    $rules = @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue)
    if ($rules.Count -eq 0) { Write-EmiLog 'No hay reglas ESET que eliminar.' Warn; return 0 }
    foreach ($r in $rules) { Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue }
    Write-EmiLog "$($rules.Count) reglas de ESET eliminadas." Ok
    return $rules.Count
}

function Get-EmiEsetRuleCount {
    @(Get-NetFirewallRule -Group $script:FwGroup -ErrorAction SilentlyContinue).Count
}

function Test-EmiEsetConnectivity {
    $targets = @(
        @{ T='update.eset.com';     P=80   ; W='Actualizacion de modulos' }
        @{ T='edf.eset.com';        P=443  ; W='Activacion / EDF' }
        @{ T='iploc.eset.com';      P=443  ; W='Localizacion IP' }
        @{ T='pki.eset.com';        P=80   ; W='PKI' }
        @{ T='u.eset.com';          P=53535; W='LiveGrid' }
        @{ T='download.eset.com';   P=443  ; W='Descargas' }
        @{ T='repository.eset.com'; P=80   ; W='Repositorio' }
        @{ T='epns.eset.com';       P=8883 ; W='EPNS' }
    )

    $items = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($t in $targets) {
        $i++
        Set-EmiStatus "Probando $($t.T):$($t.P)" ([int](($i / $targets.Count) * 100))
        $ok = $false
        try { $ok = [bool](Test-NetConnection -ComputerName $t.T -Port $t.P -InformationLevel Quiet -WarningAction SilentlyContinue) } catch { }

        $it = New-Object EmiItem
        $it.Name     = $t.T
        $it.Detail   = $t.W
        $it.Path     = "puerto $($t.P)"
        $it.Status   = if ($ok) { 'OK' } else { 'BLOQUEADO' }
        $it.Category = if ($ok) { 'ok' } else { 'fail' }
        [void]$items.Add($it)

        Write-EmiLog ("{0,-24} :{1,-6} {2}" -f $t.T, $t.P, $it.Status) $(if ($ok) { 'Ok' } else { 'Warn' })
    }
    Set-EmiStatus 'Prueba terminada' 100
    return $items
}

Export-ModuleMember -Function *-Emi*
