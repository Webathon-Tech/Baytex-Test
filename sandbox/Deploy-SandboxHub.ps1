<#
.SYNOPSIS
    Builds a mock "Baytex hub" inside a personal sandbox subscription.

.DESCRIPTION
    The real Baytex deployment consumes an EXISTING hub VNet, an EXISTING Cisco
    Firepower NVA and EXISTING on-premises database servers. None of that exists
    in a personal subscription, so this script stands up throwaway equivalents:

        vnet-sbx-hub-cnc-001            10.98.0.0/16
          snet-sbx-fw-cnc-001           10.98.0.0/24   -> NVA sim   10.98.0.4
          snet-sbx-onprem-cnc-001       10.98.1.0/24   -> DB sim    10.98.1.4
        private DNS zone sandbox.internal
          sqlsim.sandbox.internal  -> 10.98.1.4  (TCP 1433)
          orasim.sandbox.internal  -> 10.98.1.4  (TCP 1521)

    This is REHEARSAL SCAFFOLDING ONLY. It is never deployed for Baytex and the
    sandbox/ folder is gitignored so it cannot reach the client repository.

.NOTES
    Idempotent enough to re-run: existing resources are left alone.
    Tear down with Remove-SandboxHub.ps1 (or delete the resource group).
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId = "6a3bb170-5159-4bff-860b-aa74fb762697",
    [string]$Location       = "canadacentral",
    [string]$HubResourceGroup = "rg-sbx-hub-cnc-001",
    [string]$SshPublicKeyPath = "$env:USERPROFILE\.ssh\baytex-sandbox-haproxy-ed25519.pub",
    [string]$VmSize         = "Standard_B1s"
)

$ErrorActionPreference = 'Stop'

# --- constants -------------------------------------------------------------
$HubVnet        = "vnet-sbx-hub-cnc-001"
$HubVnetCidr    = "10.98.0.0/16"
$FwSubnet       = "snet-sbx-fw-cnc-001"
$FwSubnetCidr   = "10.98.0.0/24"
$FwIp           = "10.98.0.4"
$OnPremSubnet   = "snet-sbx-onprem-cnc-001"
$OnPremCidr     = "10.98.1.0/24"
$OnPremIp       = "10.98.1.4"
$DnsZone        = "sandbox.internal"
$NatPip         = "pip-sbx-hub-nat-cnc-001"
$NatGw          = "natgw-sbx-hub-cnc-001"
$Image          = "Canonical:ubuntu-24_04-lts:server:latest"
$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path

# Windows PowerShell 5.1 turns any stderr output from a native exe into an
# ErrorRecord, which terminates under $ErrorActionPreference='Stop' before the
# real exit code can be inspected. Both helpers drop to 'Continue' around the
# az call and branch on $LASTEXITCODE instead.
function Invoke-Az {
    param([string[]]$Arguments, [string]$What)
    Write-Host "  az $($Arguments -join ' ')" -ForegroundColor DarkGray
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & az @Arguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) {
        Write-Host ($output | Out-String) -ForegroundColor Red
        throw "FAILED: $What"
    }
    return $output
}

