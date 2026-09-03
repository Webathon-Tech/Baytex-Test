<#
.SYNOPSIS
    Post-apply end-to-end validation of the sandbox rehearsal.

.DESCRIPTION
    Runs the checks that prove the platform actually works, not merely that
    Terraform reported success. Each check maps to a real Baytex acceptance
    criterion in docs/deployment-runbook.md (Gate 7).

    Uses 'az vm run-command' throughout, so it needs no inbound SSH and works
    with admin_ssh_source_cidrs = [].

    Remote scripts are written to temp files with UNIX (LF) line endings and
    passed as '--scripts @file'. Do NOT inline them: Windows mangles shell
    metacharacters such as | ( ) $ when they pass through az.cmd, and a CRLF
    shebang fails on the Linux guest with "bash\r: No such file or directory" --
    the same defect this rehearsal found in the HAProxy cloud-init templates.

.NOTES
    Run AFTER:
      - terraform apply (phase 1)
      - Link-SandboxDnsToSpoke.ps1
      - the hub-side peering command from 'terraform output hub_side_peering_command'
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId = "6a3bb170-5159-4bff-860b-aa74fb762697",
    [string]$ConnectivityResourceGroup = "rg-sbx-dbx-dev-connectivity-cnc-001",
    [string]$NetworkResourceGroup = "rg-sbx-dbx-dev-network-cnc-001",
    [string]$SpokeVnetName = "vnet-sbx-dbx-dev-cnc-001",
    [string[]]$ProxyVmNames = @("vm-sbx-dbx-dev-cnc-001-proxy-01", "vm-sbx-dbx-dev-cnc-001-proxy-02"),
    [string]$StorageAccountName = "stsbxdbxdevcnc001"
)

$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[object]]::new()
$tempDir = Join-Path ([IO.Path]::GetTempPath()) "sbx-validation"
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

function Add-Result {
    param([string]$Check, [bool]$Passed, [string]$Detail)
    $results.Add([pscustomobject]@{ Check = $Check; Passed = $Passed; Detail = $Detail })
    $colour = 'Red'; $label = 'FAIL'
    if ($Passed) { $colour = 'Green'; $label = 'PASS' }
    Write-Host ("[{0}] {1}" -f $label, $Check) -ForegroundColor $colour
    if ($Detail) { Write-Host ("       {0}" -f $Detail) -ForegroundColor DarkGray }
}

