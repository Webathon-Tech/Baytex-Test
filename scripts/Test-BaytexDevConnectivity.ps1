#Requires -Version 7.2

<#
.SYNOPSIS
    Tests DNS resolution and TCP connectivity from each HAProxy VM to the on-premises destinations.

.DESCRIPTION
    Runs a short shell script on every VM through az vm run-command, so it needs no SSH access or network path to the
    VMs, only a role such as Virtual Machine Contributor on the connectivity resource group. For each VM and destination
    it records the resolved address and whether a TCP connection opened, writes every result to a JSON file, and exits
    with 1 when any test fails.

    It works for any environment: pass that environment's subscription, connectivity resource group and VM names.

.PARAMETER SubscriptionId
    The environment subscription.

.PARAMETER ConnectivityResourceGroupName
    The resource group that holds the HAProxy VMs, rg-<org>-<workload>-<env>-connectivity-<region>-<instance>.

.PARAMETER ProxyVmNames
    Names of the HAProxy VMs, vm-<prefix>-proxy-01 and vm-<prefix>-proxy-02.

.PARAMETER Endpoints
    Destinations to test, keyed by a short name, each with an fqdn and a port.

.PARAMETER OutputPath
    Where the JSON results are written.

.EXAMPLE
    $endpoints = @{
        sql6     = @{ fqdn = 'sql6.baytexenergy.com'; port = 1433 }
        ora33yyc = @{ fqdn = 'ora33yyc.baytexenergy.com'; port = 1521 }
    }
    ./scripts/Test-BaytexDevConnectivity.ps1 -SubscriptionId <subscription-id> `
        -ConnectivityResourceGroupName rg-bte-dbx-prod-connectivity-cnc-001 `
        -ProxyVmNames vm-bte-dbx-prod-cnc-001-proxy-01, vm-bte-dbx-prod-cnc-001-proxy-02 `
        -Endpoints $endpoints
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ConnectivityResourceGroupName,

    [Parameter(Mandatory)]
    [string[]]$ProxyVmNames,

    [Parameter(Mandatory)]
    [hashtable]$Endpoints,

    [string]$OutputPath = "./connectivity-test-results.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required.'
}

az account set --subscription $SubscriptionId
$results = [System.Collections.Generic.List[object]]::new()

foreach ($vmName in $ProxyVmNames) {
    foreach ($entry in $Endpoints.GetEnumerator()) {
        $name = $entry.Key
        $fqdn = [string]$entry.Value.fqdn
        $port = [int]$entry.Value.port

        $script = @"
set -e
printf 'VM=%s\n' "`$(hostname)"
printf 'DNS='; getent ahostsv4 '$fqdn' | head -n 1 || true
if timeout 10 nc -vz '$fqdn' '$port' 2>&1; then
  echo 'RESULT=PASS'
else
  echo 'RESULT=FAIL'
  exit 10
fi
"@

        Write-Host "Testing $vmName -> $fqdn`:$port" -ForegroundColor Cyan
        $raw = az vm run-command invoke `
            --subscription $SubscriptionId `
            --resource-group $ConnectivityResourceGroupName `
            --name $vmName `
            --command-id RunShellScript `
            --scripts $script `
            --output json | ConvertFrom-Json

        $message = ($raw.value | ForEach-Object message) -join "`n"
        $passed = $message -match 'RESULT=PASS'

        $results.Add([pscustomobject]@{
            VmName    = $vmName
            Endpoint  = $name
            Fqdn      = $fqdn
            Port      = $port
            Passed    = $passed
            Evidence  = $message
            TestedAt  = (Get-Date).ToUniversalTime().ToString('o')
        })
    }
}

$results | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding utf8
$results | Select-Object VmName, Endpoint, Fqdn, Port, Passed | Format-Table -AutoSize

if (@($results | Where-Object { -not $_.Passed }).Count -gt 0) {
    Write-Error "One or more connectivity tests failed. Review $OutputPath."
    exit 1
}
