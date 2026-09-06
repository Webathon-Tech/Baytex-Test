# Pipelines Explained — What Each Workflow Does And Why

The "why" companion for CI/CD, alongside [ARCHITECTURE.md](ARCHITECTURE.md) (why
the platform looks this way) and [TERRAFORM-EXPLAINED.md](TERRAFORM-EXPLAINED.md)
(how the Terraform works). For the operational steps, see
[PIPELINE-SETUP.md](PIPELINE-SETUP.md).

Every design note here was either forced by a constraint or learned by hitting
the failure in the sandbox rehearsal. Where something exists because of a real
failure, the failure is named — a rule whose reason is unrecorded is a rule
someone will "simplify" away later.

---

## 1. The shape of the whole thing

Six workflow files, two of which are building blocks rather than entry points:

```text
.github/workflows/
├── terraform-bootstrap-state.yml    entry   creates the state backend
├── terraform-deploy.yml             entry   deploys; dev -> test -> prod
├── terraform-destroy.yml            entry   destroys one environment
├── terraform-plan-pr.yml            entry   plan-only check on pull requests
├── _terraform-plan.yml              called  reusable plan
└── _terraform-apply.yml             called  reusable apply
```

The leading underscore marks a workflow that is never run directly. GitHub has no
concept of a private workflow, so the naming convention is the only signal.

### Why plan and apply are separate workflows

They run as **different jobs, in different GitHub Environments, with different
federated credentials**. That is the whole point:

- Planning needs to read state and read Azure. Applying needs to change Azure.
- The `<env>-apply` environment is where an approval gate is attached. If plan
  and apply were one job, there would be nothing to pause *between* producing a
  plan and enacting it.
- The apply consumes the **exact binary plan** the plan job produced. It never
  re-plans. A re-plan after approval could differ from what was approved —
  someone merges to `main`, or a data source resolves differently, and the thing
  applied is not the thing reviewed.

### Why reusable workflows instead of three copies

Each environment needs ~90 lines of identical steps. Three copies would drift:
someone fixes the `fmt` ordering in dev and forgets prod. The per-environment
difference is entirely *which GitHub Environment the job runs in*, which decides
which service principal and which `TFVARS` secret get used. That is one input,
not ninety lines.

### Why environments are `<env>-plan` and `<env>-apply`

A federated credential is bound to a specific subject, and the subject includes
the environment name:

```
repo:<org>/<repo>:environment:dev-apply
```

Two environments per stage means the credential that can *plan* dev is a
different credential from the one that can *apply* dev — even though both
currently map to the same service principal. It also gives a place to hang an
approval gate that only affects applies.

---

## 2. `terraform-bootstrap-state.yml`

**Trigger:** manual, choose an environment.
**Runs in:** `<env>-apply`.
**Run:** once per environment. Safe to re-run at any time.

### The problem it solves

Terraform cannot store state in a storage account that does not exist yet. So
the first run has to use local state, create the account, then move its own state
into the account it just created.

That is easy to do once by hand and surprisingly hard to make *repeatable*, which
is what a pipeline needs.

### Why it branches on the state blob, not the storage account

```
| State blob | Storage account | Mode    | Action                                    |
| exists     | exists          | remote  | init remote -> plan/apply (no-op)         |
| missing    | exists          | import  | init local -> import -> migrate           |
| missing    | missing         | create  | init local -> apply -> migrate            |
```

The obvious check is "does the storage account exist?" — and it is wrong. If an
earlier run created the account but died before migrating state, that check sends
you down the *remote* path, inits against an empty backend, and Terraform then
tries to create a storage account whose name is already taken. The run fails and
the operator is left hand-editing state.

Checking the **blob** distinguishes "backend exists and is tracked" from "backend
exists but nothing tracks it". The second case is recoverable by importing, which
is exactly what the `import` mode does.

### Why `backend.tf` is moved aside rather than using `-backend=false`

This one cost a failed run. `terraform init -backend=false` skips backend
*initialisation*, but the `azurerm` backend block is still declared in the
configuration, so the subsequent plan refuses:

```
Error: Backend initialization required, please run "terraform init"
```

The local phase needs the backend block **absent**, not merely uninitialised. So
the file is moved out of the directory, init runs with local state, and it is
restored before `-migrate-state`.

