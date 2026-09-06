# Pipeline Setup — What Must Be Done, By Whom

Everything needed to take this repository from a fresh clone to a deployed
environment, split by who has the rights to do each part.

All Terraform runs in **GitHub Actions**. Nothing is applied from a laptop. The
only local task is building the mock on-premises environment for a rehearsal
(see [LOCAL-DEVELOPMENT.md](LOCAL-DEVELOPMENT.md)); in a real client deployment
even that is unnecessary, because the hub and on-premises systems already exist.

---

## 1. Global Administrator — create the deployment identities

**Who:** an Entra Global Administrator (or Application Administrator + User
Access Administrator) in the target tenant.
**Where:** any workstation with Azure CLI and `gh` signed in.
**How often:** once per environment, per tenant.

```powershell
az login --tenant <TENANT-ID>

.\scripts\New-GitHubOidcServicePrincipal.ps1 -Environment dev  `
    -SubscriptionId <DEV-SUBSCRIPTION-ID>  -GitHubOrg <ORG> -GitHubRepo <REPO>
.\scripts\New-GitHubOidcServicePrincipal.ps1 -Environment test `
    -SubscriptionId <TEST-SUBSCRIPTION-ID> -GitHubOrg <ORG> -GitHubRepo <REPO>
.\scripts\New-GitHubOidcServicePrincipal.ps1 -Environment prod `
    -SubscriptionId <PROD-SUBSCRIPTION-ID> -GitHubOrg <ORG> -GitHubRepo <REPO>
```

Each run creates one app registration + service principal named
`sp-bte-dbx-<env>-github`, with:

| Item | Value |
| --- | --- |
| Federated credentials | one per GitHub Environment: `<env>-plan` and `<env>-apply` |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience | `api://AzureADTokenExchange` |
| Entity type | Environment |
| Azure roles | Contributor, User Access Administrator, Storage Blob Data Contributor |

The script is idempotent — re-running reuses existing objects and only fills in
what is missing. It retries transient ARM/Graph failures, so a dropped
connection will not leave a half-configured principal.

### Why those three roles

- **Contributor** builds the platform.
- **User Access Administrator** is required for exactly one thing: granting
  `Storage Blob Data Contributor` to the Databricks Access Connector. Contributor
  cannot write role assignments, so without this the data-foundation module fails.
- **Storage Blob Data Contributor** is a **data-plane** role. Neither Owner nor
  Contributor grants access to blob *content*, and the Terraform backend runs with
  `use_azuread_auth = true` — without it, `terraform init` fails with a 403 on the
  state blob even though the principal can see the storage account.

Pass `-UseOwnerRole` to collapse the first two into Owner if your security model
prefers it.

### Two OIDC subject formats

GitHub emits one of two subject shapes, depending on how the organisation has
configured its OIDC subject claim:

```
classic     repo:<org>/<repo>:environment:<env>
immutable   repo:<org>@<orgId>/<repo>@<repoId>:environment:<env>
```

The second embeds the numeric organisation and repository IDs — this is what the
Azure portal's *Organization ID* and *Repository ID* fields are for. Which form
an org emits is not discoverable in advance, and presenting the wrong one fails
with `AADSTS700213: No matching federated identity record found`. The script
registers **both**, so it works regardless. An unmatched federated credential is
inert, and Entra permits up to 20 per application.

> Those two ID fields cannot be stored on a subject-based credential at all —
> Microsoft Graph silently discards them. They only ever appear *inside* the
> subject string, which is why the portal shows them blank when you edit a
> credential created via API.

---

## 2. Databricks Account Administrator — grant account admin

**Who:** an existing Databricks account admin.
**Blocking:** `module.ncc` fails without this.

At `accounts.azuredatabricks.net` → **User management → Service principals**:

1. Add each `sp-bte-dbx-<env>-github` by its Application (client) ID if not listed.
2. Open each one → **Roles** → enable **Account admin**.

Adding the principal is *not* sufficient — the role toggle is what matters.
Without it the apply fails with:

```
cannot create mws network connectivity config:
This API is disabled for users without account admin status.
```

---

## 3. Repository Administrator — configure GitHub

**Who:** someone with admin on the repository.

Create six environments — `dev-plan`, `dev-apply`, `test-plan`, `test-apply`,
`prod-plan`, `prod-apply` — each carrying:

| Kind | Name | Value |
| --- | --- | --- |
| Variable | `AZURE_CLIENT_ID` | app ID printed by the script for that environment |
| Variable | `AZURE_TENANT_ID` | tenant ID |
| Variable | `AZURE_SUBSCRIPTION_ID` | that environment's subscription |
| Variable | `TF_STATE_RESOURCE_GROUP` | e.g. `rg-bte-dbx-dev-tfstate-cnc-001` |
| Variable | `TF_STATE_STORAGE_ACCOUNT` | e.g. `stbtedbxdevtfcnc001` |
| Variable | `TF_STATE_CONTAINER` | `tfstate` |
| Variable | `TF_STATE_KEY` | `<env>/platform.tfstate` |
| Secret | `TFVARS` | full contents of that environment's `terraform.tfvars` |

Scripted equivalent:

