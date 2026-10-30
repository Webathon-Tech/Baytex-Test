#Requires -Version 7.2

<#
.SYNOPSIS
    Exports the Terraform outputs Baytex Infrastructure and Baytex BI need for an environment's handoffs.

.DESCRIPTION
    Reads the outputs of an environment root and writes the handoff values to <env>-platform-handoff.json in the output
    directory: the workspace, the NCC and its private endpoint rules, the data storage account and Access Connector, the
    peering IDs, and the firewall and Unity Catalog handoff outputs. When Terraform does not create the hub-side peering,
    the Azure CLI command for it is written to hub-side-peering-command.ps1 as well.

    The root must already be initialised against its state backend, as described in docs/local-runs.md. The output
    directory, handoff/ by default, is gitignored.

.PARAMETER EnvironmentPath
    Path to the environment root, for example ./environments/prod. Its folder name names the output file.

.PARAMETER OutputDirectory
    Directory the handoff files are written to. It is created when it does not exist.

.EXAMPLE
    ./scripts/Export-BaytexDevHandoff.ps1 -EnvironmentPath ./environments/prod -OutputDirectory ./handoff
#>

[CmdletBinding()]
param(
    [string]$EnvironmentPath = "../environments/dev",
    [string]$OutputDirectory = "./handoff"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    throw 'Terraform CLI is required.'
}

$resolvedEnvironment = (Resolve-Path $EnvironmentPath).Path
$environmentName = Split-Path $resolvedEnvironment -Leaf
New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null

Push-Location $resolvedEnvironment
try {
    $outputs = terraform output -json | ConvertFrom-Json -AsHashtable
}
finally {
    Pop-Location
}

$selected = [ordered]@{
    GeneratedAt        = (Get-Date).ToUniversalTime().ToString('o')
    WorkspaceArmId     = $outputs.databricks_workspace_arm_id.value
    WorkspaceId        = $outputs.databricks_workspace_id.value
    WorkspaceUrl       = $outputs.databricks_workspace_url.value
    NccId              = $outputs.ncc_id.value
    NccRules           = $outputs.ncc_private_endpoint_rules.value
    StorageAccountId   = $outputs.data_storage_account_id.value
    StorageAccountName = $outputs.data_storage_account_name.value
    DataAccessConnectorId = $outputs.data_access_connector_id.value
    ContainerUrls      = $outputs.container_urls.value
    SpokeToHubPeeringId = $outputs.spoke_to_hub_peering_id.value
    HubToSpokePeeringId = $outputs.hub_to_spoke_peering_id.value
    FirewallHandoff    = $outputs.firewall_handoff.value
    UnityCatalogHandoff = $outputs.unity_catalog_handoff.value
}

$selected | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $OutputDirectory "$environmentName-platform-handoff.json") -Encoding utf8

# The command is null when Terraform manages the hub-side peering or hub_vnet_id is not set.
if ($outputs.hub_side_peering_command.value) {
    $outputs.hub_side_peering_command.value | Set-Content -Path (Join-Path $OutputDirectory 'hub-side-peering-command.ps1') -Encoding utf8
}

Write-Host "Handoff package written to $OutputDirectory" -ForegroundColor Green
