# Pipelines — How They Work and Which Strategy to Use

Everything about the CI/CD in this repository: what each workflow does, when it
fires, how a change travels from a developer's branch to production, and the
strategies available when something is urgent or goes wrong.

Every non-obvious decision here names the failure that caused it. A rule whose
reason is unrecorded is a rule somebody removes later.

> For the GitHub configuration these workflows depend on — environments,
> variables, protection rules, branch protection — see
> [GITHUB-SETUP.md](GITHUB-SETUP.md).

---

## 1. The seven workflows

```text
.github/workflows/
├── terraform-validate.yml           pull request       fmt + validate, no credentials
├── terraform-plan-pr.yml            pull request       parity report + plan all 3 envs
├── terraform-bootstrap-state.yml    manual             creates state backends
├── terraform-deploy.yml             manual             deploys; dev -> test -> prod
├── terraform-destroy.yml            manual             destroys one environment
├── _terraform-plan.yml              called             reusable plan
└── _terraform-apply.yml             called             reusable apply
```

The leading underscore marks a workflow that is never run directly. GitHub has no
concept of a private workflow, so the naming convention is the only signal — and
those two have no **Run workflow** button, which is the visible confirmation.

### Trigger summary

| Workflow | Fires when | Scope | Needs Azure? |
| --- | --- | --- | --- |
| Terraform Validate | pull request | fmt + validate | **no** |
| Terraform Plan (PR) | pull request opened/updated | plans dev + test + prod | yes (read) |
| Bootstrap State Backend | manual | one env, or `all` | yes |
| Terraform Deploy | manual | `dev` / `test` / `prod` / `all` | yes |
| Terraform Destroy | manual + typed confirmation | one env | yes |

**Nothing deploys automatically.** There is no trigger on merge. Merging is a
statement about code review; applying is a statement that an environment is ready
to change — often gated on a change window or a customer-side handoff. Coupling
them would let a merge silently mutate production.

### Environments that do not exist yet

You do not have to bootstrap all three environments to start using the pipelines.
Before an environment has a state backend, `terraform init` against it fails hard,
which would make every pull request red for reasons nobody can fix — and a
permanently failing check is one people stop reading.

So the plan workflows detect a missing backend and behave differently by purpose:

| Situation | Behaviour |
| --- | --- |
| Report-only plan (pull request), no backend | **Skipped**, with a note naming the workflow that provisions it. Run stays green. |
| Deploy plan, no backend | **Fails**, naming the bootstrap workflow. You asked to deploy it; it cannot work. |
| Destroy, no backend | **Succeeds as a no-op.** The desired end state is already true. |

Verified with only dev bootstrapped: dev planned normally while test and prod
skipped and the run stayed green.

The check looks for the storage **account and container**, not the state blob. The
blob is created on first write, so its absence is normal for an environment that
has been bootstrapped but never deployed.

---

## 2. The developer journey

```
git push (feature branch)
  └─ nothing runs

open pull request
  ├─ Terraform Validate ......... fmt + validate, seconds, no credentials
  ├─ Root parity ................ reports if the three env roots have drifted
  ├─ Plan dev ................... impact on dev
  ├─ Plan test .................. impact on test
  └─ Plan prod .................. impact on prod

merge to main
  └─ nothing runs

Actions -> Terraform Deploy
  ├─ dev ........................ applies immediately
  ├─ test ....................... PAUSES for approval
  └─ prod ....................... PAUSES for approval
```

### Why nothing runs on push or on merge

Both were tried and removed as noise. A push-triggered validate fired on every
commit, for a result that only matters once somebody is reviewing. And a
merge-triggered plan re-ran all five checks against the same commit a reviewer
had just approved on the pull request — identical inputs, identical result.

Everything now happens in one place: the pull request. That is where a human is
already looking.

### Why validate exists alongside the plan jobs

The plan jobs run `terraform validate` too, so this looks redundant. It is not:
in `_terraform-plan.yml` that step is guarded by the state-backend check, so for
any environment not yet bootstrapped the plan job **skips** it. With no backends
at all, `terraform-validate.yml` is the only thing validating the code.

### Why validate needs no credentials

`terraform init -backend=false` is enough for `terraform validate`. No state is
read and no Azure login happens, so it is safe on a branch pushed by anyone.
Before it existed a developer got no feedback at all until they opened a PR — a
syntax error could sit on a branch for days.

### Why all three environments are planned

The three roots are **separate copies** of the same `.tf` files. A change can be
valid for dev and break prod — a name collision, an address that does not fit
prod's `/20`. Planning dev alone would not show it.

### Why the parity check reports instead of failing

`environments/{dev,test,prod}/*.tf` should be identical; only `terraform.tfvars`
differs, and that is not in git. But divergence is *sometimes* deliberate, and a
hard gate would train people to bypass the check. Making it visible on every PR
is what matters.

Verified both ways: with a tag added to dev only it reported
`2 difference(s) found` and printed the diff; once copied to test and prod it
reported `Roots are identical`.

---

