# Local Runs

How to plan and apply a platform environment from your own workstation, signed in to Azure as yourself, against the
same state file the pipelines use. Local runs suit development and troubleshooting, normally in dev; test and prod
changes go through the gated pipelines described in [Workflows](workflows.md).

The commands are PowerShell and work in Windows PowerShell 5.1 and PowerShell 7; the scripts in `scripts/` need
PowerShell 7.2 or later. Run them in order, in one window opened at the repository root, because later blocks use
variables that earlier blocks set. Every environment-specific value —
tenant, subscription, state backend and `terraform.tfvars` — is read from the environment's `<env>-plan` GitHub
Environment.

---

## 1. Before you start

| You need | Check |
| --- | --- |
| Terraform at the version the pipelines use | `terraform version` matches `gh variable get TERRAFORM_VERSION` |
| Azure CLI | `az version` |
| GitHub CLI, signed in with access to this repository | `gh auth status` |

Your Azure user needs the same access as the environment's deployment service principal:

| Scope | Role | Why |
| --- | --- | --- |
| Environment subscription | Contributor and Role Based Access Control Administrator, or Owner | Creates the platform and assigns the managed identities their roles |
| State storage account | Storage Blob Data Contributor | Reads and writes the state blob; the account has shared key access disabled, so Owner or Contributor alone cannot open it |
| Databricks account console | Account admin | Required by the Network Connectivity Configuration and network policy APIs |
| Hub VNet, only when a peering flag is `true` | Network Contributor | Creates the peering on the hub VNet and peers the spoke with it |
| Hub Private DNS zones, only when zone IDs are set | Private DNS Zone Contributor | Registers the storage private endpoints in those zones |

## 2. Working alongside the pipelines

A local run uses the pipelines' state file and lock, but none of their controls:

- **One state, one lock.** Deploy, Destroy and Unlock queue behind each other in GitHub, but GitHub cannot see a local
  run. Do not apply while one of those workflows is running for the same environment.
- **The pipelines deploy `main`.** Apply from an up-to-date `main`, or from a branch you merge straight afterwards.
  Anything applied locally that is not on `main` is reverted by the next pipeline deploy.
- **`terraform.tfvars` must equal `TFVARS`.** A value changed only in your local copy is reverted by the next pipeline
  deploy. Step 4 fetches the file fresh for each session.
- **No approval gate and no evidence bundle.** Both belong to pipeline runs only.

## 3. Open the session

```powershell
# The environment to work on: dev, test or prod.
$environment = "dev"

Set-Location "environments\$environment"

# An ARM_CLIENT_ID, ARM_CLIENT_SECRET or ARM_USE_OIDC left in the session would make azurerm authenticate as that
# service principal instead of you. Clearing every ARM_* variable leaves the Azure CLI login as the only credential.
Get-ChildItem Env:ARM_* | Remove-Item

# The two settings every pipeline Terraform job carries. The second runs the NCC private endpoint rules on the
# Databricks provider's plugin framework implementation, as the pipelines do.
$env:ARM_USE_AZUREAD                    = "true"
$env:DATABRICKS_TF_ENABLED_PF_RESOURCES = "databricks_mws_ncc_private_endpoint_rule"

$planEnvironment = "$($environment)-plan"
$tenantId        = gh variable get AZURE_TENANT_ID       --env $planEnvironment
$subscriptionId  = gh variable get AZURE_SUBSCRIPTION_ID --env $planEnvironment

# Prompts for a sign-in only when the CLI is not already on this tenant.
if ((az account show --query tenantId -o tsv) -ne $tenantId) { az login --tenant $tenantId }
az account set --subscription $subscriptionId
az account show --query "{user:user.name, tenant:tenantId, subscription:name}" -o table
```

The last command should show your own user on the environment's subscription. The state backend, azurerm, azapi and
the Databricks provider all take their tokens from this login.

## 4. Fetch terraform.tfvars

The file is gitignored. This writes it from the `TFVARS` value on the `<env>-plan` GitHub Environment, replacing any
local copy:

```powershell
# cmd writes gh's output byte for byte. PowerShell redirection re-encodes it, as UTF-16 by default in Windows
# PowerShell, which Terraform rejects.
cmd /c "gh variable get TFVARS --env $planEnvironment > terraform.tfvars"
```

When `TFVARS` is held as an environment secret, GitHub does not return its value. Copy
`baytex.terraform.tfvars.example`, the content the secret is created from, and confirm with whoever maintains the secret
that it has not changed since:

```powershell
Copy-Item baytex.terraform.tfvars.example terraform.tfvars
```

## 5. Connect to the state backend

The backend values come from the same GitHub Environment the pipeline reads, so a local run always opens the state file
the pipeline writes.

```powershell
$stateRg        = gh variable get TF_STATE_RESOURCE_GROUP  --env $planEnvironment
$stateAccount   = gh variable get TF_STATE_STORAGE_ACCOUNT --env $planEnvironment
$stateContainer = gh variable get TF_STATE_CONTAINER       --env $planEnvironment
$stateKey       = gh variable get TF_STATE_KEY             --env $planEnvironment

# Confirms your user can read the state blob before Terraform tries to, and shows whether anything holds its lock.
az storage blob show --auth-mode login --account-name $stateAccount --container-name $stateContainer --name $stateKey `
  --query "{blob:name, modified:properties.lastModified, lease:properties.lease.state}" -o table
