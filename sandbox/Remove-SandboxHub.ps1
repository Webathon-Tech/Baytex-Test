<#
.SYNOPSIS
    Tears down the mock Baytex hub created by Deploy-SandboxHub.ps1.

.DESCRIPTION
    Deletes the sandbox hub resource group and everything in it (hub VNet, NVA
    simulator, on-prem DB simulator, NAT gateway, private DNS zones).

    ORDER MATTERS. Run this LAST:
      1. terraform destroy   in environments/dev   (removes the spoke + peering)
      2. terraform destroy   in bootstrap/dev-state (removes the state backend)
      3. this script                                (removes the mock hub)

    Destroying the hub while the spoke peering still references it, or removing
    the state backend before the platform it tracks, leaves orphans.

.PARAMETER Force
    Skip the confirmation prompt.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$SubscriptionId   = "6a3bb170-5159-4bff-860b-aa74fb762697",
    [string]$HubResourceGroup = "rg-sbx-hub-cnc-001",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Guard: never let this point at a real Baytex subscription.
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$name = & az account show --subscription $SubscriptionId --query name -o tsv 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = $previous
if ($code -ne 0) { throw "Cannot read subscription $SubscriptionId" }
if ($name -like 'SUB-BTE-*') {
    throw "REFUSING TO RUN: '$name' looks like a real Baytex subscription."
}
Write-Host "Target: $name ($SubscriptionId)" -ForegroundColor Yellow

# Warn if the spoke still peers to this hub.
$ErrorActionPreference = 'Continue'
$peerings = & az network vnet peering list --subscription $SubscriptionId `
    -g "rg-sbx-dbx-dev-network-cnc-001" --vnet-name "vnet-sbx-dbx-dev-cnc-001" `
    --query "[].name" -o tsv 2>&1
$peerCode = $LASTEXITCODE
$ErrorActionPreference = $previous
if ($peerCode -eq 0 -and $peerings) {
    Write-Warning "Spoke VNet still has peering(s): $peerings"
    Write-Warning "Run 'terraform destroy' in environments/dev BEFORE this script."
    if (-not $Force) { throw "Aborting. Re-run with -Force to delete anyway." }
}

if ($Force -or $PSCmdlet.ShouldProcess($HubResourceGroup, "Delete resource group and all contents")) {
    Write-Host "Deleting $HubResourceGroup ..." -ForegroundColor Cyan
    & az group delete --name $HubResourceGroup --subscription $SubscriptionId --yes
    if ($LASTEXITCODE -ne 0) { throw "Failed to delete $HubResourceGroup" }
    Write-Host "Mock hub removed." -ForegroundColor Green
}
