<#
.SYNOPSIS
    Links the sandbox private DNS zones to the Terraform-created spoke VNet.

.DESCRIPTION
    Run this AFTER 'terraform apply' has created the spoke VNet. In the real
    Baytex build this step is the Baytex-owned DNS handoff described in
    docs/firewall-and-dns-handoff.md -- the platform Terraform deliberately
    does not own central DNS.

    Links three zones to the spoke so the HAProxy VMs and Databricks compute
    can resolve:
      sandbox.internal                    -> simulated on-prem hosts
      privatelink.blob.core.windows.net   -> storage private endpoint
      privatelink.dfs.core.windows.net    -> storage private endpoint
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId   = "6a3bb170-5159-4bff-860b-aa74fb762697",
    [string]$HubResourceGroup = "rg-sbx-hub-cnc-001",
    [string]$SpokeVnetName    = "vnet-sbx-dbx-dev-cnc-001",
    [string]$SpokeResourceGroup = "rg-sbx-dbx-dev-network-cnc-001"
)

$ErrorActionPreference = 'Stop'

function Invoke-Az {
    param([string[]]$Arguments, [string]$What)
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

$spokeVnetId = az network vnet show -g $SpokeResourceGroup -n $SpokeVnetName --subscription $SubscriptionId --query id -o tsv
if (-not $spokeVnetId) {
    throw "Spoke VNet $SpokeVnetName not found in $SpokeResourceGroup. Run 'terraform apply' first."
}
Write-Host "Spoke VNet: $spokeVnetId" -ForegroundColor Green

$zones = @(
    'sandbox.internal',
    'privatelink.blob.core.windows.net',
    'privatelink.dfs.core.windows.net'
)

foreach ($zone in $zones) {
    $linkName = 'link-spoke'
    if (Test-AzResource @('network','private-dns','link','vnet','show','-g',$HubResourceGroup,'-n',$linkName,'-z',$zone,'--subscription',$SubscriptionId)) {
        Write-Host "  $zone already linked to spoke, skipping" -ForegroundColor DarkYellow
        continue
    }
    Write-Host "  Linking $zone -> $SpokeVnetName" -ForegroundColor Cyan
    Invoke-Az @('network','private-dns','link','vnet','create','-g',$HubResourceGroup,'-n',$linkName,
        '-z',$zone,'-v',$spokeVnetId,'-e','false','--subscription',$SubscriptionId,'--output','none') "link $zone" | Out-Null
}

Write-Host "`nAll sandbox DNS zones linked to the spoke VNet." -ForegroundColor Green