## 3. Where a change belongs

This decides how far it spreads:

| Edit | Affects |
| --- | --- |
| `modules/**` | **all three** environments — every root references `../../modules/...` |
| `environments/dev/**` | **dev only** — test and prod hold their own copies |
| `TFVARS` variable for one environment | **that environment only** |

A platform component goes in a module. Something genuinely dev-specific goes in
dev's root — and the parity report will flag it, which is correct.

---

## 4. Strategies

### Normal promotion

```
PR -> review -> merge -> Deploy dev -> validate -> Deploy test -> validate -> Deploy prod
```

Or `deploy_target: all` to chain them, stopping at the first failure. Test cannot
be reached until dev has actually applied.

### Configuration-only change

Adding a route, an endpoint, a DNS server, an alert address — these live entirely
in the `TFVARS` variable. Update it for that environment and deploy. No PR, no
branch, and it cannot affect any other environment. This is the fast path and it
is genuinely safe.

### Hotfix

Because all environments share the same code, deploying `main` to prod applies
**every** merged-but-undeployed change, not just the urgent one. To apply exactly
one thing:

```bash
git checkout -b hotfix/ncc-rule-fix <commit-prod-is-running>
git cherry-pick <fix-sha>
git push -u origin hotfix/ncc-rule-fix
```

Then Deploy, selecting that branch. `hotfix/*` is the only non-`main` ref an apply
accepts — verified: an apply from `feature/guard-check` was refused with
`Refusing to apply from 'refs/heads/feature/guard-check'`, while one from
`hotfix/nat-timeout-emergency` reported `Applying from refs/heads/hotfix/...`
and applied successfully.

**Merge the hotfix back to `main`**, or the next ordinary deploy reverts it.

### Rollback

Terraform has no rollback. Reverting is a forward apply:

```bash
git revert <bad-sha>    # then deploy that environment
```

Two things do not revert cleanly. `infrastructure_encryption_enabled` and the
workspace's `default_catalog` are create-time only, so reverting them plans a
**replace**. And anything already destroyed comes back empty. Always read the
plan — a revert showing `destroy` or `replace` on a stateful resource is a
rebuild, not a rollback.

### Break-glass

If Actions is down and an environment is genuinely impaired, run Terraform locally
against the same backend. This produces a change with no plan artefact, no
approval and no audit record, so: say so before you start, keep the plan output,
and get the fix onto `main` the same day.

---

## 5. Concurrency — several people at once

| Scenario | Behaviour |
| --- | --- |
| Several developers pushing branches | Independent. Per-branch group, no state touched. |
| Two PRs open together | Both plan in parallel. Report-only plans use `-lock=false`, so no contention. |
| PR opened during a deploy | Same — the deploy holds the lease, the PR plan does not need it. |
| Two deploys | Queue. Shared `terraform-mutate` group, `cancel-in-progress: false`. |
| Deploy and destroy together | Cannot happen — same `terraform-mutate` group; the second queues. |
| Bootstrap alongside a deploy | Independent — different state key (`bootstrap/<env>.tfstate`). |

**Why report-only plans are lock-free.** A PR plan never writes state, so taking
the blob lease buys nothing and causes real problems: two PRs at once, or a PR
during a 20-minute deploy, would queue on the lease and fail after the timeout.
Worse, `cancel-in-progress` can kill a run holding the lease and strand it.

Deploy plans **do** lock, because their plan feeds an apply and must see a state
nothing else is mutating.

Verified by opening two PRs simultaneously: both planned all three environments,
overlapping in time, with zero lock errors.

One consequence worth expecting: because deploy and destroy share a group, a
destroy sitting on an approval gate **holds the group**, and a deploy started
meanwhile queues behind it rather than running. That is the protection working,
not a stall — but it surprises people the first time.

### If a lock does get stranded

A cancelled or crashed apply can leave a lease held. Terraform prints the lock ID:

```bash
terraform force-unlock <LOCK-ID>
```

Only do this once you are certain no apply is still running.

---

## 6. Environments and identity

Six GitHub Environments: `dev-plan`, `dev-apply`, `test-plan`, `test-apply`,
`prod-plan`, `prod-apply`. Each carries `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`, the `TF_STATE_*` values, and `TFVARS`.

Two per stage because a federated credential is bound to a subject containing the
environment name, so the credential that can *plan* dev differs from the one that
can *apply* it — and it gives a place to hang an approval that affects only
applies.

**Branch protection on `main`.** Direct pushes are refused, including for
repository admins — every change reaches `main` through a pull request. This is
what makes the ref guards meaningful: restricting applies to `main` and `hotfix/*`
only helps if getting onto `main` requires review. Configured per
[GITHUB-SETUP.md](GITHUB-SETUP.md) §4.

**Approvals.** `test-apply` and `prod-apply` require a reviewer and are restricted
to `main` and `hotfix/*`. `dev-apply` has the branch restriction but no reviewer. `dev-apply` deliberately has neither, so iterating on
dev stays fast. Protection rules need a public repository on the Free plan, or
Pro/Team/Enterprise on a private one.

