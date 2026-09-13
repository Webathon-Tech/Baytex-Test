# Local Runs — dev from a Workstation

Plan and apply the dev platform from your own machine, signed in to Azure as yourself, against the same state file the
pipelines use. The commands are PowerShell and work in Windows PowerShell 5.1 and PowerShell 7. Run them in order, in
one window opened at the repository root, because later blocks use variables that earlier blocks set.

Every environment-specific value (tenant, subscription, state backend and `terraform.tfvars`) is read from the
`dev-plan` GitHub Environment, so none of the commands needs editing.

---

## 1. Before you start

| You need | Check |
| --- | --- |
| Terraform at the version the pipelines use | `terraform version` matches `gh variable get TERRAFORM_VERSION` |
| Azure CLI | `az version` |
| GitHub CLI, signed in with access to this repository | `gh auth status` |

Your Azure user needs the same access as the dev deployment service principal:

| Scope | Role | Why |
| --- | --- | --- |
| dev subscription | Contributor and User Access Administrator, or Owner | Creates the platform and assigns the managed identities their roles |
| State storage account | Storage Blob Data Contributor | Reads and writes the state blob. The account has shared key access disabled, so Owner or Contributor without this role cannot open it |
| Databricks account console | Account admin | The Network Connectivity Configuration API refuses anyone else |
| Hub VNet, only when a peering flag is `true` | Network Contributor | Creates the peering on the hub VNet and peers the spoke with it |
| Hub Private DNS zones, only when zone IDs are set | Private DNS Zone Contributor | Registers the storage private endpoints in those zones |

## 2. Working alongside the pipelines

A local run uses the pipelines' state file and lock, but none of their controls:

- **One state, one lock.** Deploy, Destroy and Unlock queue behind each other in GitHub, but GitHub cannot see a local
  run. Do not apply while one of those workflows is running.
- **The pipelines deploy `main`.** Apply from an up-to-date `main`, or from a branch you merge straight afterwards.
  Anything applied locally that is not on `main` is reverted by the next pipeline deploy.
- **`terraform.tfvars` must equal `TFVARS`.** A value changed only in your local copy is reverted by the next pipeline
  deploy, and a stale local copy reverts the pipeline's values. Step 4 fetches the file fresh for each session.
- **No approval gate and no evidence bundle.** Both belong to pipeline runs only.

## 3. Open the session

```powershell
Set-Location environments\dev

# An ARM_CLIENT_ID, ARM_CLIENT_SECRET or ARM_USE_OIDC left in the session would make azurerm authenticate as that
# service principal instead of you. Clearing every ARM_* variable leaves the Azure CLI login as the only credential.
Get-ChildItem Env:ARM_* | Remove-Item

# The two settings every pipeline Terraform job carries. The second runs the NCC private endpoint rules on the
# Databricks provider's plugin framework implementation, as the pipelines do.
$env:ARM_USE_AZUREAD                    = "true"
$env:DATABRICKS_TF_ENABLED_PF_RESOURCES = "databricks_mws_ncc_private_endpoint_rule"

$tenantId       = gh variable get AZURE_TENANT_ID       --env dev-plan
$subscriptionId = gh variable get AZURE_SUBSCRIPTION_ID --env dev-plan

# Prompts for a sign-in only when the CLI is not already on this tenant.
if ((az account show --query tenantId -o tsv) -ne $tenantId) { az login --tenant $tenantId }
az account set --subscription $subscriptionId
az account show --query "{user:user.name, tenant:tenantId, subscription:name}" -o table
```

The last command should show your own user on the dev subscription. The state backend, azurerm, azapi and the
Databricks provider all take their tokens from this login.

## 4. Fetch terraform.tfvars

The file is gitignored. This writes it from the `TFVARS` value on the `dev-plan` GitHub Environment, replacing any local
copy:

```powershell
# cmd writes gh's output byte for byte. PowerShell redirection re-encodes it, as UTF-16 by default in Windows
# PowerShell, which Terraform rejects.
cmd /c "gh variable get TFVARS --env dev-plan > terraform.tfvars"
```