function Test-AzResource {
    param([string[]]$ShowArguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $null = & az @ShowArguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    return ($code -eq 0)
}

if (-not (Test-Path $SshPublicKeyPath)) {
    throw "SSH public key not found at $SshPublicKeyPath"
}

Write-Host "`n=== Guard: confirm target subscription ===" -ForegroundColor Cyan
$current = az account show --query id -o tsv 2>$null
if ($current -ne $SubscriptionId) {
    Write-Host "Switching active subscription to $SubscriptionId" -ForegroundColor Yellow
    Invoke-Az @('account','set','--subscription',$SubscriptionId) 'set subscription' | Out-Null
}
$name = az account show --query name -o tsv
Write-Host "Target: $name ($SubscriptionId)" -ForegroundColor Green
if ($name -like 'SUB-BTE-*') {
    throw "REFUSING TO RUN: '$name' looks like a real Baytex subscription."
}

Write-Host "`n=== 1/8 Resource group ===" -ForegroundColor Cyan
Invoke-Az @('group','create','--name',$HubResourceGroup,'--location',$Location,
    '--subscription',$SubscriptionId,'--tags','Purpose=SandboxRehearsal','ManagedBy=Manual',
    '--output','none') 'create hub resource group' | Out-Null

Write-Host "`n=== 2/8 Hub VNet + subnets ===" -ForegroundColor Cyan
if (Test-AzResource @('network','vnet','show','-g',$HubResourceGroup,'-n',$HubVnet,'--subscription',$SubscriptionId)) {
    Write-Host "  VNet already exists, skipping" -ForegroundColor DarkYellow
} else {
    Invoke-Az @('network','vnet','create','-g',$HubResourceGroup,'-n',$HubVnet,
        '--address-prefixes',$HubVnetCidr,'--subnet-name',$FwSubnet,'--subnet-prefixes',$FwSubnetCidr,
        '--location',$Location,'--subscription',$SubscriptionId,'--output','none') 'create hub vnet' | Out-Null
}
if (-not (Test-AzResource @('network','vnet','subnet','show','-g',$HubResourceGroup,'--vnet-name',$HubVnet,'-n',$OnPremSubnet,'--subscription',$SubscriptionId))) {
    Invoke-Az @('network','vnet','subnet','create','-g',$HubResourceGroup,'--vnet-name',$HubVnet,
        '-n',$OnPremSubnet,'--address-prefixes',$OnPremCidr,'--subscription',$SubscriptionId,
        '--output','none') 'create on-prem subnet' | Out-Null
}

Write-Host "`n=== 3/8 NAT gateway (guest agent + extension egress) ===" -ForegroundColor Cyan
if (-not (Test-AzResource @('network','public-ip','show','-g',$HubResourceGroup,'-n',$NatPip,'--subscription',$SubscriptionId))) {
    Invoke-Az @('network','public-ip','create','-g',$HubResourceGroup,'-n',$NatPip,'--sku','Standard',
        '--location',$Location,'--subscription',$SubscriptionId,'--output','none') 'create nat pip' | Out-Null
}
if (-not (Test-AzResource @('network','nat','gateway','show','-g',$HubResourceGroup,'-n',$NatGw,'--subscription',$SubscriptionId))) {
    Invoke-Az @('network','nat','gateway','create','-g',$HubResourceGroup,'-n',$NatGw,
        '--public-ip-addresses',$NatPip,'--location',$Location,'--subscription',$SubscriptionId,
        '--output','none') 'create nat gateway' | Out-Null
}
foreach ($sn in @($FwSubnet, $OnPremSubnet)) {
    Invoke-Az @('network','vnet','subnet','update','-g',$HubResourceGroup,'--vnet-name',$HubVnet,
        '-n',$sn,'--nat-gateway',$NatGw,'--subscription',$SubscriptionId,'--output','none') "attach nat gw to $sn" | Out-Null
}

Write-Host "`n=== 4/8 NVA simulator NIC (IP forwarding ON) ===" -ForegroundColor Cyan
if (-not (Test-AzResource @('network','nic','show','-g',$HubResourceGroup,'-n','nic-sbx-hub-fwsim-01','--subscription',$SubscriptionId))) {
    Invoke-Az @('network','nic','create','-g',$HubResourceGroup,'-n','nic-sbx-hub-fwsim-01',
        '--vnet-name',$HubVnet,'--subnet',$FwSubnet,'--private-ip-address',$FwIp,
        '--ip-forwarding','true','--location',$Location,'--subscription',$SubscriptionId,
        '--output','none') 'create nva nic' | Out-Null
}

Write-Host "`n=== 5/8 NVA simulator VM ===" -ForegroundColor Cyan
if (Test-AzResource @('vm','show','-g',$HubResourceGroup,'-n','vm-sbx-hub-fwsim-01','--subscription',$SubscriptionId)) {
    Write-Host "  VM already exists, skipping" -ForegroundColor DarkYellow
} else {
    Invoke-Az @('vm','create','-g',$HubResourceGroup,'-n','vm-sbx-hub-fwsim-01',
        '--image',$Image,'--size',$VmSize,'--admin-username','azureadmin',
        '--ssh-key-values',$SshPublicKeyPath,'--nics','nic-sbx-hub-fwsim-01',
        '--custom-data',(Join-Path $ScriptDir 'cloud-init-nva.yaml'),
        '--os-disk-delete-option','Delete','--nic-delete-option','Delete',
        '--location',$Location,'--subscription',$SubscriptionId,'--output','none') 'create nva vm' | Out-Null
}

Write-Host "`n=== 6/8 On-prem DB simulator NIC + VM ===" -ForegroundColor Cyan
if (-not (Test-AzResource @('network','nic','show','-g',$HubResourceGroup,'-n','nic-sbx-hub-dbsim-01','--subscription',$SubscriptionId))) {
    Invoke-Az @('network','nic','create','-g',$HubResourceGroup,'-n','nic-sbx-hub-dbsim-01',
        '--vnet-name',$HubVnet,'--subnet',$OnPremSubnet,'--private-ip-address',$OnPremIp,
        '--location',$Location,'--subscription',$SubscriptionId,'--output','none') 'create db nic' | Out-Null
}
if (Test-AzResource @('vm','show','-g',$HubResourceGroup,'-n','vm-sbx-hub-dbsim-01','--subscription',$SubscriptionId)) {
    Write-Host "  VM already exists, skipping" -ForegroundColor DarkYellow
} else {
    Invoke-Az @('vm','create','-g',$HubResourceGroup,'-n','vm-sbx-hub-dbsim-01',
        '--image',$Image,'--size',$VmSize,'--admin-username','azureadmin',
        '--ssh-key-values',$SshPublicKeyPath,'--nics','nic-sbx-hub-dbsim-01',
        '--custom-data',(Join-Path $ScriptDir 'cloud-init-onprem.yaml'),
        '--os-disk-delete-option','Delete','--nic-delete-option','Delete',
        '--location',$Location,'--subscription',$SubscriptionId,'--output','none') 'create db vm' | Out-Null
}

Write-Host "`n=== 7/8 Private DNS zone ===" -ForegroundColor Cyan
if (-not (Test-AzResource @('network','private-dns','zone','show','-g',$HubResourceGroup,'-n',$DnsZone,'--subscription',$SubscriptionId))) {
    Invoke-Az @('network','private-dns','zone','create','-g',$HubResourceGroup,'-n',$DnsZone,
        '--subscription',$SubscriptionId,'--output','none') 'create dns zone' | Out-Null
}
if (-not (Test-AzResource @('network','private-dns','link','vnet','show','-g',$HubResourceGroup,'-n','link-hub','-z',$DnsZone,'--subscription',$SubscriptionId))) {
    Invoke-Az @('network','private-dns','link','vnet','create','-g',$HubResourceGroup,'-n','link-hub',
        '-z',$DnsZone,'-v',$HubVnet,'-e','false','--subscription',$SubscriptionId,'--output','none') 'link zone to hub' | Out-Null
}
foreach ($record in @('sqlsim','orasim')) {
    if (-not (Test-AzResource @('network','private-dns','record-set','a','show','-g',$HubResourceGroup,'-z',$DnsZone,'-n',$record,'--subscription',$SubscriptionId))) {
        Invoke-Az @('network','private-dns','record-set','a','add-record','-g',$HubResourceGroup,
            '-z',$DnsZone,'-n',$record,'-a',$OnPremIp,'--subscription',$SubscriptionId,
            '--output','none') "add A record $record" | Out-Null
    }
}

Write-Host "`n=== 7b/8 Storage privatelink DNS zones ===" -ForegroundColor Cyan
# Baytex has central privatelink zones already. Creating equivalents here means
# the platform's blob_private_dns_zone_ids / dfs_private_dns_zone_ids inputs and
# the private_dns_zone_group dynamic block get exercised instead of skipped.
foreach ($zone in @('privatelink.blob.core.windows.net','privatelink.dfs.core.windows.net')) {
    if (-not (Test-AzResource @('network','private-dns','zone','show','-g',$HubResourceGroup,'-n',$zone,'--subscription',$SubscriptionId))) {
        Invoke-Az @('network','private-dns','zone','create','-g',$HubResourceGroup,'-n',$zone,
            '--subscription',$SubscriptionId,'--output','none') "create $zone" | Out-Null
    }
}

Write-Host "`n=== 8/8 Summary ===" -ForegroundColor Cyan
$blobZoneId = az network private-dns zone show -g $HubResourceGroup -n 'privatelink.blob.core.windows.net' --subscription $SubscriptionId --query id -o tsv
$dfsZoneId  = az network private-dns zone show -g $HubResourceGroup -n 'privatelink.dfs.core.windows.net' --subscription $SubscriptionId --query id -o tsv
$hubVnetId = az network vnet show -g $HubResourceGroup -n $HubVnet --subscription $SubscriptionId --query id -o tsv
Write-Host ""
Write-Host "Mock hub ready. Put these into environments/dev/terraform.tfvars:" -ForegroundColor Green
Write-Host ""
Write-Host "hub_subscription_id       = `"$SubscriptionId`""
Write-Host "hub_resource_group_name   = `"$HubResourceGroup`""
Write-Host "hub_vnet_name             = `"$HubVnet`""
Write-Host "hub_vnet_id               = `"$hubVnetId`""
Write-Host "cisco_firewall_private_ip = `"$FwIp`""
Write-Host ""
Write-Host "blob_private_dns_zone_ids = [`"$blobZoneId`"]"
Write-Host "dfs_private_dns_zone_ids  = [`"$dfsZoneId`"]"
Write-Host ""
Write-Host "Simulated on-prem targets: sqlsim.$DnsZone`:1433  orasim.$DnsZone`:1521 -> $OnPremIp"
Write-Host ""
Write-Host "NEXT: after 'terraform apply' creates the spoke VNet, run" -ForegroundColor Yellow
Write-Host "      Link-SandboxDnsToSpoke.ps1 to link all three zones to it." -ForegroundColor Yellow
Write-Host ""
