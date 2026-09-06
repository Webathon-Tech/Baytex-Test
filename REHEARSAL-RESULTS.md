# Sandbox Rehearsal — Results

Record of deploying this platform end to end in an isolated sandbox
subscription, across three environments, and tearing it down again.

**Subscription:** `6a3bb170-5159-4bff-860b-aa74fb762697` (Contoso / MngEnvMCAP797847)
**Repository:** `Webathon-Tech/Baytex-Test`
**Dates:** 3–4 September 2026

---

## Outcome

All three environments — dev, test and prod — were deployed through GitHub
Actions, validated at **11/11 checks each (33/33 total)**, then destroyed through
a dedicated destroy pipeline. The mock on-premises environment was deliberately
retained.

The rehearsal exercised the one part of the architecture the original repository
recorded as unvalidated: the Databricks **Network Connectivity Configuration**
and the serverless path through Private Link to on-premises.

### Validation, per environment

| Check | dev | test | prod |
| --- | --- | --- | --- |
| Spoke-to-hub peering `Connected` | ✅ | ✅ | ✅ |
| Private DNS resolves on-prem sims | ✅ | ✅ | ✅ |
| Storage private endpoint on a private IP | `10.99.2.5` | `10.99.18.4` | `10.99.34.4` |
| Proxy VM 01 → SQL 1433 / Oracle 1521 | ✅ | ✅ | ✅ |
| Proxy VM 02 → SQL 1433 / Oracle 1521 | ✅ | ✅ | ✅ |
| HAProxy active on both nodes | ✅ | ✅ | ✅ |
| ILB frontend → on-prem (SQL) | ✅ | ✅ | ✅ |
| ILB frontend → on-prem (Oracle) | ✅ | ✅ | ✅ |

The last two are the ones that matter: real TCP traversing internal load
balancer → floating IP → HAProxy → route table → firewall NVA → simulated
on-premises host, returning `SIMULATED-SQL-OK` / `SIMULATED-ORACLE-OK`. That is
the serverless path, proven.

### Environment addressing

| | dev | test | prod |
| --- | --- | --- | --- |
| VNet | `10.99.0.0/20` | `10.99.16.0/20` | `10.99.32.0/20` |
| ILB frontends | `.2.75` / `.2.76` | `.18.75` / `.18.76` | `.34.75` / `.34.76` |
| Workspace | `adb-7405608282711431.11` | `adb-7405612160123647.7` | `adb-7405611598891423.3` |

Three structurally independent environments from one codebase with **no `.tf`
changes** — the property Baytex needs when each environment is its own
subscription.

---

## Defects found

Each of these would have surfaced during the Baytex deployment. None were
detectable by `fmt`, `validate` or `plan`.

### 1. Workflows were not in `.github/workflows/`

Both pipelines sat at the repository root, where GitHub Actions never runs them.
The repository documented the correct path in three places, and the plan
workflow's own path filter referenced it.

### 2. CRLF line endings in every committed blob

`.gitattributes` did not exist despite documentation claiming it had been added.
Anything a Linux guest executes breaks: a cloud-init shebang becomes
`#!/bin/bash\r` and never runs. The firewall NVA simulator would have forwarded
nothing while appearing deployed. Fixed by adding `.gitattributes` and
normalising all 62 text files.

### 3. `terraform fmt -check` ran after the tfvars secret was written

`terraform fmt` checks `.tfvars` files. Writing the secret first meant the gate
failed on the *formatting of secret content*, failing every run. Reordered.

### 4. GitHub OIDC subject format

The organisation emits subjects carrying immutable IDs:

```
repo:Webathon-Tech@269995634/Baytex-Test@1356511433:environment:dev-apply
```

not the classic `repo:<org>/<repo>:environment:<env>`. Presenting the wrong one
fails with `AADSTS700213`. Which form an organisation emits is not discoverable
in advance, so `New-GitHubOidcServicePrincipal.ps1` now registers **both**.

> This also answers what the Azure portal's *Organization ID* and *Repository ID*
> fields do. They cannot be stored on a subject-based credential — Microsoft
> Graph accepts and silently discards them. They exist only *inside* the
> immutable subject string, which is why the portal shows them blank when
> editing a credential created via API.

### 5. Storage Blob Data Contributor is required and is easily missed

A data-plane role that **neither Owner nor Contributor includes**. Without it
`terraform init` fails with 403 on the state blob even though the principal can
see the storage account. Hit twice: once for the deployment principals, once for
the interactive admin account.

### 6. DNS link name collision across environments

`Link-SandboxDnsToSpoke.ps1` hardcoded the link name `link-spoke`. Linking a
second environment found the first environment's link already present and
**silently skipped all three zones** — while reporting success. Test and prod
would have been unable to resolve either the on-premises hosts or their storage
endpoints. Now derived from the spoke VNet name.

*Only observable with more than one environment. The single strongest argument
for rehearsing test and prod rather than stopping at dev.*

### 7. Diagnostic settings report "already exists" on first apply

