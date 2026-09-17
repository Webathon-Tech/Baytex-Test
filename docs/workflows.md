# Workflows

How the GitHub Actions pipelines are built, when they run, and how to run, approve and troubleshoot them.

For the one-time configuration of identities, GitHub Environments, variables and protection rules, see
[GitHub setup](github-setup.md).

---

## 1. At a glance

| Workflow | What it does | When it runs | Produces |
| --- | --- | --- | --- |
| **Terraform Pull Request Checks** | Formats and validates every change, and plans the environments or state backends it affects. Never applies. | Automatically, on every pull request | A plan per affected environment for the reviewer |
| **Terraform Bootstrap State Backend** | Creates the Azure storage account that holds an environment's Terraform state | Manually, once per environment; safe to re-run | The state backend and its settings |
| **Terraform Deploy Platform** | Builds or updates the platform | Manually, whenever a change is promoted | The deployed environment and its outputs |
| **Terraform Destroy Platform** | Tears an environment down | Manually, rarely | An empty environment; the state backend is kept |
| **Terraform Unlock State** | Releases a state lock left behind by a cancelled or killed run | Manually, only after such a run | The released lock and an audit record |

Five further workflows, named **`Reusable - ...`**, are building blocks called by the five above. They cannot be run
directly.

### The order things happen in

```
      once per environment                    every change
      ────────────────────                    ────────────

      Bootstrap State Backend      →     Pull Request Checks  (automatic)
      (creates somewhere for                      ↓
       state to live)                     Deploy Platform     (manual)
                                                  ↓
                                          Destroy Platform    (only to tear down)
```

---

## 2. The model

Every workflow that changes Azure is split into **two jobs in two GitHub Environments**:

```
   Plan dev platform                  Apply dev platform
   ─────────────────                  ──────────────────
   GitHub Environment:                GitHub Environment:
       dev-plan                           dev-apply
                                          ▲
   Runs terraform plan.               THE APPROVAL GATE LIVES HERE
   Saves the plan as a file.
   Uploads it as an artefact.  ────►  Downloads that exact file
                                      and applies it. Never re-plans.
```

**The approval gate has one home.** Required reviewers on `dev-apply`, `test-apply` or `prod-apply` pause every workflow
that changes that environment: deploy, destroy, bootstrap and unlock.

**What is approved is what runs.** The apply job applies the saved binary plan. Nothing can change between the plan a
reviewer read and the actions Azure receives.

**A plan cannot change anything.** Plan jobs run in their own environment, so running a plan never needs approval.

**Destroy is reviewable.** It uses the same two jobs with `terraform plan -destroy`, so a teardown is read and approved
exactly like a deployment.

### Which branches may apply

| Workflow | Allowed branches | Reason |
| --- | --- | --- |
| Deploy | `main`, `hotfix/*` | Routine promotion, plus an emergency path |
| Bootstrap | `main`, `hotfix/*` | It applies Terraform, so the same rule applies |
| Destroy | **`main` only** | A teardown is never an emergency fix |
| Unlock | **`main` only** | A recovery runs from reviewed code |

Feature branches can never apply. The branch is checked in the `Check the run is allowed` job before Azure is touched,
and again inside the apply job.

---

## 3. Running each workflow

All manual workflows start the same way:

> **Actions** tab → select the workflow → **Run workflow** → choose the branch → tick environments → **Run workflow**

### 3.1 Bootstrap the state backend

**Run this first for each environment.** Deploy refuses to run until the environment has a state backend.

| Setting | Value |
| --- | --- |
| Inputs | `dev`, `test`, `prod` checkboxes, in any combination |
| Branch | `main` or `hotfix/*` |
| Duration | 2–4 minutes per environment |
| Safe to re-run | Yes; a re-run against an existing backend changes nothing |

**Jobs**

```
Check the run is allowed
Plan dev bootstrap storage account (state backend)    ← in dev-plan
Apply dev bootstrap storage account (state backend)   ← in dev-apply, pauses here if reviewers are set
```

**The plan names a mode**

| Mode | Meaning |
| --- | --- |
| `create` | Nothing exists yet. Normal for a first run. |
| `import` | The storage account exists but is not in state. The apply adopts it rather than recreating it. |
| `remote` | The backend exists and is tracked. Expect "No changes". |

> **Read this plan before approving.** The storage account holds the Terraform state for the whole environment. If the
> plan says `must be replaced` or `will be destroyed`, the summary's **Replaces or destroys** row says so, and approving
> it can destroy the state file. Stop and investigate.

