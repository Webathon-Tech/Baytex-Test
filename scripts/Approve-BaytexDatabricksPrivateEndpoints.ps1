#Requires -Version 7.2

<#
.SYNOPSIS
    Approves the private endpoint connections Azure Databricks creates for an environment's Network Connectivity
    Configuration.

.DESCRIPTION
    Every NCC private endpoint rule makes Databricks create a private endpoint from its own subscription to a target in
    the environment: the data storage account, for the blob and dfs sub-resources, and one Private Link Service per
    on-premises destination. Each connection arrives as Pending, and serverless compute cannot use it until it is
    approved.

    The script approves only connections whose private endpoint name appears in the environment's
    ncc_private_endpoint_rules output, and reports every other connection without touching it.

    Re-running is safe. Connections that are already approved are reported and left alone, and nothing is approved twice.
    Connections left behind by rules that no longer exist are not in the output, so they are reported and never changed.

    Databricks creates the private endpoints a few minutes after the rules are applied. With -WaitMinutes, the script
    reviews the targets again every -PollSeconds, approving each expected connection as it appears, until all of them
    are approved or the wait ends. The deploy pipeline runs it this way after every apply.

    Exit codes:
      0  Every expected connection is approved.
      2  Expected connections are still pending, which happens only with -WhatIf.
      3  Expected private endpoints did not appear on any target before the wait ended, or a rule in the output has no
         private endpoint name.
      4  An expected connection is rejected or disconnected. Azure does not allow approving it, so the matching NCC rule
         is recreated in Terraform to raise a fresh connection.

.PARAMETER TerraformOutputPath
    Path to the JSON produced by "terraform output -json". The targets and the expected private endpoint names are read
    from the data_storage_account_id, private_link_service_ids and ncc_private_endpoint_rules outputs.

.PARAMETER StorageAccountId
    Resource ID of the data storage account, from the data_storage_account_id output.

.PARAMETER PrivateLinkServiceId
    Resource IDs of the Private Link Services, from the private_link_service_ids output.

.PARAMETER ExpectedPrivateEndpointName
    Private endpoint names to approve, from the endpoint_name field of each ncc_private_endpoint_rules entry.

.PARAMETER Description
    Reason recorded on each approval.

.PARAMETER IncludeAlreadyApproved
    List connections that were already approved as well as the ones this run changed.

.PARAMETER WaitMinutes
    How long to keep reviewing the targets while expected private endpoints have not appeared yet. The default, 0,
    reviews them once.

.PARAMETER PollSeconds
    Pause between reviews while waiting.

.EXAMPLE
    terraform -chdir=environments/dev output -json > dev-outputs.json
    ./scripts/Approve-BaytexDatabricksPrivateEndpoints.ps1 -TerraformOutputPath dev-outputs.json

.EXAMPLE
    ./scripts/Approve-BaytexDatabricksPrivateEndpoints.ps1 -TerraformOutputPath outputs.json -WaitMinutes 20 -IncludeAlreadyApproved -Confirm:$false

    Runs unattended, as the deploy pipeline does: approves without prompting and waits up to 20 minutes for the
    private endpoints Databricks is still creating.