function Invoke-OnVm {
    param([string]$VmName, [string]$ScriptBody, [string]$Tag)
    # Force LF endings; a CRLF shebang is fatal on the Linux guest.
    $path = Join-Path $tempDir "$Tag.sh"
    $lf = ($ScriptBody -replace "`r`n", "`n")
    [IO.File]::WriteAllText($path, $lf, (New-Object Text.UTF8Encoding $false))

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $raw = & az vm run-command invoke --subscription $SubscriptionId `
        --resource-group $ConnectivityResourceGroup --name $VmName `
        --command-id RunShellScript --scripts "@$path" `
        --query "value[0].message" -o tsv 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) { return "RUNCOMMAND-FAILED: $raw" }
    return ($raw | Out-String)
}

# --- 1. peering ------------------------------------------------------------
Write-Host "`n=== 1. VNet peering state ===" -ForegroundColor Cyan
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$peerState = & az network vnet peering list --subscription $SubscriptionId `
    -g $NetworkResourceGroup --vnet-name $SpokeVnetName `
    --query "[].{name:name,state:peeringState}" -o tsv 2>&1
$ErrorActionPreference = $previous
$peerConnected = ("$peerState" -match 'Connected')
Add-Result "Spoke-to-hub peering Connected" $peerConnected ("$peerState" -replace '\s+', ' ').Trim()
if (-not $peerConnected) {
    Write-Warning "State 'Initiated' means the hub side is missing. Run:"
    Write-Warning "  terraform output -raw hub_side_peering_command"
}

# --- 2. on-prem DNS --------------------------------------------------------
Write-Host "`n=== 2. DNS resolution of simulated on-prem hosts ===" -ForegroundColor Cyan
$dnsBody = @'
for h in sqlsim.sandbox.internal orasim.sandbox.internal; do
  ip=$(getent hosts "$h" | awk '{print $1}' | head -n1)
  echo "$h=${ip:-UNRESOLVED}"
done
'@
$dnsOut = Invoke-OnVm -VmName $ProxyVmNames[0] -ScriptBody $dnsBody -Tag 'dns'
$dnsOk = ($dnsOut -match 'sqlsim\.sandbox\.internal=10\.98\.1\.4') -and ($dnsOut -match 'orasim\.sandbox\.internal=10\.98\.1\.4')
Add-Result "Private DNS resolves on-prem sims to 10.98.1.4" $dnsOk (($dnsOut -split "`n" | Where-Object { $_ -match '=' }) -join '; ')

# --- 3. storage privatelink DNS -------------------------------------------
Write-Host "`n=== 3. Storage private endpoint resolves to a private IP ===" -ForegroundColor Cyan
$peBody = "getent hosts $StorageAccountName.dfs.core.windows.net | awk '{print `$1}' | head -n1"
$peOut = Invoke-OnVm -VmName $ProxyVmNames[0] -ScriptBody $peBody -Tag 'pe'
$peOk = ($peOut -match '10\.99\.82\.')
Add-Result "DFS private endpoint resolves to 10.99.82.x" $peOk (($peOut -replace '\s+', ' ')).Trim()

# --- 4. routed path to on-prem --------------------------------------------
Write-Host "`n=== 4. TCP path: proxy -> route table -> NVA -> on-prem sim ===" -ForegroundColor Cyan
$tcpBody = @'
for t in sqlsim.sandbox.internal:1433 orasim.sandbox.internal:1521; do
  h=${t%%:*}; p=${t##*:}
  r=$(timeout 8 bash -c "cat < /dev/tcp/$h/$p" 2>/dev/null | head -c 30 | tr -d '\r\n')
  if [ -n "$r" ]; then echo "$t => $r"; else echo "$t => NO-RESPONSE"; fi
done
'@
foreach ($vm in $ProxyVmNames) {
    $tcpOut = Invoke-OnVm -VmName $vm -ScriptBody $tcpBody -Tag "tcp-$vm"
    Add-Result "$vm -> sqlsim:1433" ($tcpOut -match 'SIMULATED-SQL-OK') (($tcpOut -split "`n" | Where-Object { $_ -match 'sqlsim' }) -join ' ')
    Add-Result "$vm -> orasim:1521" ($tcpOut -match 'SIMULATED-ORACLE-OK') (($tcpOut -split "`n" | Where-Object { $_ -match 'orasim' }) -join ' ')
}

# --- 5. haproxy runtime health --------------------------------------------
Write-Host "`n=== 5. HAProxy service health ===" -ForegroundColor Cyan
$haBody = @'
echo "cloud-init=$(cloud-init status 2>/dev/null | head -n1)"
echo "haproxy=$(systemctl is-active haproxy)"
echo "lbips=$(systemctl is-active baytex-lb-ips.service)"
echo "dummy0=$(ip -4 -o addr show dummy0 2>/dev/null | wc -l)"
echo "listeners=$(ss -lnt | grep -cE '1433|1521|8404')"
'@
foreach ($vm in $ProxyVmNames) {
    $haOut = Invoke-OnVm -VmName $vm -ScriptBody $haBody -Tag "ha-$vm"
    $haOk = ($haOut -match 'haproxy=active')
    Add-Result "$vm haproxy active" $haOk (($haOut -split "`n" | Where-Object { $_ -match '=' }) -join ' ')
}

# --- 6. ILB frontends ------------------------------------------------------
Write-Host "`n=== 6. Load balancer front-end reachability ===" -ForegroundColor Cyan
$lbBody = @'
for t in 10.99.83.11:1433 10.99.83.12:1521; do
  h=${t%%:*}; p=${t##*:}
  r=$(timeout 8 bash -c "cat < /dev/tcp/$h/$p" 2>/dev/null | head -c 30 | tr -d '\r\n')
  if [ -n "$r" ]; then echo "$t => $r"; else echo "$t => NO-RESPONSE"; fi
done
'@
$lbOut = Invoke-OnVm -VmName $ProxyVmNames[0] -ScriptBody $lbBody -Tag 'lb'
Add-Result "ILB 10.99.83.11:1433 proxies to on-prem sim" ($lbOut -match 'SIMULATED-SQL-OK') (($lbOut -split "`n" | Where-Object { $_ -match '10\.99\.83\.11' }) -join ' ')
Add-Result "ILB 10.99.83.12:1521 proxies to on-prem sim" ($lbOut -match 'SIMULATED-ORACLE-OK') (($lbOut -split "`n" | Where-Object { $_ -match '10\.99\.83\.12' }) -join ' ')

# --- summary ---------------------------------------------------------------
Write-Host "`n=================== SUMMARY ===================" -ForegroundColor Cyan
$results | Format-Table -AutoSize
$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) of $($results.Count) checks FAILED." -ForegroundColor Red
    exit 1
}
Write-Host "All $($results.Count) checks passed." -ForegroundColor Green
