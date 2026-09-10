# Workflows — Operator Guide

How the GitHub Actions pipelines are built, when they run, and how to run them.

For one-time repository configuration — service principals, environments,
variables, protection rules — see **[GITHUB-SETUP.md](GITHUB-SETUP.md)**.

---

## 1. At a glance

| Workflow | What it does | When it runs | Who starts it | Produces |
| --- | --- | --- | --- | --- |
| **Terraform Pull Request Checks** | Formats, validates, and plans all three environments. Never applies. | Automatically, on every pull request | Nobody — it is automatic | A plan per environment for the reviewer |
| **Terraform Bootstrap State Backend** | Creates the Azure storage account that holds Terraform state | Manually, once per environment (and safe to re-run) | Platform engineer | The state backend, plus its configuration |
| **Terraform Deploy Platform** | Builds or updates the Databricks platform | Manually, whenever a change is promoted | Platform engineer | The deployed environment, plus outputs |
| **Terraform Destroy Platform** | Tears an environment down | Manually, rarely | Platform engineer | An empty environment (backend kept) |

There are also five workflows whose names begin with **`Reusable -`**. They are
building blocks called by the four above. **Do not run them directly** — they
will not appear with a "Run workflow" button.

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

## 2. The model, in one page

Every workflow that changes Azure is split into **two jobs in two different
GitHub Environments**:

```
   Plan dev deployment                Apply dev deployment
   ───────────────────                ────────────────────
   GitHub Environment:                GitHub Environment:
       dev-plan                           dev-apply
                                          ▲
   Runs Terraform plan.               THE APPROVAL GATE LIVES HERE
   Saves the plan as a file.
   Uploads it as an artefact.  ────►  Downloads that exact file
                                      and applies it. Never re-plans.
```

Four consequences worth understanding:

**The approval gate has one home.** Attach required reviewers to `dev-apply`,
`test-apply` or `prod-apply` and *every* workflow that changes that environment
pauses — deploy, destroy **and** bootstrap. You do not configure it three times.

**What is approved is what runs.** The apply job applies a saved binary plan. It
does not re-run `terraform plan` after approval, so nothing can change between
the plan a reviewer read and the actions Azure receives.

**A plan cannot change anything.** The plan jobs are separated into their own
environment precisely so they can hold credentials that only need to read, and so
that running a plan is never a decision anybody has to approve.

**Destroy is not special.** It uses the same two jobs; the only difference is
`terraform plan -destroy` instead of `terraform plan`. So a destroy is reviewable
before it happens, in exactly the same way a deployment is.

### Which branches may apply

| Workflow | Allowed branches | Reason |
| --- | --- | --- |
| Deploy | `main`, `hotfix/*` | Routine promotion, plus an emergency path |
| Bootstrap | `main`, `hotfix/*` | It applies Terraform, so the same rule |
| Destroy | **`main` only** | A teardown is never the urgent action a hotfix exists for |

Feature branches can never apply anything. This is checked twice — once in the
`Check the run is allowed` job before Azure is touched, and again inside the
apply job itself.

---

## 3. Running each workflow

All manual workflows are started the same way:

> **Actions** tab → pick the workflow in the left sidebar → **Run workflow** →
> choose the branch → tick environments → **Run workflow**

### 3.1 Bootstrap the state backend

**Run this first.** Until it has completed for an environment, Deploy will refuse
to run, because there is nowhere to keep Terraform state.

| | |
| --- | --- |
| Inputs | `dev`, `test`, `prod` checkboxes — tick any combination |
| Branch | `main` (or `hotfix/*`) |
| Duration | 2–4 minutes per environment |
| Safe to re-run | Yes — a re-run against an existing backend is a no-op |

**Jobs you will see**

```
Check the run is allowed
Plan dev bootstrap storage account   ← in dev-plan
Apply dev state backend      ← in dev-apply, pauses here if reviewers are set
```

**What the plan tells you.** The summary names a **mode**:

| Mode | Meaning |
| --- | --- |
| `create` | Nothing exists yet. Normal for a first run. |
| `import` | The storage account exists but Terraform does not track it. The apply adopts it into state rather than trying to recreate it. |
| `remote` | The backend exists and is already tracked. A re-run; expect "No changes". |

> **Read the plan before approving this one.** The storage account it manages
> holds the Terraform state for the whole environment. If the plan says
> `must be replaced` or `will be destroyed`, the summary puts a warning at the
> top. Approving that can destroy the state file. Stop and ask.

**When it finishes** the summary prints the backend configuration and confirms
that a re-run produces no changes.

### 3.2 Deploy the platform