.EXAMPLE
    $parameters = @{
        StorageAccountId            = '/subscriptions/.../storageAccounts/stbtedbxdevcnc001'
        PrivateLinkServiceId        = '/subscriptions/.../privateLinkServices/pls-bte-dbx-dev-cnc-001-sql6'
        ExpectedPrivateEndpointName = 'ncc-pe-blob-0001', 'ncc-pe-dfs-0001', 'ncc-pe-sql6-0001'
    }
    ./scripts/Approve-BaytexDatabricksPrivateEndpoints.ps1 @parameters -WhatIf
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'FromTerraformOutput')]
param(
    [Parameter(Mandatory, ParameterSetName = 'FromTerraformOutput')]
    [ValidateNotNullOrEmpty()]
    [string]$TerraformOutputPath,

    [Parameter(Mandatory, ParameterSetName = 'FromResourceIds')]
    [ValidateNotNullOrEmpty()]
    [string]$StorageAccountId,

    [Parameter(ParameterSetName = 'FromResourceIds')]
    [string[]]$PrivateLinkServiceId = @(),

    [Parameter(Mandatory, ParameterSetName = 'FromResourceIds')]
    [ValidateNotNullOrEmpty()]
    [string[]]$ExpectedPrivateEndpointName,

    [string]$Description = 'Approved for the Baytex Azure Databricks Network Connectivity Configuration',

    [switch]$IncludeAlreadyApproved,

    [ValidateRange(0, 240)]
    [int]$WaitMinutes = 0,

    [ValidateRange(5, 600)]
    [int]$PollSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------------------------------------------------

# Reads a property that may be absent, which a plain property reference would turn into an error under strict mode.
function Get-Property {
    param($InputObject, [string]$Name)

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

# Runs the Azure CLI and returns the parsed JSON, or throws naming the command that failed.
# The Azure CLI writes its errors to standard error, which PowerShell can surface as an error record of its own. The
# preference is relaxed around the call so the exit code alone decides whether the command succeeded, while the CLI's
# own message still reaches the console.
function Invoke-AzJson {
    param([string[]]$Arguments, [switch]$AllowFailure)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = az @Arguments --output json
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $null }
        throw "az $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
    if ([string]::IsNullOrWhiteSpace($output)) { return $null }
    return $output | ConvertFrom-Json
}

# The subscription is part of every resource ID, so it never has to be supplied or set as the CLI default.
function Get-SubscriptionIdFromResourceId {
    param([string]$ResourceId)

    $segments = $ResourceId.Trim('/').Split('/')
    if ($segments.Length -ge 2 -and $segments[0] -eq 'subscriptions') { return $segments[1] }
    throw "Cannot read a subscription from the resource ID '$ResourceId'."
}

# ----------------------------------------------------------------------------------------------------------------------
# Prerequisites
# ----------------------------------------------------------------------------------------------------------------------

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required. Install it and run az login.'
}

if (-not (Invoke-AzJson -Arguments @('account', 'show') -AllowFailure)) {
    throw 'Azure CLI is not authenticated. Run az login first.'
}

# ----------------------------------------------------------------------------------------------------------------------
# Targets and expected endpoint names
# ----------------------------------------------------------------------------------------------------------------------

$targets = [System.Collections.Generic.List[string]]::new()
$expected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$unnamedRules = [System.Collections.Generic.List[string]]::new()

if ($PSCmdlet.ParameterSetName -eq 'FromTerraformOutput') {
    if (-not (Test-Path -LiteralPath $TerraformOutputPath)) {
        throw "Terraform output file '$TerraformOutputPath' was not found. Create it with: terraform output -json > outputs.json"
    }

    $outputs = Get-Content -LiteralPath $TerraformOutputPath -Raw | ConvertFrom-Json

    $storageAccount = Get-Property (Get-Property $outputs 'data_storage_account_id') 'value'
    if ($storageAccount) { $targets.Add([string]$storageAccount) }

    $privateLinkServices = Get-Property (Get-Property $outputs 'private_link_service_ids') 'value'
    if ($privateLinkServices) {
        foreach ($service in $privateLinkServices.PSObject.Properties) { $targets.Add([string]$service.Value) }
    }

    $rules = Get-Property (Get-Property $outputs 'ncc_private_endpoint_rules') 'value'
    if ($rules) {
        foreach ($rule in $rules.PSObject.Properties) {
            $endpointName = Get-Property $rule.Value 'endpoint_name'
            if ($endpointName) { [void]$expected.Add([string]$endpointName) }
            else { $unnamedRules.Add($rule.Name) }
        }
    }

    if ($targets.Count -eq 0) {
        throw "'$TerraformOutputPath' holds no data_storage_account_id or private_link_service_ids output. Produce it from the environment root with: terraform output -json > outputs.json"
    }
    if ($expected.Count -eq 0) {
        throw "'$TerraformOutputPath' holds no ncc_private_endpoint_rules output, so there is no list of endpoint names to approve against."
    }
}
else {
    $targets.Add($StorageAccountId)
    foreach ($id in $PrivateLinkServiceId) {
        if (-not [string]::IsNullOrWhiteSpace($id)) { $targets.Add($id) }
    }
    foreach ($name in $ExpectedPrivateEndpointName) {
        if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$expected.Add($name) }
    }
}