When `TFVARS` is held as an environment secret, GitHub does not return it. Copy `baytex.terraform.tfvars.example`
instead, which is the content the secret is created from, and confirm with whoever maintains the secret that it has not
changed since:

```powershell
Copy-Item baytex.terraform.tfvars.example terraform.tfvars
```

## 5. Connect to the state backend

The backend values come from the same GitHub Environment the pipeline reads, not from a local `backend.hcl`, so a local
run always opens the state file the pipeline writes.

```powershell
$stateRg        = gh variable get TF_STATE_RESOURCE_GROUP  --env dev-plan
$stateAccount   = gh variable get TF_STATE_STORAGE_ACCOUNT --env dev-plan
$stateContainer = gh variable get TF_STATE_CONTAINER       --env dev-plan
$stateKey       = gh variable get TF_STATE_KEY             --env dev-plan

# Proves your user can read the state blob before Terraform tries to, and shows whether anything holds its lock.
az storage blob show --auth-mode login --account-name $stateAccount --container-name $stateContainer --name $stateKey `
  --query "{blob:name, modified:properties.lastModified, lease:properties.lease.state}" -o table
```

| Result | Meaning |
| --- | --- |
| A row with `lease` = `leased` | A run, from the pipeline or another workstation, holds the state lock. Wait for it to finish |
| A row with any other `lease` value | Ready |
| `BlobNotFound` | No state at this key. Expected only before dev's first deploy; otherwise stop, because a plan against an empty state tries to create the whole environment again |
| A permissions error naming the Storage Blob Data roles | Your user lacks Storage Blob Data Contributor on the state account |

```powershell
# -reconfigure attaches this directory to the backend below and never offers to copy state from a backend it used
# before. -upgrade selects the newest providers the version constraints allow, which is what the pipeline gets on every
# run because the lock file is not committed.
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

Read the plan before applying. A dev environment that matches `main` and `TFVARS` reports `No changes`. Any
`must be replaced` deletes and recreates that resource, so find out why first.

```powershell
# Applies exactly the saved plan, without asking again.
terraform apply -lock-timeout=10m tfplan
```

After an apply that creates or recreates NCC rules, approve the Databricks private endpoint connections as described in
[docs/deployment-runbook.md](docs/deployment-runbook.md) Gate 5.

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
# created for the NCC rules outlive the NCC. Clearing them first lets the destroy finish in one pass.
$plsIds = ((terraform output -json private_link_service_ids | Out-String) | ConvertFrom-Json).PSObject.Properties.Value
foreach ($pls in $plsIds) {
  foreach ($conn in (az network private-endpoint-connection list --id $pls --query "[].id" -o tsv)) {
    az network private-endpoint-connection delete --id $conn --yes --only-show-errors -o none
  }
}

# Azure takes a moment before a Private Link Service reports zero connections.
Start-Sleep -Seconds 20

terraform plan -destroy -lock-timeout=10m -out=tfplan
terraform apply -lock-timeout=10m tfplan
```

If the apply stops with `cannot delete mws network connectivity config ... attached to one or more workspaces`, the NCC
unbind has not landed yet. Wait a minute and run the last two commands again.

The state storage account is a separate root, `bootstrap/dev`, and is not destroyed.

## 8. Release a stuck lock

Stopping a local apply part-way leaves its lease on the state blob, and the next run fails with
`Error acquiring the state lock`. That message gives the lock ID, and its `Who` line names the user and machine that
hold it. When it is your own run and that run has stopped:

```powershell
terraform force-unlock "<lock-id>"   # the ID from the error message
```

Never release a lock whose run is still going, because its state write would be lost. A lock held by a pipeline run is
released with **Terraform Unlock State** ([WORKFLOWS.md](WORKFLOWS.md) §3.5), so the release is approved and recorded
like the run it interrupts.

## 9. Finish

```powershell
# The saved plan holds every variable value in clear text, and removing terraform.tfvars makes the next session fetch
# the current TFVARS rather than reuse an old copy. Both files are gitignored.
Remove-Item tfplan, terraform.tfvars -ErrorAction SilentlyContinue
```
