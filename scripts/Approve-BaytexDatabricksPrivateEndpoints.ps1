#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string[]]$TargetResourceIds,

    [Parameter(Mandatory)]
    [string[]]$ExpectedPrivateEndpointNames,

    [string]$Description = "Approved for Baytex DEV Azure Databricks NCC",

    [switch]$IncludeAlreadyApproved
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required.'
}

$account = az account show --output json | ConvertFrom-Json
if (-not $account) {
    throw 'Azure CLI is not authenticated. Run az login first.'
}

az account set --subscription $SubscriptionId
$expected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in $ExpectedPrivateEndpointNames) {
    [void]$expected.Add($name)
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($resourceId in $TargetResourceIds) {
    Write-Host "Reviewing private endpoint connections on $resourceId" -ForegroundColor Cyan

    $connections = az network private-endpoint-connection list `
        --id $resourceId `
        --subscription $SubscriptionId `
        --output json | ConvertFrom-Json

    foreach ($connection in @($connections)) {
        $status = [string]$connection.properties.privateLinkServiceConnectionState.status
        $privateEndpointId = [string]$connection.properties.privateEndpoint.id
        $privateEndpointName = if ($privateEndpointId) { Split-Path $privateEndpointId -Leaf } else { '' }
        $isExpected = $expected.Contains($privateEndpointName)

        $record = [pscustomobject]@{
            TargetResourceId  = $resourceId
            ConnectionId      = $connection.id
            ConnectionName    = $connection.name
            Status            = $status
            PrivateEndpoint   = $privateEndpointId
            ExpectedEndpoint  = $isExpected
            Action            = 'None'
        }

        if (-not $isExpected) {
            $record.Action = 'SkippedUnexpectedEndpoint'
            $results.Add($record)
            continue
        }

        if ($status -eq 'Pending') {
            if ($PSCmdlet.ShouldProcess($connection.id, "Approve expected Databricks private endpoint '$privateEndpointName'")) {
                az network private-endpoint-connection approve `
                    --id $connection.id `
                    --subscription $SubscriptionId `
                    --description $Description `
                    --only-show-errors | Out-Null
                $record.Action = 'Approved'
                $record.Status = 'Approved'
            }
            else {
                $record.Action = 'WhatIf'
            }
        }
        elseif ($IncludeAlreadyApproved -and $status -eq 'Approved') {
            $record.Action = 'AlreadyApproved'
        }

        $results.Add($record)
    }
}

$results | Sort-Object TargetResourceId, ConnectionName | Format-Table -AutoSize

$unexpected = @($results | Where-Object { -not $_.ExpectedEndpoint })
if ($unexpected.Count -gt 0) {
    Write-Warning "$($unexpected.Count) connection(s) were skipped because their private endpoint names were not in the approved NCC output."
}

$pendingExpected = @($results | Where-Object { $_.ExpectedEndpoint -and $_.Status -eq 'Pending' })
if ($pendingExpected.Count -gt 0) {
    Write-Warning "$($pendingExpected.Count) expected private endpoint connection(s) remain pending."
    exit 2
}