Write-Host "Targets to review:          $($targets.Count)" -ForegroundColor Cyan
Write-Host "Expected private endpoints: $($expected.Count)" -ForegroundColor Cyan

# ----------------------------------------------------------------------------------------------------------------------
# Review and approve
# ----------------------------------------------------------------------------------------------------------------------

# Reads every connection on every target, approves the expected ones that are pending, and returns one record per
# connection together with the expected endpoint names that were found.
function Invoke-ConnectionReview {
    $records = [System.Collections.Generic.List[object]]::new()
    $found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($resourceId in $targets) {
        $subscriptionId = Get-SubscriptionIdFromResourceId -ResourceId $resourceId
        $isPrivateLinkService = $resourceId -match '/providers/Microsoft.Network/privateLinkServices/'

        $connections = Invoke-AzJson -AllowFailure -Arguments @(
            'network', 'private-endpoint-connection', 'list',
            '--id', $resourceId,
            '--subscription', $subscriptionId
        )

        # A Private Link Service also reports its connections on the service itself, which is the reliable source when
        # the generic private-endpoint-connection command cannot read them.
        if ($null -eq $connections -and $isPrivateLinkService) {
            $service = Invoke-AzJson -AllowFailure -Arguments @('network', 'private-link-service', 'show', '--ids', $resourceId)
            $connections = Get-Property $service 'privateEndpointConnections'
        }

        # One target that cannot be read never stops the run: the remaining targets are still reviewed, and the summary
        # reports every expected endpoint that was not found.
        if ($null -eq $connections) {
            Write-Warning "No private endpoint connections could be read from $resourceId. Check that the resource exists and that the signed-in account can read it."
            continue
        }

        foreach ($connection in @($connections)) {
            $properties = Get-Property $connection 'properties'
            $connectionState = Get-Property $properties 'privateLinkServiceConnectionState'
            $status = [string](Get-Property $connectionState 'status')
            $privateEndpoint = Get-Property $properties 'privateEndpoint'
            $privateEndpointId = [string](Get-Property $privateEndpoint 'id')
            $privateEndpointName = if ($privateEndpointId) { Split-Path $privateEndpointId -Leaf } else { '' }
            $connectionId = [string](Get-Property $connection 'id')
            $isExpected = $expected.Contains($privateEndpointName)

            if ($isExpected) { [void]$found.Add($privateEndpointName) }

            $record = [pscustomobject]@{
                Target          = Split-Path $resourceId -Leaf
                Connection      = [string](Get-Property $connection 'name')
                PrivateEndpoint = $privateEndpointName
                Expected        = $isExpected
                Status          = $status
                Action          = 'None'
            }

            # Anything Databricks did not create for this environment's current rules is left alone for a person to
            # review.
            if (-not $isExpected) {
                $record.Action = 'SkippedUnexpectedEndpoint'
                $records.Add($record)
                continue
            }

            switch ($status) {
                'Pending' {
                    if ($PSCmdlet.ShouldProcess($connectionId, "Approve private endpoint '$privateEndpointName'")) {
                        if ($isPrivateLinkService) {
                            $null = Invoke-AzJson -Arguments @(
                                'network', 'private-link-service', 'connection', 'update',
                                '--ids', $connectionId,
                                '--connection-status', 'Approved',
                                '--description', $Description
                            )
                        }
                        else {
                            $null = Invoke-AzJson -Arguments @(
                                'network', 'private-endpoint-connection', 'approve',
                                '--id', $connectionId,
                                '--description', $Description
                            )
                        }
                        $record.Status = 'Approved'
                        $record.Action = 'Approved'
                        Write-Host "Approved $privateEndpointName on $(Split-Path $resourceId -Leaf)" -ForegroundColor Green
                    }
                    else {
                        $record.Action = 'WhatIf'
                    }
                }
                'Approved' {
                    # A re-run reaches this branch for every connection an earlier run approved, and changes nothing.
                    $record.Action = 'AlreadyApproved'
                }
                default {
                    # Rejected, Disconnected or an unknown state, none of which Azure allows to be approved.
                    $record.Action = 'NeedsAttention'
                }
            }

            $records.Add($record)
        }
    }

    return [pscustomobject]@{ Records = $records; Found = $found }
}

