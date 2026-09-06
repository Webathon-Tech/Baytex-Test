#Requires -Version 7.2
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