### Why it asserts idempotency instead of assuming it

The last step runs `terraform plan -detailed-exitcode` and fails the run on
anything but exit 0. A bootstrap that quietly leaves drift means every later run
shows changes, and operators learn to ignore a noisy pipeline. Making the
pipeline fail loudly on day one is cheaper than that habit.

*Verified: a second run took the `remote` path, skipped create/import/migrate,
and reported no changes.*

### Why it does not create its own storage role assignment

`bootstrap/state` can grant `Storage Blob Data Contributor` on the state
account, but the pipeline passes an empty list. The migrate step runs seconds
after apply, and a freshly created data-plane role assignment has not reliably
propagated by then. The deployment principals get that role at subscription scope
when they are created instead, which is settled long before any pipeline runs.

---

## 3. `_terraform-plan.yml` (reusable)

**Called by:** `terraform-deploy.yml`, `terraform-plan-pr.yml`.
**Runs in:** `<env>-plan`.

Step order matters more than the steps themselves.

### `fmt -check` runs BEFORE the tfvars secret is written

`terraform fmt` checks `.tfvars` files, not just `.tf`. The original workflows
wrote `secrets.DEV_TFVARS` to `terraform.tfvars` and *then* ran
`terraform fmt -check -recursive` — so the gate failed on the formatting of
**secret content**, not on repository code. Every run would have failed, and the
error would have pointed at a file nobody could see.

This is not hypothetical: the repository's own change log records "`terraform fmt
-check` failed in 6 files — both CI workflows fail on the first pipeline run" as
a previously fixed defect. It had re-entered through the tfvars path.

### `upload_plan` is an input

A pull-request plan and a deployment plan want different things. A deployment
plan must be preserved as a binary artefact so apply can consume it. A PR plan
only needs to be readable — uploading a binary plan from an unmerged branch
invites someone to apply it. The input switches between uploading `tfplan` and
uploading only the rendered text.

### Why the lock file travels with the plan

The uploaded artefact includes `.terraform.lock.hcl`. The apply job downloads it
**before** running `init`, so provider versions are pinned to exactly what the
plan was built against. Without that, apply could resolve a newer patch release
inside the `~>` constraint and run a different provider than the one reviewed.

---

## 4. `_terraform-apply.yml` (reusable)

**Called by:** `terraform-deploy.yml`.
**Runs in:** `<env>-apply` — the gated environment.

### It applies a saved plan, never a fresh one

```bash
terraform apply -lock-timeout=10m -auto-approve tfplan
```

`-auto-approve` looks alarming and is not. Applying a *saved plan file* is
already non-interactive; Terraform refuses if state has moved underneath it. The
approval happened at the GitHub Environment gate, against the rendered plan.

### Step order is load-bearing

Download artefact → `init` → verify → apply. The download must precede `init` so
the reviewed lock file governs provider selection, and the explicit existence
check on `tfplan` and `.terraform.lock.hcl` turns a silently empty artefact into
a clear failure rather than an apply that plans from scratch.

---

## 5. `terraform-deploy.yml`

**Trigger:** manual, `deploy_target: dev | test | prod | all`.

### Why one workflow with a target, not three workflows

Promotion order is a property of the *pipeline*, not of three unrelated buttons.
Expressing `dev → test → prod` as `needs:` between jobs means GitHub enforces it:
test cannot start until dev has actually applied, and a failure stops the chain.
Three separate workflows would make the ordering a convention that someone
eventually breaks under time pressure.

### Why `always()` appears in the conditions

```yaml
test-plan:
  needs: dev-apply
  if: >-
    always() && (
      inputs.deploy_target == 'test' ||
      (inputs.deploy_target == 'all' && needs.dev-apply.result == 'success')
    )