**When it finishes**, the summary shows the storage account, container and state key the platform workflows use.

### 3.2 Deploy the platform

| Setting | Value |
| --- | --- |
| Inputs | `dev`, `test`, `prod` checkboxes |
| Branch | `main`, or `hotfix/*` for emergencies |
| Duration | 20–30 minutes per environment |
| Prerequisite | The environment's state backend exists |

**Promotion order is enforced.** Ticked environments run in the order dev → test → prod, and each waits for the previous
ticked environment to apply successfully. With dev and prod ticked, prod waits for dev. If dev fails, nothing after it
runs.

**Jobs on a full run**

```
Check the run is allowed
Plan dev platform     →  Apply dev platform      ← gate
Plan test platform    →  Apply test platform     ← gate
Plan prod platform    →  Apply prod platform     ← gate
```

**Approving.** When a run reaches a gated apply job, GitHub shows *Review pending deployments* at the top of the run.
Read the plan in the summary of the matching **Plan** job, then **Approve and deploy** or **Reject**.

The plan summary gives the result line and a **Replacements** count. Anything other than `none` means a resource will be
deleted and recreated; find out which one, and why, before approving.

**Before the apply**, the job removes the private endpoint connections of any Private Link Service the approved plan
deletes, in its **Clear connections from Private Link Services the plan removes** step. Deleting an NCC rule whose
connection is established only deactivates it, and Databricks keeps its private endpoint for seven days, while Azure
refuses to delete a Private Link Service that still has a connection. This is what lets a deploy remove an on-premises
destination in one pass; a plan that removes no Private Link Service is not affected.