**Authentication is OIDC** — no client secret exists anywhere. GitHub emits one of
two subject formats and which one is not discoverable in advance, so the setup
script registers both:

```
classic     repo:<org>/<repo>:environment:<env>
immutable   repo:<org>@<orgId>/<repo>@<repoId>:environment:<env>
```

Presenting the wrong one fails with `AADSTS700213`.

### TFVARS: variable or secret

Currently a **variable**, so its content is visible while testing. The
`secrets.TFVARS` line is commented directly above it in each workflow, for a
one-line revert.

> **Switch it back to a secret before any client deployment.** GitHub masks
> secrets in logs automatically and does **not** mask variables. Nothing in the
> file is a credential — the SSH key is a public key — but on a public repository
> that masking is genuinely protective.

---

## 7. Deliberately not automated

| Not automated | Why |
| --- | --- |
| Hub-side VNet peering | The hub is customer-owned. Terraform creates the spoke side and emits the command for the other. |
| Corporate DNS / private zone links | Central DNS is a customer change process. |
| NCC private endpoint approval | Approving a path toward on-premises databases should be a deliberate human act. |
| Unity Catalog objects | Different owner, approval path and change cadence. |
| Databricks account admin for the SPs | Requires an existing account admin in the Databricks console. |

---

## 8. Traps worth knowing

**A tag change replaces the Databricks workspace.** `local.tags` feeds every
resource group. Changing a tag marks the platform resource group as *updated*,
which defers the AVM module's resource-group data source to apply time, making
`parent_id` unknown — and `parent_id` is ForceNew:

```
# module.databricks_workspace.azapi_resource.this                     must be replaced
# module.databricks_workspace.azurerm_monitor_diagnostic_setting.this must be replaced
# module.ncc.databricks_mws_ncc_binding.workspace                     must be replaced
```

Editing a cost centre or owner tag would destroy and recreate the workspace. The
cause is `depends_on = [azurerm_resource_group.platform]` on the module block,
which exists to stop the data source resolving during the first plan. **Read the
plan before applying anything that touches tags.**

**`terraform destroy` needs more than one pass.** Azure refuses to delete a
Private Link Service that still has private endpoint connections, and the
Databricks-managed endpoints outlive the NCC that created them. Deleting the NCC
binding and the NCC are separate API calls and the unbind is not immediately
visible. The destroy workflow clears the connections first and retries the apply,
re-planning between attempts.

**Diagnostic settings can report "already exists" on a first apply.** The provider
creates the setting, reads it back before Azure is consistent, retries and
collides with itself. Recovery is to import, or delete and re-apply.

**A green apply is not acceptance.** Anything driven by cloud-init needs runtime
proof — a fully successful apply once left a completely dead HAProxy tier.

**Run `az` from PowerShell, not Git Bash.** MSYS rewrites arguments that look like
Unix paths, so `--remote-vnet /subscriptions/...` arrives mangled.

---

## 9. What has been proven

Every workflow has been exercised end to end against a sandbox subscription, with
a mock on-premises hub standing in for the customer's hub, firewall and databases.

| Path | Evidence |
| --- | --- |
| Bootstrap, first run | mode `create`, then `Idempotency confirmed` |
| Bootstrap, re-run | mode `remote`, no changes |
| Bootstrap `all` | three matrix legs; dev `remote`, test and prod `create` in one run |
| Plan with no backends | all three skipped, run green |
| Plan with only dev | dev planned, test and prod skipped |
| Deploy dev | full platform, then 11/11 connectivity checks |
| Promotion chain `all` | dev → test → prod, both approval gates held and released |
| Validate on push | ran on a feature branch with no Azure credentials |
| Parity, divergent | `2 difference(s) found` plus the diff |
| Parity, aligned | `Roots are identical` |
| Plan on merge | `event=push`, all three planned |
| Apply a modification | `0 added, 1 changed, 0 destroyed` |
| Hotfix branch apply | allowed and applied |
| Feature branch apply | refused before touching Azure |
| Wrong destroy confirmation | refused before authenticating |
| Two simultaneous PRs | overlapping, zero lock errors |
| Destroy | state emptied, further destroy plan reports no changes |

The connectivity sweep is the one that matters: real TCP from an internal load
balancer front end, through floating IP to HAProxy, out via the route table to the
firewall and on to the simulated on-premises host, returning
`SIMULATED-SQL-OK` / `SIMULATED-ORACLE-OK`. That is the serverless path, proven.

A green pipeline is still not acceptance — see §8.

---

## 10. Quick reference

```
Create the state backend    Actions -> Terraform Bootstrap State Backend
                            environment: dev | test | prod | all

Deploy                      Actions -> Terraform Deploy
                            deploy_target: dev | test | prod | all

Destroy                     Actions -> Terraform Destroy
                            environment + type the same name to confirm

Emergency fix to prod       branch hotfix/*, cherry-pick, Deploy from that branch

Config-only change          update the TFVARS variable, Deploy that environment
```