```

Without `always()`, a **skipped** dependency skips everything downstream. On a
`deploy_target: test` run the dev jobs are skipped by design, which would skip
test too — the workflow would appear to do nothing.

`always()` lets the condition be evaluated, and the condition then does the real
work: run if this environment was explicitly targeted, **or** if we are chaining
and the previous stage genuinely succeeded. The `result == 'success'` check is
what stops `all` from marching past a failure.

*Verified: a `deploy_target: test` run showed `dev-plan` and `dev-apply` skipped
with only `test-plan` and `test-apply` executing.*

### Why `cancel-in-progress: false`

Cancelling a deploy mid-apply leaves Azure half-changed and can abandon a state
lock. Plans are cheap to redo; applies are not.

---

## 6. `terraform-destroy.yml`

**Trigger:** manual, environment plus a typed confirmation.
**Runs in:** `<env>-apply`.

### Why it is a separate workflow

Destruction could have been a fourth value of `deploy_target`. It should not be.
The workflow people run every day should not have "delete everything" one
dropdown position away from "deploy dev".

### The confirmation guard, and why it runs where it does

The operator must type the environment name back. It is checked **before**
checkout and before Azure login, so a mistyped run costs nothing.

That step carries an explicit `working-directory: .`, which looks redundant and
is not. The job default is `environments/<env>`, which does not exist until
checkout. Without the override the step dies on a missing directory — failing for
a right-looking reason but the wrong cause, which made an early test of the guard
a **false positive**. The guard was fixed and then genuinely re-tested with a
wrong value.

### Why it clears Private Link Service connections first

Azure refuses to delete a Private Link Service that still has private endpoint
connections:

```
PrivateLinkServiceWithPrivateEndpointConnectionsCannotBeDeleted
```

The Databricks-managed endpoints created by the NCC rules **outlive the NCC**.
After the NCC is deleted they remain `Approved` against the PLS, so Terraform
cannot remove it, and the network and connectivity resource groups survive the
destroy. The next apply then collides on names that still exist.

The workflow clears those connections before planning. This is a property of
Private Link plus NCC, not of the sandbox — it will happen in the client tenant.

### Why the apply retries

Deleting the NCC binding and deleting the NCC are separate Databricks API calls,
and the unbind is not immediately visible:

```
cannot delete mws network connectivity config: ... is unable to be deleted
because it is attached to one or more workspaces: 7405611598891423
```

By the next attempt the unbind has landed. The loop re-plans between attempts,
because a partially completed destroy makes the saved plan stale, and is bounded
at three so a genuine failure still surfaces.

### Why it verifies emptiness two ways

`terraform state list` must be empty **and** a further destroy plan must report no
changes. A partial destroy is a silent problem — it looks like success and breaks
the next apply.

### What it deliberately does not destroy

- **`bootstrap/state`.** The state backend survives, so an environment can be
  rebuilt without re-bootstrapping. It also holds the state file this job is
  writing to; destroying it from here would be self-defeating.
- **The hub-side VNet peering.** Terraform only ever creates the spoke side,
  because the hub is customer-owned. The final step prints the exact `az` command
  rather than pretending the cleanup is complete.

---

## 7. `terraform-plan-pr.yml`

**Trigger:** pull requests touching `environments/**`, `modules/**` or the
workflows.

Plans **dev only**. The Terraform is identical across environments — only inputs
differ — so planning all three on every PR triples the blast radius of a
malicious or careless PR for no extra signal. `cancel-in-progress: true` is safe
here because a superseded plan is worth nothing.

> A `pull_request` plan still runs repository code with credentials that can read
> state. On a public repo, forks get no secrets; on a private repo, a same-repo PR
> does. Anyone who can open a PR can therefore run `terraform plan` against dev.
> That is the reason to keep this scoped to dev, and a reason to require review
> before merge.

---

## 8. Cross-cutting decisions

### OIDC, never a stored secret

Every job authenticates with `azure/login` using `id-token: write` and a
federated credential. No client secret exists anywhere, so there is nothing to
rotate, leak, or find in a log.

The subject GitHub presents must match a registered credential exactly. This
organisation emits the **immutable** form:

```
repo:Webathon-Tech@269995634/Baytex-Test@1356511433:environment:dev-apply
```

not the classic `repo:<org>/<repo>:environment:<env>`. The mismatch fails with
`AADSTS700213`, and which form an org emits is not discoverable in advance — so
`New-GitHubOidcServicePrincipal.ps1` registers both.

### `TFVARS` as a secret, not a committed file

Inputs carry subscription IDs, network topology and an SSH public key. They are
environment-specific and not repository content. Keeping them as a per-environment
secret also means the pipeline is the only thing that assembles a
`terraform.tfvars`, so a stale local file cannot influence a deployment.

### Terraform pinned to 1.16.1 everywhere

CI originally pinned 1.15.9 while the code was developed on 1.16.x. Terraform
**refuses to read state written by a newer minor version**, so a single local
apply on 1.16 would have made the pipeline unusable against that state. Version
skew between local and CI is not a style question.

### `ARM_USE_AZUREAD: true`

Forces the azurerm backend and provider to use Entra ID rather than storage
account keys. It pairs with `shared_access_key_enabled = false` on the storage
accounts: there is no key to use even if something tried.

### Concurrency

| Workflow | Group | Cancel in progress |
| --- | --- | --- |
| deploy | `terraform-mutate` | no |
| destroy | `terraform-mutate` | no |
| bootstrap | `terraform-bootstrap-<env>` | no |
| plan (PR) | `terraform-plan-pr-<ref>` | yes |

Deploy and destroy share one group so the two can never overlap and fight over
the state lock. It cannot be scoped per environment because a deploy can span all
three in one run, so mutating runs serialise globally — the safe trade.

`cancel-in-progress` is true only for PR plans, where a superseded plan is worth
nothing. Cancelling an apply mid-flight leaves Azure half-changed and can abandon
a state lease.

### Every run leaves evidence

Plans, rendered plan text, outputs, and a pre-destroy `terraform state list` are
uploaded as artefacts. For an infrastructure change that someone may need to
explain months later, "what exactly did that run do" should not depend on log
retention.

---

## 9. When each pipeline runs

Nothing deploys automatically. There is no trigger on merge to `main`. Every
change to an environment is a deliberate human action.

| Workflow | Trigger | Runs for | Automatic? |
| --- | --- | --- | --- |
| Terraform Plan (PR) | `pull_request` touching `environments/**`, `modules/**` or the workflows | **dev only** | yes |
| Terraform Deploy | manual, `deploy_target` | dev / test / prod / all | no |
| Terraform Destroy | manual, environment + typed confirmation | one environment | no |
| Bootstrap State Backend | manual, environment | one environment | no |

### Why no deploy-on-merge

Merging is a statement about code review. Applying is a statement about a
specific environment being ready to change — often gated on a firewall ticket, a
change window, or a Baytex-side handoff that has nothing to do with the
repository. Coupling the two would mean a merge silently mutates prod.

The cost is that `main` can be ahead of what is deployed. That is a real trade
and it is why the plan output is treated as the source of truth about what a run
will do, rather than the commit log.

### What `deploy_target` actually does

| Value | Jobs that run |
| --- | --- |
| `dev` | dev-plan → dev-apply |
| `test` | test-plan → test-apply (dev jobs skipped) |
| `prod` | prod-plan → prod-apply (dev and test skipped) |
| `all` | dev → test → prod, stopping at the first failure |

`all` is the promotion path. The single values exist for iterating on dev, and
for re-running one stage after fixing something — a chain that fails at test
should not force dev to re-apply.

### Which branch a run uses

`workflow_dispatch` runs the workflow from whichever branch is selected, default
`main`. Plans may run from any branch — that is useful. **Applies and destroys
may not.** `_terraform-apply.yml` refuses any ref that is not `main` or
`hotfix/*`, and destroy accepts `main` only.

This guard is in the workflow rather than a GitHub Environment "deployment
branches" rule because protection rules need a paid plan on a private repository.
Without it, anyone with write access could dispatch an unreviewed feature branch
straight at prod.

---

## 10. Hotfixes

The three environments share **identical `.tf` files** and differ only in their
`TFVARS` secret. That shapes everything about hotfixing, because it means there
are two very different kinds of urgent change.

### Case A — configuration only (most common)

Adding an on-premises route, a new database endpoint, a DNS server, changing an
alert receiver. These live entirely in `TFVARS` and touch no code.

```
1. Update the TFVARS secret for that environment only
2. Actions → Terraform Deploy → deploy_target: <env>
3. Review the plan in the job summary before the apply job proceeds
```

No PR, no branch, no effect on any other environment. This is the fast path and
it is genuinely safe, because a config change to prod cannot alter dev or test.

> The trade: a secret has no diff and no review history. If you want an audit
> trail of *why* a value changed, record it in the change ticket — GitHub will
> only tell you that a secret was updated and by whom.

### Case B — a code fix

A module bug, a wrong NSG rule, a missing argument. Because the roots are
identical copies, this change belongs to **all three** environments the moment it
lands on `main`.

**Normal path** — use it unless prod is actually broken:

```
PR → review → merge to main
Deploy dev  → validate
Deploy test → validate
Deploy prod
```

**Emergency path** — prod is broken and you cannot wait for the chain:

```bash
# Branch from the commit prod is actually running, not from main
git checkout -b hotfix/ncc-rule-fix <last-known-good-sha>
git cherry-pick <fix-sha>
git push -u origin hotfix/ncc-rule-fix
```

Then Actions → Terraform Deploy → select branch `hotfix/ncc-rule-fix` →
`deploy_target: prod`.

The point of branching from the deployed commit rather than `main` is isolation.
`main` may have accumulated other merged-but-undeployed changes; deploying `main`
to prod applies *all* of them. A hotfix branch applies exactly one.

**Afterwards, merge the hotfix back to `main`.** If you do not, the next ordinary
deploy silently reverts it, because the platform's desired state comes from
whatever branch is applied.

### Choosing between them

| Situation | Path |
| --- | --- |
| New endpoint, route, DNS server, alert address | Case A — update TFVARS, deploy that env |
| Bug that affects one environment because of its inputs | Case A if fixable in tfvars, else Case B |
| Module or root bug | Case B, normal path |
| Prod broken, fix is small and understood | Case B, hotfix branch |
| Prod broken, cause not understood | Do not deploy. Diagnose first — see below. |

### Rollback

Terraform has no rollback. "Rolling back" means applying an earlier desired
state, which is a forward operation:

```bash
git revert <bad-sha>          # then deploy that environment
```

Two things do not roll back cleanly and are worth knowing before you need them:

- **Create-time-only settings.** `infrastructure_encryption_enabled` and the
  workspace's `default_catalog` cannot be changed after creation. Reverting the
  code produces a plan that **replaces** the resource.
- **Anything already destroyed.** Reverting a change that deleted a storage
  account gives you a new, empty storage account.

Always read the plan before applying a revert. A revert that shows
`destroy` / `replace` on a stateful resource is not a rollback, it is a rebuild.

### When the pipeline itself is the problem

If Actions is down or the workflow is broken and prod is genuinely impaired,
there is a break-glass path: run Terraform locally against the same backend.

This is deliberately not the documented normal route — it produces a change with
no plan artefact, no approval and no audit record. If you use it:

1. Say so in the incident channel before you start.
2. Save `terraform plan` output somewhere durable.
3. Get the fix back into `main` the same day, so the repository matches reality.

### Drift

Nothing currently detects drift on a schedule. If someone changes a resource in
the portal, you find out at the next plan. For a platform where prod matters,
a nightly `terraform plan -detailed-exitcode` per environment that alerts on
exit 2 would close that gap — it is a small addition to the existing reusable
plan workflow and is worth doing before Baytex go-live.

---

## 11. What the pipelines deliberately do not do

| Not automated | Why |
| --- | --- |
| Hub-side VNet peering | The hub is customer-owned. Terraform creates the spoke side and emits the command for the other. |
| Corporate DNS / private zone links | Central DNS is a customer change process, not a platform deployment. |
| NCC private endpoint approval | Approving a path toward on-premises databases should be a deliberate human act. `Approve-BaytexDatabricksPrivateEndpoints.ps1` only approves endpoints whose names match the deployment's own outputs. |
| Unity Catalog objects | Different owner, different approval path, different change cadence — see ARCHITECTURE §3.6. |
| Databricks account admin for the SPs | Requires an existing account admin in the Databricks console; there is no Azure-side equivalent. |

A green pipeline is not acceptance. The cloud-init defect found during the
rehearsal produced a fully successful `terraform apply` with a completely dead
HAProxy tier. Anything driven by cloud-init needs runtime proof — which is why
validation checks `systemctl is-active haproxy` and real TCP responses rather
than trusting Terraform's exit code.