```

| Result | Meaning |
| --- | --- |
| A row with `lease` = `leased` | A run, from the pipeline or another workstation, holds the state lock. Wait for it to finish |
| A row with any other `lease` value | Ready |
| `BlobNotFound` | No state at this key. Expected only before the environment's first deploy; otherwise stop, because a plan against empty state tries to create the whole environment again |
| A permissions error naming the Storage Blob Data roles | Your user lacks Storage Blob Data Contributor on the state account |

```powershell
# -reconfigure attaches this directory to the backend below without offering to copy state from a backend it used
# before. -upgrade selects the newest providers the version constraints allow, as every pipeline run does.
terraform init -reconfigure -upgrade `
  -backend-config="resource_group_name=$stateRg" `
  -backend-config="storage_account_name=$stateAccount" `
  -backend-config="container_name=$stateContainer" `
  -backend-config="key=$stateKey" `
  -backend-config="use_azuread_auth=true"

terraform validate
```

## 6. Plan and apply

```powershell
# Holds the state lock while planning, so it reads a state nothing else is writing. If the state changes before you
# apply, Terraform rejects the saved plan as stale; plan again.
terraform plan -lock-timeout=10m -out=tfplan
```

Read the plan before applying. An environment that matches `main` and `TFVARS` reports `No changes`. Any
`must be replaced` deletes and recreates that resource, so find out why first.

When the plan removes an on-premises destination, remove the connections from its Private Link Service first, as the
deploy pipeline does. Databricks keeps the private endpoint of a deleted NCC rule for seven days, and Azure refuses to
delete a Private Link Service that still has a connection:

```powershell
# Every Private Link Service the saved plan deletes or replaces. Nothing is removed when the list is empty.
$plan = terraform show -json tfplan | ConvertFrom-Json
$removed = @($plan.resource_changes | Where-Object { $_.type -eq "azurerm_private_link_service" -and $_.change.actions -contains "delete" })
foreach ($pls in $removed.change.before.id) {
  foreach ($conn in (az network private-endpoint-connection list --id $pls --query "[].id" -o tsv)) {
    az network private-endpoint-connection delete --id $conn --yes -o none
  }
}
```

```powershell
# Applies exactly the saved plan, without asking again.
terraform apply -lock-timeout=10m tfplan
```

A pipeline deploy approves the Databricks private endpoint connections after its apply. After a local apply, run the
same step from PowerShell 7 in this directory:

```powershell
terraform output -json > outputs.json
..\..\scripts\Approve-BaytexDatabricksPrivateEndpoints.ps1 -TerraformOutputPath outputs.json -WaitMinutes 20
```

The script approves only the connections named in the outputs and leaves approved connections unchanged, so running it
after an apply that changed no NCC rule changes nothing. Its exit codes are listed in the
[deployment runbook](deployment-runbook.md#gate-5--private-link-approvals).

To look without changing anything, this plan neither waits on nor blocks a pipeline run, and cannot be applied:

```powershell
terraform plan -lock=false
```

Reading outputs:

```powershell
terraform output databricks_workspace_url
terraform output -json unity_catalog_handoff
```

## 7. Destroy

Run in the same session, after step 5.

```powershell
# Azure refuses to delete a Private Link Service that still has endpoint connections, and the endpoints Databricks
# created for the NCC rules outlive the NCC. Removing them first lets the destroy finish in one pass.
$plsIds = ((terraform output -json private_link_service_ids | Out-String) | ConvertFrom-Json).PSObject.Properties.Value
foreach ($pls in $plsIds) {
  $plsRg = $pls.Split("/")[4]
  $plsName = $pls.Split("/")[8]
  foreach ($conn in (az network private-link-service show -g $plsRg -n $plsName --query "privateEndpointConnections[].name" -o tsv)) {
    az network private-link-service connection delete -g $plsRg --service-name $plsName -n $conn -o none
  }
}

# Azure takes a moment before a Private Link Service reports zero connections.
Start-Sleep -Seconds 20

# Azure Databricks refuses to delete a network policy a running workspace still refers to, so the workspace is moved
# to the account default policy before the teardown.
terraform apply -var "attach_serverless_network_policy=false"

terraform plan -destroy -lock-timeout=10m -out=tfplan
terraform apply -lock-timeout=10m tfplan
```

If the apply stops with `cannot delete mws network connectivity config ... attached to one or more workspaces`, the NCC
unbind has not registered yet. Wait a minute and run the last two commands again.

The state storage account belongs to the separate `bootstrap/<env>` root and is not destroyed.

## 8. Release a stuck lock

Stopping a local apply part-way leaves its lease on the state blob, and the next run fails with
`Error acquiring the state lock`. The message gives the lock ID, and its `Who` line names the user and machine that
hold it. When it is your own run and that run has stopped:

```powershell
terraform force-unlock "<lock-id>"   # the ID from the error message
```

Never release a lock whose run is still going, because its state write would be lost. A lock held by a pipeline run is
released with **Terraform Unlock State** ([Workflows](workflows.md#35-release-a-stuck-state-lock)), so the release is
approved and recorded like the run it interrupts.

## 9. Finish

```powershell
# The saved plan holds every variable value in clear text, and removing terraform.tfvars makes the next session fetch
# the current TFVARS rather than reuse an old copy. Both files are gitignored.
Remove-Item tfplan, terraform.tfvars, outputs.json -ErrorAction SilentlyContinue
Set-Location ..\..
```