# Each pass approves whatever has appeared since the previous one. The wait ends as soon as every expected endpoint has
# been found, and at once when a connection needs attention, because waiting cannot change a rejected connection.
$deadline = (Get-Date).AddMinutes($WaitMinutes)
$approvedByRun = [System.Collections.Generic.List[object]]::new()
$pass = 0

while ($true) {
    $pass++
    Write-Host ''
    Write-Host "Review pass $pass" -ForegroundColor Cyan

    $review = Invoke-ConnectionReview
    $results = $review.Records
    $seen = $review.Found
    foreach ($record in @($results | Where-Object { $_.Action -eq 'Approved' })) { $approvedByRun.Add($record) }

    $missing = @($expected | Where-Object { -not $seen.Contains($_) })
    $needsAttention = @($results | Where-Object { $_.Action -eq 'NeedsAttention' })
    $isWhatIf = @($results | Where-Object { $_.Action -eq 'WhatIf' }).Count -gt 0

    if ($missing.Count -eq 0 -or $needsAttention.Count -gt 0 -or $isWhatIf -or (Get-Date) -ge $deadline) { break }

    Write-Host "Waiting for $($missing.Count) private endpoint(s) Databricks has not created yet: $($missing -join ', ')"
    Start-Sleep -Seconds $PollSeconds
}

# ----------------------------------------------------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------------------------------------------------

Write-Host ''
if ($results.Count -eq 0) {
    Write-Warning 'No private endpoint connections were found on any target.'
}
else {
    $results |
        Where-Object { $IncludeAlreadyApproved -or $_.Action -ne 'AlreadyApproved' } |
        Sort-Object Target, Connection |
        Format-Table -AutoSize |
        Out-String -Width 400 |
        Write-Host
}

$alreadyApproved = @($results | Where-Object { $_.Action -eq 'AlreadyApproved' })
$unexpectedUnapproved = @($results | Where-Object { $_.Action -eq 'SkippedUnexpectedEndpoint' -and $_.Status -ne 'Approved' })
$stillPending = @($results | Where-Object { $_.Expected -and $_.Status -eq 'Pending' })

Write-Host "Approved by this run: $($approvedByRun.Count)"
Write-Host "Already approved:     $($alreadyApproved.Count)"

# Approved connections outside the output, such as the platform's own private endpoints, need no attention.
if ($unexpectedUnapproved.Count -gt 0) {
    Write-Warning "$($unexpectedUnapproved.Count) connection(s) that are not approved were skipped because their private endpoint name is not in the ncc_private_endpoint_rules output. Review them before approving anything by hand."
}

if ($needsAttention.Count -gt 0) {
    Write-Warning "$($needsAttention.Count) connection(s) are rejected or disconnected and cannot be approved: $(@($needsAttention | ForEach-Object { $_.PrivateEndpoint }) -join ', '). Recreate the matching NCC rule to raise a fresh connection."
    exit 4
}

if ($stillPending.Count -gt 0) {
    Write-Warning "$($stillPending.Count) expected connection(s) are still pending."
    exit 2
}

if ($unnamedRules.Count -gt 0) {
    Write-Warning "$($unnamedRules.Count) rule(s) in the ncc_private_endpoint_rules output have no private endpoint name: $($unnamedRules -join ', '). Refresh the state with terraform apply -refresh-only, export the outputs again and re-run."
    exit 3
}

if ($missing.Count -gt 0) {
    Write-Warning "$($missing.Count) expected private endpoint(s) have no connection on any target: $($missing -join ', '). Check each rule's state in the Databricks account console, and re-run with -WaitMinutes to wait for endpoints that are still being created."
    exit 3
}

Write-Host 'Every expected private endpoint connection is approved.' -ForegroundColor Green
exit 0