| | |
| --- | --- |
| Inputs | `dev`, `test`, `prod` checkboxes |
| Branch | `main` (or `hotfix/*` for emergencies) |
| Duration | 20–30 minutes per environment |
| Prerequisite | The environment's state backend must exist |

**Promotion order is enforced.** Whatever you tick runs in the order
dev → test → prod, and each stage waits for the previous ticked stage to apply
successfully. Tick dev and prod with test unticked, and prod still waits for dev.
If dev fails, nothing after it runs.

**Jobs on a full run**

```
Check the run is allowed
Plan dev deployment     →  Apply dev deployment      ← gate
Plan test deployment    →  Apply test deployment     ← gate
Plan prod deployment    →  Apply prod deployment     ← gate
```

**Approving.** When a run reaches a gated apply job, GitHub shows
*"Review pending deployments"* at the top of the run. Open it, read the plan in
the job summary of the matching **Plan** job above, then **Approve and deploy**
or **Reject**.

> You cannot approve your own deployment in some configurations. If the button is
> missing on a run you started, that is why — a second reviewer is needed.

**When it finishes** the summary lists the workspace URL, the data storage
account, the NAT public IP and the peering ID.

### 3.3 Destroy an environment

| | |
| --- | --- |
| Inputs | `dev`, `test`, `prod` checkboxes, plus **`confirm`** |
| Branch | **`main` only** |
| Duration | 15–25 minutes per environment |

**The `confirm` box.** Type the ticked environments exactly, comma-separated, in
the order `dev,test,prod`, with no spaces:

| Ticked | Type into `confirm` |
| --- | --- |
| dev | `dev` |
| dev and prod | `dev,prod` |
| all three | `dev,test,prod` |

Anything else is refused before Azure is touched. This exists so that a
mis-clicked checkbox cannot destroy an environment you did not mean to name.

**What is *not* destroyed**

- The **state backend** — kept deliberately, so Deploy can rebuild the
  environment without bootstrapping again
- The **hub VNet, firewall and on-premises systems** — this Terraform never
  owned them
- The **hub side of the VNet peering** — customer-owned

That last one matters. It survives pointing at a VNet that no longer exists, and
will block the peering from being recreated on the next deploy with
`RemotePeeringIsDisconnected`. The apply job's summary prints the exact
`az network vnet peering delete` command. Run it if the spoke is gone for good.

### 3.4 Pull request checks

Nothing to run — it starts itself when a pull request is opened or updated.

**What a reviewer should look at**

| Job | What it means |
| --- | --- |
| `Validate Terraform code` | Formatting and syntax across every deployed root. Must be green. Always runs. |
| `Detect changed areas` | Decides which of the checks below have anything to say about this change. Always runs. |
| `Check environment root parity` | **Reports only, never fails.** Flags where `environments/dev`, `test` and `prod` have drifted. |
| `Check bootstrap root parity` | The same, for the three `bootstrap/` roots. |
| `Plan dev / test / prod platform (review only)` | What this change would do to each environment. |
| `Plan dev / test / prod bootstrap storage account (review only)` | What it would do to the **state backend**. |

Which of them run depends on what the pull request touched:

| Change in | Checks that run |
| --- | --- |
| `environments/**` | validate, detect, environment parity, the three platform plans |
| `modules/**` | validate, detect, the three platform plans |
| `bootstrap/**` | validate, detect, bootstrap parity, the three bootstrap plans |
| Anything else — docs, workflows, scripts | validate and detect only |

A check that does not apply shows as **Skipped**, which does not block a merge.

Planning all three matters: the environment roots are separate copies of the same
files, so a change can be valid for dev and break prod.

An environment that is not ready yet shows a **skipped** plan with a note saying
why, rather than a failure. There are two such cases:

| State | What the plan reports |
| --- | --- |
| **No service principal yet** — the environment's `AZURE_*` and `TF_STATE_*` variables are unset | `not configured yet`, listing the missing variables |
| **Not bootstrapped yet** — configured, but no state backend exists | `skipped`, naming the storage account it looked for |

This is what lets you roll out one environment at a time. Configure and verify
dev first; `test` and `prod` report as not configured until you create their
service principals, and start planning for real the moment you do — no workflow
change is needed.

A **deploy, destroy or bootstrap** run still fails for an unconfigured
environment. Those name the environment explicitly, so missing configuration is a
genuine error rather than something to skip past, and the message lists exactly
which variables are missing.

### The state backend plans

These run **only when the pull request changes** `bootstrap/**`,
`.github/workflows/_bootstrap-*.yml` or `.github/workflows/terraform-bootstrap.yml`.
On any other pull request they are skipped and the
`Check whether the state backend changed` job says so — planning an unchanged root
three more times would add minutes to every pull request and could only report
"No changes".