**After the apply**, the job approves the Databricks private endpoint connections in its
**Approve the NCC private endpoint connections** step. Databricks creates a private endpoint for every NCC rule, to the
data storage account or to a Private Link Service, and serverless compute cannot use it until the connection is
approved. The step reads the endpoint names from the outputs of the apply, approves the pending connections that match,
leaves approved connections unchanged and reports any other connection without changing it. It waits up to 20 minutes
for endpoints Databricks is still creating, so a deploy that adds an on-premises destination finishes with its
connection approved. The details are in the [deployment runbook](deployment-runbook.md#gate-5--private-link-approvals).

**When it finishes**, the summary lists the workspace URL and ID, the data storage account, the NAT Gateway public IP
and the number of private endpoint connections approved.

### 3.3 Destroy an environment

| Setting | Value |
| --- | --- |
| Inputs | `dev`, `test`, `prod` checkboxes, plus **`confirm`** |
| Branch | **`main` only** |
| Duration | 15–25 minutes per environment |

**The `confirm` box.** Type the ticked environments exactly, comma-separated, in the order `dev,test,prod`, with no
spaces:

| Ticked | Type into `confirm` |
| --- | --- |
| dev | `dev` |
| dev and prod | `dev,prod` |
| all three | `dev,test,prod` |

Anything else is refused before Azure is touched, so a mis-clicked checkbox cannot destroy an environment.

**What is not destroyed**

- The **state backend**, so Deploy can rebuild the environment without bootstrapping again
- The **hub VNet, firewall and on-premises systems**, which this Terraform does not own
- A **hub-side peering created outside Terraform**, when `create_hub_to_spoke_peering` is `false`

Peerings Terraform created, in either direction, are destroyed with the environment. A hub-side peering created outside
Terraform shows as `Disconnected` once its spoke is destroyed; the hub owner deletes it, and after the next deploy peers
the new VNet with the command in the `hub_side_peering_command` output.

**When it finishes**, the summary shows how many resources were destroyed and confirms that none remain.

### 3.4 Pull request checks

The workflow starts itself when a pull request is opened or updated.

| Job | What it means |
| --- | --- |
| `Validate Terraform code` | Formatting and syntax across every environment and bootstrap root. Must be green. Always runs. |
| `Detect changed areas` | Decides which of the checks below apply to the change. Always runs. |
| `Check environment root parity` | **Reports only.** Shows where `environments/dev`, `test` and `prod` differ. |
| `Check bootstrap root parity` | The same, for the three `bootstrap/` roots. |
| `Plan dev / test / prod platform (review only)` | What the change would do to each environment. |
| `Plan dev / test / prod bootstrap storage account (review only)` | What the change would do to each **state backend**. |

Which checks run depends on what the pull request changed:

| Change in | Checks that run |
| --- | --- |
| `environments/**` | Validate, detect, environment parity, the three platform plans |
| `modules/**` | Validate, detect, the three platform plans |
| `bootstrap/**` | Validate, detect, bootstrap parity, the three bootstrap plans |
| Anything else — docs, workflows, scripts | Validate and detect only |

A check that does not apply shows as **Skipped**, which does not block a merge. All three environments are planned
because a change can be valid for one and break another.

An environment that is not ready shows a **skipped** plan with a note, rather than a failure:

| State | What the plan reports |
| --- | --- |
| **No service principal yet** — the environment's `AZURE_*` and `TF_STATE_*` variables are unset | `not configured yet`, listing the missing variables |
| **Not bootstrapped yet** — configured, but no state backend exists | `skipped`, naming the storage account it looked for |

This lets environments be onboarded one at a time. A **deploy, destroy or bootstrap** run still fails for an
unconfigured environment, because it names the environment explicitly, and the message lists the missing variables.

**State backend plans** run only when a pull request changes `bootstrap/**`. Each storage account holds its environment's
Terraform state, so a change that forces replacement would destroy the state it is tracked in.

> If a state backend plan says `must be replaced` or `will be destroyed`, stop and investigate before merging.

Pull request plans are review-only: no binary plan is uploaded, so nothing a pull request produces can be applied.

### 3.5 Release a stuck state lock

| Setting | Value |
| --- | --- |
| Inputs | `environment`, `lock_id`, and `confirm` (the environment name again) |
| Branch | **`main` only** |
| Duration | About a minute |

Use this only when a run was cancelled or killed mid-apply and a later run fails with `Error acquiring the state lock`.
Copy the lock ID from that error, and confirm from its `Created` time and `Operation` that the run holding it has
stopped. The unlock runs in the `<env>-apply` environment, so the reviewers who gate a deployment also gate a recovery.

The lock ID is checked against the lock actually held, so a stale or mistyped ID releases nothing. The summary says
whether the lock was released.

A lock left by a run from a workstation is released by that user, as described in [Local runs](local-runs.md#8-release-a-stuck-lock).

---

## 4. Scenarios

### A new environment

1. Complete [GitHub setup](github-setup.md) for the environment
2. Run **Terraform Bootstrap State Backend** for the environment
3. Run **Terraform Deploy Platform** for the same environment
4. Approve the apply when it pauses
5. Complete the handoffs in the [deployment runbook](deployment-runbook.md); the deploy has already approved the
   Databricks private endpoint connections

### A routine change

1. Branch from `main`, make the change and push
2. Open a pull request; the checks run automatically
3. Review and merge
4. Run **Terraform Deploy Platform** from `main`, ticking dev first
5. Once dev is verified, run it for test, then prod — or tick all three and approve at each gate

A change to an environment's values is made in its `TFVARS` variable rather than in git, followed by a deploy of that
environment.

### A hotfix

When `main` has moved on and only one fix must reach production:

```bash
git checkout -b hotfix/urgent-fix <last-known-good-commit>
git cherry-pick <the-one-fix>
git push -u origin hotfix/urgent-fix
```

Run **Terraform Deploy Platform** with the branch set to `hotfix/urgent-fix`, then merge the same fix into `main`, or the
next deploy will revert it.

### A rollback

Roll forward: revert the commit on `main`, merge it and deploy again. The plan shows the change being undone, and a
reviewer sees it before it applies.

### Re-running after a failure

Use **Re-run failed jobs** only when the cause was transient and the failed job changed nothing in Azure, because a
re-run reuses the plan the original run saved. When an apply failed part-way, or the code or variables changed, start a
new run so it plans against the current state.

### Concurrent runs

Deploy, Destroy and Unlock share one concurrency group, so a second run **queues** until the first finishes. Two applies
against one state file would contend for the lock. Bootstrap runs have their own group.

Pull request plans run with `-lock=false` because they never write state, so any number of pull requests can be open at
once.

---

## 5. Evidence and audit

Every job that touches Azure uploads an artefact, **including when it fails**.

| Produced by | Artefact | Contains | Kept |
| --- | --- | --- | --- |
| Validate | `evidence-validate-<run>` | Validation output | 14 days |
| Pull request plan | `evidence-plan-<env>-<run>` | The plan text | 14 days |
| Pull request state backend plan | `evidence-bootstrap-plan-<env>-<run>` | The plan text and detected mode | 14 days |
| Deploy plan | `tfplan-deploy-<env>-<run>` | Binary plan, plan text, provider lock | 5 days |
| Deploy apply | `evidence-deploy-<env>-<run>` | Plan, apply log, outputs, private endpoint approval log, final state list | **30 days** |
| Destroy plan | `tfplan-destroy-<env>-<run>` | Binary plan, plan text, state before | 5 days |
| Destroy apply | `evidence-destroy-<env>-<run>` | Plan, apply log, state before and after | **30 days** |
| Bootstrap plan | `tfplan-bootstrap-<env>-<run>` | Binary plan, plan text, detected mode | 5 days |
| Bootstrap apply | `evidence-bootstrap-<env>-<run>` | Plan, apply log, state list, backend settings | **30 days** |
| Unlock | `evidence-unlock-<env>-<run>` | Unlock log | 14 days |

`tfplan-*` artefacts pass a plan from a plan job to its apply job. `evidence-*` artefacts are the record.

Every artefact contains **`run-metadata.json`**: the commit SHA, branch, run ID and attempt, the person who triggered it,
the Terraform version, the timestamp and a link to the run. It answers what changed, when, from which commit and who
approved it, after the logs themselves have expired.

Download artefacts from the bottom of a run's summary page.

---

## 6. Troubleshooting

| What you see | What it means | What to do |
| --- | --- | --- |
| `No Terraform state backend for '<env>'` | The environment was never bootstrapped | Run **Terraform Bootstrap State Backend** for it |
| `Refusing to deploy from 'refs/heads/...'` | The run was started from a feature branch | Merge to `main`, or use a `hotfix/*` branch |
| `Refusing to destroy from ...` | Destroy was started from a branch other than `main` | Run destroy from `main` |
| `Confirmation '...' does not match` | The `confirm` box does not match the ticked boxes | Retype exactly, for example `dev,prod` |
| `Environment '<env>' is not configured. Missing: ...` | A deploy, destroy or bootstrap was started for an environment without its variables | Set them — [GitHub setup](github-setup.md) §2 and §4 |
| A pull request plan says `not configured yet` | Expected before that environment's service principal exists | Nothing; it plans once §2 and §4 are complete |
| `TFVARS is empty for <env>-plan` | The variable is missing on that GitHub Environment | Set it — [GitHub setup](github-setup.md) §4 |
| Plan fails with `Invalid value for variable` | A `TFVARS` value breaks an input rule in `variables.tf`, such as an address outside its subnet or a peering flag without `hub_vnet_id` | Correct the value the error message names |
| Plan shows the workspace **must be replaced** | A setting fixed at creation changed: the workspace name, managed resource group, VNet, subnets, root storage account name, infrastructure encryption or default storage firewall. Tags and other settings update in place | Find which setting changed before approving |
| Apply fails with `LinkedAuthorizationFailed` for `Microsoft.Network/virtualNetworks/peer/action` | `create_spoke_to_hub_peering` is `true`, but the service principal has no role on the hub VNet | Grant Network Contributor on the hub VNet ([GitHub setup](github-setup.md#optional-roles-in-the-hub-subscription)), or set the flag to `false` |
| Apply fails with `AuthorizationFailed` for `Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write` | `create_hub_to_spoke_peering` is `true`, but the service principal has no role on the hub VNet | Grant Network Contributor on the hub VNet, or set the flag to `false` |
| Apply fails with `LinkedAuthorizationFailed` for `Microsoft.Network/privateDnsZones/join/action` | DNS zone IDs are set, but the service principal has no role on those zones | Grant Private DNS Zone Contributor on each zone, or set `blob_private_dns_zone_ids` and `dfs_private_dns_zone_ids` to `[]` |
| A hub-side peering created outside Terraform shows `Disconnected` | The spoke VNet was destroyed and rebuilt | The hub owner deletes the old peering and peers the new VNet with the command in the `hub_side_peering_command` output |
| Destroy log shows `cannot delete mws network connectivity config ... attached to one or more workspaces`, then succeeds | Expected: unbinding and deleting the NCC are separate Databricks calls, and the unbind takes a moment to register | Nothing; the apply retries automatically and `apply.log` records each attempt |
| A HAProxy VM needs inspecting | SSH is closed unless `admin_ssh_source_cidrs` is set | Run `az vm run-command invoke -g <rg> -n <vm> --command-id RunShellScript --scripts "systemctl status haproxy"`; it needs only Virtual Machine Contributor |
| HAProxy is not running on a VM, or a HAProxy health probe alert is raised | The VM installs HAProxy once the package mirrors are reachable through the hub peering and the firewall rule, and retries every two minutes, including after a restart | Complete the peering and the firewall rule; follow progress with `az vm run-command invoke -g <rg> -n <vm> --command-id RunShellScript --scripts "journalctl -u baytex-haproxy-reconcile -n 30 --no-pager"` |
| A change to `on_prem_endpoints` or `dns_servers` has not reached HAProxy | The VMs apply user data changes within about two minutes, and keep the running configuration when `haproxy -c` rejects the new one | Read the same journal; a rejected configuration is kept at `/var/lib/baytex-haproxy/rejected-haproxy.cfg` for inspection |
| HAProxy starts again after being stopped for maintenance | The reconcile service keeps HAProxy running | Stop `baytex-haproxy-reconcile.timer` before stopping HAProxy, and start the timer again afterwards |
| Serverless compute cannot reach an on-premises name or the data storage | A Databricks private endpoint connection is not approved, or its rule is not `ESTABLISHED` yet | Read `approve-private-endpoints.log` in the deploy's evidence bundle, and run the approval script as described in the [deployment runbook](deployment-runbook.md#gate-5--private-link-approvals) |
| **Approve the NCC private endpoint connections** fails with exit code `3` | An expected private endpoint did not appear on its target within 20 minutes, or a rule in the outputs has no endpoint name | Check the rule's state in the Databricks account console. When it is still being created, start a new **Terraform Deploy Platform** run for the environment: its plan has nothing to change, and the step approves the connection once it appears. **Re-run failed jobs** does not help here, because the saved plan has already been applied |
| **Approve the NCC private endpoint connections** fails with exit code `4` | An expected connection was rejected or disconnected, which Azure does not allow to be approved | Recreate the matching NCC rule so Databricks raises a fresh connection, then deploy again |
| `Error acquiring the state lock` | Another run holds the lock | Wait; runs queue by design. If a run was killed mid-apply, release the lock with **Terraform Unlock State** (§3.5) |
| A run is queued behind another | Deploy, Destroy and Unlock share a concurrency group | Expected; it starts when the other run finishes |

---

## 7. Reference

### Workflow inputs

| Workflow | Input | Type | Notes |
| --- | --- | --- | --- |
| Bootstrap | `dev` / `test` / `prod` | Checkbox | Any combination; independent of each other |
| Deploy | `dev` / `test` / `prod` | Checkbox | Any combination; run in promotion order |
| Destroy | `dev` / `test` / `prod` | Checkbox | Any combination; independent of each other |
| Destroy | `confirm` | Text | Must equal the ticked list, for example `dev,prod` |
| Unlock | `environment` | Choice | `dev`, `test` or `prod` |
| Unlock | `lock_id` | Text | The lock ID from the failed run's error message |
| Unlock | `confirm` | Text | Must equal the selected environment |

### Workflow files

| File | Role |
| --- | --- |
| `terraform-pull-request.yml` | Entry point — automatic checks on pull requests |
| `terraform-bootstrap.yml` | Entry point — create the state backend |
| `terraform-deploy.yml` | Entry point — deploy the platform |
| `terraform-destroy.yml` | Entry point — tear an environment down |
| `terraform-unlock.yml` | Entry point — release a state lock left by a killed run |
| `_terraform-validate.yml` | Reusable — format check and validate, without credentials |
| `_terraform-plan.yml` | Reusable — plan a deploy or destroy in `<env>-plan` |
| `_terraform-apply.yml` | Reusable — apply a saved plan in `<env>-apply` |
| `_bootstrap-plan.yml` | Reusable — plan the state backend in `<env>-plan` |
| `_bootstrap-apply.yml` | Reusable — apply and migrate state in `<env>-apply` |

The platform reusable workflows take an `operation` of `deploy` or `destroy`, so one pair of files serves both.

### GitHub Environments

| Environments | Purpose | Approval |
| --- | --- | --- |
| `dev-plan`, `test-plan`, `prod-plan` | Run `terraform plan` | Never gated |
| `dev-apply`, `test-apply`, `prod-apply` | Run `terraform apply` | **Attach reviewers here** |

### Versions

| Component | Version |
| --- | --- |
| Terraform | 1.16 |
| `hashicorp/azurerm` provider | 5.5 |
| `Azure/azapi` provider | 2.12 |
| `databricks/databricks` provider | 1.131 |
| HAProxy VM image | Ubuntu 26.04 LTS |
| `actions/checkout` | v7 |
| `actions/upload-artifact` | v7 |
| `actions/download-artifact` | v8 |
| `azure/login` | v3 |
| `hashicorp/setup-terraform` | v4 |

Every workflow installs the Terraform version in the `TERRAFORM_VERSION` repository variable, so changing the version is
one edit in the repository settings. Provider lock files are not committed; each run installs the newest provider
release within the constraints in `versions.tf`.