```bash
gh api -X PUT repos/<ORG>/<REPO>/environments/dev-plan
gh variable set AZURE_CLIENT_ID --env dev-plan --repo <ORG>/<REPO> --body "<app-id>"
gh secret   set TFVARS          --env dev-plan --repo <ORG>/<REPO> < environments/dev/terraform.tfvars
```

`plan` and `apply` for the same environment take the **same** values. They are
separate environments so the federated credential — and therefore the approval
gate — can differ between planning and applying.

### Approval gates

Attach **required reviewers** to `test-apply` and `prod-apply`. The run then
pauses there until a reviewer approves.

> Deployment protection rules require GitHub Pro, Team or Enterprise on a
> **private** repository. On the Free plan the environments still work and still
> scope secrets, but the reviewer gate is unavailable — the effective control is
> that a human chooses to run the workflow. Attach the reviewers once the plan
> allows it; no workflow changes are needed.

---

## 4. Running the pipelines

### First: create the state backend

```
Actions → "Terraform Bootstrap State Backend" → Run workflow → environment: dev
```

Creates the resource group, storage account and container, then migrates its own
state into the account it just created. Run once per environment.

It is safe to re-run at any time. It branches on whether the **state blob**
exists, not merely the storage account:

| State blob | Storage account | Action |
| --- | --- | --- |
| exists | exists | init remote → plan/apply (no-op) |
| missing | exists | init local → **import** RG/account/container → migrate |
| missing | missing | init local → apply → migrate |

Checking the blob rather than the account is what makes recovery work: if an
earlier run created the account but died before migrating, checking only the
account would init against an empty backend and then fail trying to create a
storage account whose name is already taken.

The final step asserts idempotency with `terraform plan -detailed-exitcode` and
fails the run if a re-run would still show changes.

### Then: deploy

```
Actions → "Terraform Deploy" → Run workflow → deploy_target: dev | test | prod | all
```

`all` runs the full promotion chain `dev → test → prod` and stops at the first
failure, so test is only reached once dev has actually applied. Single values run
one environment on its own.

Pull requests automatically run a plan-only check (`Terraform Plan (PR)`).

### Destroying an environment

```
Actions → "Terraform Destroy" → Run workflow → environment: dev, confirm: dev
```

The confirmation must match the chosen environment or the run stops before it
authenticates to Azure. Scope is the platform root only — the state backend
survives, so the environment can be rebuilt without re-bootstrapping.

Two things make this stack awkward to destroy, both handled by the workflow:

- Azure will not delete a **Private Link Service that still has private endpoint
  connections**, and the Databricks-managed endpoints outlive the NCC that created
  them. The workflow clears them before planning.
- Deleting the **NCC binding and the NCC** are separate Databricks calls and the
  unbind is not immediately visible, so the first attempt can fail with *"attached
  to one or more workspaces"*. The workflow retries, re-planning between attempts.

Afterwards, remove the **hub-side peering** yourself — Terraform never owned it:

```bash
az network vnet peering delete --subscription <hub-sub>   --resource-group <hub-rg> --vnet-name <hub-vnet> --name peer-hub-to-<spoke>
```

### Post-apply steps (not automated)

1. **Hub-side peering.** Terraform creates only the spoke side by design; the hub
   is customer-owned. Run the command emitted by the `hub_side_peering_command`
   output. Peering shows `Initiated` until the hub side exists, then `Connected`.
2. **DNS.** Link the central private DNS zones to the new spoke VNet.
3. **Approve NCC private endpoints.** Databricks raises them as `Pending`:
   ```powershell
   pwsh .\scripts\Approve-BaytexDatabricksPrivateEndpoints.ps1 `
     -SubscriptionId <sub> `
     -TargetResourceIds @("<storage-id>","<pls-id-1>","<pls-id-2>") `
     -ExpectedPrivateEndpointNames @(<endpoint_name values from ncc_private_endpoint_rules>)
   ```
   The storage account will show **four** connections: two created by Terraform
   (already approved) and two raised by Databricks. Only the latter need action.
4. **Validate.** Run the connectivity checks and the in-cluster probe from
   DEPLOYMENT-GUIDE §1.11a — the one that proves Databricks compute itself
   reaches the target systems.

---

## 5. Known operational notes

**Run `az` from PowerShell, not Git Bash.** Git Bash (MSYS) rewrites arguments
that look like Unix paths, so `--id /subscriptions/...` arrives mangled and Azure
rejects it. If you must use Git Bash, export `MSYS_NO_PATHCONV=1` first.

**`scripts/*.ps1` other than the SP script require PowerShell 7.2+** (`pwsh`).
Windows PowerShell 5.1 will refuse to run them. `New-GitHubOidcServicePrincipal.ps1`
is deliberately written for 5.1 as well, so a stock admin workstation can create
the identities without installing anything.

**Diagnostic settings can fail with "already exists" on a first apply.** The
azurerm provider creates the setting, gets a 404 reading it back (Azure is
eventually consistent here), retries, and collides with its own resource. The
resource *is* created correctly. Recovery is to import it, or delete it and
re-apply — not a configuration change.

**A green apply is not acceptance.** Anything driven by cloud-init needs runtime
proof: a fully successful `terraform apply` can still leave a dead HAProxy tier.
Check `systemctl is-active haproxy` and real TCP responses.