This is the most important review on that root. The storage account it manages
holds the Terraform state for **every** environment, so a change that forces
replacement would destroy the state it is tracked in. Before this check existed
that was only visible once somebody ran the bootstrap workflow by hand.

> If a state backend plan says `must be replaced` or `will be destroyed`, stop and
> investigate before merging — not just before approving the bootstrap run.

They are review-only: no binary plan is uploaded, so nothing a pull request
produces can be applied.

---

## 4. Scenarios

### A brand-new environment, from nothing

1. Complete the setup in [GITHUB-SETUP.md](GITHUB-SETUP.md) for that environment
2. **Terraform Bootstrap State Backend** — tick the environment
3. **Terraform Deploy Platform** — tick the same environment
4. Approve the apply when it pauses

### A routine change

1. Branch from `main`, make the change, push
2. Open a pull request → checks run automatically
3. Get the review, merge
4. **Terraform Deploy Platform** from `main`, ticking dev first
5. Once dev looks right, run again for test, then prod — or tick all three and
   approve at each gate

### A hotfix

When `main` has moved on and you need only one fix in production:

```bash
git checkout -b hotfix/urgent-fix <last-known-good-commit>
git cherry-pick <the-one-fix>
git push -u origin hotfix/urgent-fix
```

Then run **Terraform Deploy Platform** with the branch set to `hotfix/urgent-fix`.
Merge the same fix back into `main` afterwards, or the next deploy will revert it.

### A rollback

There is no rollback button. Roll **forward**: revert the commit on `main`, merge
it, and deploy again. The plan will show the change being undone, and a reviewer
sees it before it applies — which a one-click rollback would not give you.

### Re-running after a failure

Use **Re-run failed jobs** only when the cause was transient. If the code or the
variables changed, start a fresh run: a re-run reuses the same `run_id`, and the
apply job refuses any plan that did not come from its own run.

### Two people at once

Deploy and Destroy share one concurrency group, so a second run **queues** rather
than running alongside the first. This is deliberate — two applies against one
state file would fight over the lock.

Pull-request plans are exempt: they run with `-lock=false` because they never
write state, so any number of pull requests can be open without contending.

---

## 5. Evidence and audit

Every job that touches Azure uploads an artefact, **including when it fails** —
a failed apply is exactly the run somebody needs to reconstruct later.

| Produced by | Artefact | Contains | Kept |
| --- | --- | --- | --- |
| Validate | `evidence-validate-<run>` | Validation output | 14 days |
| PR plan | `evidence-plan-<env>-<run>` | The plan text | 14 days |
| PR state backend plan | `evidence-bootstrap-plan-<env>-<run>` | The plan text and detected mode | 14 days |
| Deploy plan | `tfplan-deploy-<env>-<run>` | Binary plan, plan text, provider lock | 5 days |
| Deploy apply | `evidence-deploy-<env>-<run>` | Plan, apply log, outputs, final state list | **30 days** |
| Destroy plan | `tfplan-destroy-<env>-<run>` | Binary plan, plan text, state before | 5 days |
| Destroy apply | `evidence-destroy-<env>-<run>` | Plan, apply log, state before and after | **30 days** |
| Bootstrap plan | `tfplan-bootstrap-<env>-<run>` | Binary plan, plan text, detected mode | 5 days |
| Bootstrap apply | `evidence-bootstrap-<env>-<run>` | Plan, apply log, state list, backend config | **30 days** |

`tfplan-*` artefacts are working files handed from a plan job to its apply job.
`evidence-*` artefacts are the record.

Every artefact contains **`run-metadata.json`**: the commit SHA, branch, run ID
and attempt, who triggered it, the Terraform version, the timestamp, and a link
back to the run. That is what makes an artefact still meaningful once the logs
have expired — hand this to an auditor and it answers "what changed, when, from
which commit, approved by whom".

Download artefacts from the bottom of any run's summary page.

---

## 6. Troubleshooting

