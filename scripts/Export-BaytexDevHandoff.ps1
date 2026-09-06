#Requires -Version 7.2
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
    AccessConnectorId  = $outputs.access_connector_id.value
    ContainerUrls      = $outputs.container_urls.value
    FirewallHandoff    = $outputs.firewall_handoff.value
    UnityCatalogHandoff = $outputs.unity_catalog_handoff.value
}

$selected | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $OutputDirectory 'dev-platform-handoff.json') -Encoding utf8
$outputs.hub_side_peering_command.value | Set-Content -Path (Join-Path $OutputDirectory 'hub-side-peering-command.ps1') -Encoding utf8

Write-Host "Handoff package written to $OutputDirectory" -ForegroundColor Green