The azurerm provider creates the setting, reads it back before Azure is
consistent, retries, and collides with its own resource. The resource is created
correctly but is absent from state. Verified no Azure Policy was involved.
Recovery is to import or delete and re-apply — **not** a configuration change.

### 8. `terraform destroy` does not complete in one pass

Two independent causes, both fixed in `terraform-destroy.yml`:

- **NCC deletion.** Deleting the workspace binding and deleting the NCC are
  separate Databricks API calls, and the unbind is not immediately visible. The
  NCC delete fails with *"unable to be deleted because it is attached to one or
  more workspaces"*. The workflow now retries, re-planning between attempts.
- **Private Link Service deletion.** Azure refuses to delete a PLS that still has
  private endpoint connections, and the Databricks-managed endpoints outlive the
  NCC — they remain `Approved` against the PLS after the NCC is gone. The
  workflow now clears them before planning the destroy.

Without both fixes a destroy leaves the network and connectivity resource groups
behind, and the next apply collides on names that still exist.

### 9. Terraform version skew in CI

CI pinned 1.15.9 while the code was developed on 1.16.x. Terraform refuses to
read state written by a newer minor version, so one local apply would have made
the pipeline unusable. Now 1.16.1 everywhere.

---

## Pipelines

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `terraform-bootstrap-state.yml` | manual, per environment | Creates the state backend and migrates its own state into it |
| `terraform-deploy.yml` | manual, `dev`/`test`/`prod`/`all` | Deploys; `all` chains dev → test → prod and stops at first failure |
| `terraform-destroy.yml` | manual, per environment | Destroys one environment's platform |
| `terraform-plan-pr.yml` | pull request | Plan-only check |
| `_terraform-plan.yml` / `_terraform-apply.yml` | called | Reusable plan and apply of the exact plan |

### Properties verified, not assumed

- **Bootstrap idempotency.** Re-running took the remote path, skipped
  create/import/migrate, and `plan -detailed-exitcode` reported no changes.
- **Single-environment targeting.** Running `deploy_target: test` showed `dev-*`
  jobs **skipped** and only `test-*` executing.
- **Destroy confirmation guard.** Tested with a deliberately wrong value: refused
  at the first step, never authenticating to Azure. An earlier version of this
  test was a false positive — the step was failing on a missing working
  directory rather than the confirmation logic, which was then fixed.
- **Destroy completeness.** Each run asserts state is empty *and* that a further
  destroy plan reports no changes.

---

## Teardown state (as of 4 September 2026)

**Destroyed:** all three platform environments. Confirmed zero Databricks
workspaces, zero platform VMs, zero platform storage accounts.

**Retained deliberately:**

| Resource group | Why |
| --- | --- |
| `rg-sbx-hub-cnc-001` | Mock on-premises environment — hub VNet, firewall NVA sim, SQL/Oracle sim, DNS zones |
| `rg-sbx-dbx-{dev,test,prod}-tfstate-cnc-001` | State backends, so redeploying needs no re-bootstrap |

Also removed as part of cleanup, because Terraform never owned them: the three
**hub-side VNet peerings** and the spoke DNS zone links. In a Baytex deployment
these are customer-owned handoffs and must be removed through their change
process.

### On-premises environment confirmed working after teardown

```
nva_service=active
ip_forward=1
dns_sqlsim=10.98.1.4
sql_over_network=SIMULATED-SQL-OK
ora_over_network=SIMULATED-ORACLE-OK
```

---

## Redeploying

State backends and identities are intact, so:

1. **Actions → Terraform Deploy → `deploy_target: dev`** (or `all`).
2. Post-apply, per environment:
   - hub-side peering: `az network vnet peering create ... --name peer-hub-to-<spoke>`
   - `.\sandbox\Link-SandboxDnsToSpoke.ps1 -SpokeVnetName <spoke> -SpokeResourceGroup <rg>`
   - approve the 4 NCC private endpoints (2 storage, 1 per PLS)
   - `.\sandbox\Invoke-SandboxValidation.ps1` with that environment's addressing

No bootstrap re-run and no service principal work is needed.

---

## Still outstanding

- **`Approve-BaytexDatabricksPrivateEndpoints.ps1` is unexercised.** It declares
  `#Requires -Version 7.2` and `pwsh` is not installed on the rehearsal
  workstation, so endpoints were approved with `az` instead. Nothing in the
  script appears to need 7.2.
- **`existing_metastore_id` is `TO-BE-CONFIRMED`.** It only feeds an output. The
  value could not be read because the interactive admin account is not
  provisioned into the workspaces (403).
- **Approval gates are not active.** Deployment protection rules need GitHub Pro,
  Team or Enterprise on a private repository. The environments exist and scope
  secrets correctly; attaching reviewers to `test-apply` and `prod-apply`
  requires no workflow change.
- **Run `az` from PowerShell, not Git Bash.** MSYS rewrites arguments that look
  like Unix paths, so `--remote-vnet /subscriptions/...` arrives mangled. Setting
  `MSYS_NO_PATHCONV=1` fixes that but then breaks `--scripts "@/tmp/file"`, which
  relies on the conversion. Using PowerShell avoids both.