| What you see | What it means | What to do |
| --- | --- | --- |
| `No Terraform state backend for '<env>'` | The environment was never bootstrapped | Run **Terraform Bootstrap State Backend** for it |
| `Refusing to deploy from 'refs/heads/...'` | You started a run from a feature branch | Merge to `main`, or use a `hotfix/*` branch |
| `Refusing to destroy from ...` | Destroy was started from a non-`main` branch | Destroy runs from `main` only |
| `Confirmation '...' does not match` | The `confirm` box does not match the ticked boxes | Retype exactly, e.g. `dev,prod` |
| `Environment '<env>' is not configured. Missing: ...` | You asked to deploy, destroy or bootstrap an environment with no service principal | Create it and set the variables — [GITHUB-SETUP.md](GITHUB-SETUP.md) §2 and §4 |
| A pull-request plan says `not configured yet` | Expected before that environment's service principal exists | Nothing. It starts planning once §2 and §4 are done |
| `TFVARS is empty for <env>-plan` | The variable is missing on that environment | See [GITHUB-SETUP.md](GITHUB-SETUP.md) §4 |
| `<field> mismatch - BOOTSTRAP_TFVARS says X, TF_STATE_* says Y` | The two descriptions of the backend disagree | Fix the variables so they name the same account |
| `The plan came from run N, not this run` | An apply was fed a plan from a different run | Start a fresh run; do not re-run a single job |
| Plan shows the workspace **must be replaced** | Usually a change that forces replacement | **Do not approve.** Investigate first — this destroys and recreates the workspace |
| `RemotePeeringIsDisconnected` on deploy | A stale hub-side peering from an earlier destroy | Delete the hub-side peering (command is in the destroy run's summary), then re-run |
| Destroy log shows `cannot delete mws network connectivity config ... attached to one or more workspaces`, then succeeds | **Normal.** Unbinding the NCC and deleting it are separate Databricks calls, and the unbind is not immediately visible | Nothing. The apply retries automatically and typically completes on attempt 2. `apply.log` records each attempt |
| Need to inspect a HAProxy VM | Port 22 is deliberately closed (`admin_ssh_source_cidrs = []`). Use `az vm run-command invoke -g <rg> -n <vm> --command-id RunShellScript --scripts "systemctl status haproxy"` — it runs as root over the Azure control plane and needs only Virtual Machine Contributor |
| `Error acquiring the state lock` | Another run holds it | Wait — runs queue by design. If a run was killed mid-apply, the lock may need clearing manually |
| A run is queued behind another | Deploy and Destroy share a concurrency group | Expected. It will start when the other finishes |

---

## 7. Reference

### Workflow inputs

| Workflow | Input | Type | Notes |
| --- | --- | --- | --- |
| Bootstrap | `dev` / `test` / `prod` | checkbox | Any combination; independent of each other |
| Deploy | `dev` / `test` / `prod` | checkbox | Any combination; run in promotion order |
| Destroy | `dev` / `test` / `prod` | checkbox | Any combination; independent of each other |
| Destroy | `confirm` | text | Must equal the ticked list, e.g. `dev,prod` |

### Workflow files

| File | Role |
| --- | --- |
| `terraform-pull-request.yml` | Entry point — automatic checks on pull requests |
| `terraform-bootstrap.yml` | Entry point — create the state backend |
| `terraform-deploy.yml` | Entry point — deploy the platform |
| `terraform-destroy.yml` | Entry point — tear an environment down |
| `_terraform-validate.yml` | Reusable — fmt and validate, no credentials |
| `_terraform-plan.yml` | Reusable — plan (deploy or destroy) in `<env>-plan` |
| `_terraform-apply.yml` | Reusable — apply a saved plan in `<env>-apply` |
| `_bootstrap-plan.yml` | Reusable — plan the state backend in `<env>-plan` |
| `_bootstrap-apply.yml` | Reusable — apply and migrate state in `<env>-apply` |
| `terraform-unlock.yml` | Entry point — release a state lock left by a killed run |

The reusable workflows are called with an `operation` of `deploy` or `destroy`,
which is why one pair of files serves both directions.

### Environments

Six GitHub Environments, two per Azure environment:

| | Purpose | Approval |
| --- | --- | --- |
| `dev-plan`, `test-plan`, `prod-plan` | Run `terraform plan` | Never gated |
| `dev-apply`, `test-apply`, `prod-apply` | Run `terraform apply` | **Attach reviewers here** |

### Versions

| Component | Version |
| --- | --- |
| Terraform | 1.16.1 |
| `actions/checkout` | v7 |
| `actions/upload-artifact` | v7 |
| `actions/download-artifact` | v8 |
| `azure/login` | v3 |
| `hashicorp/setup-terraform` | v4 |

The Terraform version comes from a single **repository variable**, `TERRAFORM_VERSION`, read by every workflow as
`${{ vars.TERRAFORM_VERSION }}`. Changing the version is one edit in repository settings rather than ten in code.

If that variable is unset, `setup-terraform` silently installs the latest Terraform — which is exactly the drift it
exists to prevent, so `GITHUB-SETUP.md` lists it as required and the verification script checks for it.
