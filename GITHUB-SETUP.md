# GitHub Setup — Repository Administrator Guide

Everything that must be configured in GitHub and Entra before the workflows can
run. Written as a from-zero checklist: following it in order takes an empty
repository to a working platform.

For how to *run* the pipelines once this is done, see
**[WORKFLOWS.md](WORKFLOWS.md)**.

---

## 1. Prerequisites

| You need | For |
| --- | --- |
| **Global Administrator** in the Entra tenant (or Application Administrator **and** User Access Administrator) | Creating the app registrations and assigning roles |
| **Owner** or **User Access Administrator** on each target subscription | Granting the service principals their roles |
| **Databricks Account Admin** | Adding each service principal to the Databricks account console |
| **Admin** on the GitHub repository | Creating environments, variables and protection rules |
| Windows PowerShell 5.1 or PowerShell 7, with the Azure CLI signed in | Running the setup script |

Each environment can live in its own subscription. The script takes the
subscription as a parameter for exactly that reason — run it three times with
three different subscription IDs.

---

## 2. Identity: three service principals

**One app registration per environment**, each with **two federated credentials**
— one for the `<env>-plan` GitHub Environment and one for `<env>-apply`.

No client secret is ever created. GitHub Actions presents a short-lived OIDC
token which Entra exchanges for an access token, so there is no credential to
rotate, store, or leak.

### Run the script, once per environment

```powershell
cd scripts

.\New-GitHubOidcServicePrincipal.ps1 -Environment dev  -SubscriptionId <dev-subscription-id>
.\New-GitHubOidcServicePrincipal.ps1 -Environment test -SubscriptionId <test-subscription-id>
.\New-GitHubOidcServicePrincipal.ps1 -Environment prod -SubscriptionId <prod-subscription-id>
```

Other parameters, all optional:

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-GitHubOrg` | `Webathon-Tech` | Organisation that owns the repository |
| `-GitHubRepo` | `Baytex-Test` | Repository name |
| `-NamePrefix` | `sp-bte-dbx` | App registration name prefix |
| `-UseOwnerRole` | off | Assign `Owner` instead of the least-privilege split below |

The script is **idempotent** — re-running reuses the existing app, service
principal, federated credentials and role assignments rather than duplicating
them. It prints the client ID, tenant ID and subscription ID you need in §4.

### What it creates

| Item | Value |
| --- | --- |
| App registration | `sp-bte-dbx-<env>-github` |
| Federated credential 1 | Subject `repo:<org>/<repo>:environment:<env>-plan` |
| Federated credential 2 | Subject `repo:<org>/<repo>:environment:<env>-apply` |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience | `api://AzureADTokenExchange` |

> **Two subject formats.** Some organisations issue an *immutable* subject that
> embeds numeric IDs — `repo:<org>@<orgId>/<repo>@<repoId>:environment:<env>`
> — rather than the classic name-based one. The script registers **both**, so
> the credentials work either way. If a run fails with `AADSTS700213`, the
> subject format is the cause; re-running the script fixes it.

### Azure roles granted, at subscription scope

| Role | Why it is needed |
| --- | --- |
| **Contributor** | Create and manage the platform resources |
| **User Access Administrator** | Assign the workspace's own roles to managed identities |
| **Storage Blob Data Contributor** | Read and write the Terraform state blobs — the backend authenticates as the service principal (`use_azuread_auth=true`), never with an account key |

`-UseOwnerRole` collapses the first two into `Owner`. The default split is the
least privilege that still works.

### Databricks account console

Each service principal must be added to the Databricks account **and granted the
Account Admin role**. Without it, the Network Connectivity Configuration API
returns *"API disabled without account admin"* and the deploy fails partway.

> Account console → **User management** → **Service principals** → add by
> Application ID → enable the **Account admin** toggle.

---

## 3. The six GitHub Environments

**Settings → Environments → New environment.** Create all six with these exact
names:

```
dev-plan     dev-apply
test-plan    test-apply
prod-plan    prod-apply
```

**Why two per environment.** The plan job and the apply job run in different
GitHub Environments so that approval can be attached to the apply alone. Planning
is safe and should never need sign-off; applying is the decision. Splitting them
also means the plan-side credentials are separable from the apply-side ones if
you later want to narrow them.

---

## 4. Variables, per environment

Set these on **each of the six environments** (Settings → Environments → pick one
→ **Environment variables**). All six need the full set — the plan and apply jobs
each read them.

| Variable | Holds | Where the value comes from |
| --- | --- | --- |
| `AZURE_CLIENT_ID` | Service principal application ID | Printed by the script in §2 |
| `AZURE_TENANT_ID` | Entra tenant ID | Printed by the script |
| `AZURE_SUBSCRIPTION_ID` | Target subscription | Printed by the script |
| `TF_STATE_RESOURCE_GROUP` | Resource group holding the state storage account | Your naming standard |
| `TF_STATE_STORAGE_ACCOUNT` | State storage account name | Your naming standard |
| `TF_STATE_CONTAINER` | Blob container for state | e.g. `tfstate` |
| `TF_STATE_KEY` | Blob name for the platform state | e.g. `platform/dev.tfstate` |
| `TFVARS` | **The entire `terraform.tfvars` file** for this environment | See below |
| `BOOTSTRAP_TFVARS` | **The entire `terraform.tfvars` file** for the state backend root | See below |

### Why whole files live in variables

`TFVARS` holds the complete contents of `environments/<env>/terraform.tfvars`,
and the workflow writes it to disk at run time. This is what lets one set of
`.tf` files serve three environments with **no environment-specific values in
git** — no CIDRs, no resource names, no hostnames.

`BOOTSTRAP_TFVARS` does the same for `bootstrap/state`. It must name the **same**
resource group, storage account and container as the `TF_STATE_*` variables — the
bootstrap workflow cross-checks them and refuses to run if they disagree, because
otherwise it would create one storage account and store its state in a different
one.

### ⚠️ Variables vs secrets

These are currently **variables**, so their content is visible in the GitHub UI
during validation. GitHub masks **secrets** in logs automatically and does **not**
mask variables.

**Before any client deployment, switch `TFVARS` and `BOOTSTRAP_TFVARS` to
secrets.** Each workflow already carries the alternative line, commented out
directly above the one in use:

```yaml
# TFVARS: ${{ secrets.TFVARS }}
TFVARS: ${{ vars.TFVARS }}
```

Swap which line is commented in these four files, then move the values from
Environment *variables* to Environment *secrets*:

- `.github/workflows/_terraform-plan.yml`
- `.github/workflows/_terraform-apply.yml`
- `.github/workflows/_bootstrap-plan.yml` (uses `BOOTSTRAP_TFVARS`)
- `.github/workflows/_bootstrap-apply.yml` (uses `BOOTSTRAP_TFVARS`)

---

## 5. Environment protection rules

Set on the **`-apply`** environments only. The `-plan` environments stay open —
planning changes nothing, and gating it would only slow reviews down.

### Required reviewers

Settings → Environments → `test-apply` → **Required reviewers** → add one or more
people or teams.

| Environment | Recommended | Effect |
| --- | --- | --- |
| `dev-apply` | none | Iterating on dev stays fast |
| `test-apply` | 1+ reviewer | Run pauses before applying to test |
| `prod-apply` | 1+ reviewer | Run pauses before applying to prod |

Because every mutating workflow routes its apply through `<env>-apply`, adding a
reviewer here gates **deploy, destroy and bootstrap** for that environment at
once. To gate dev as well, add a reviewer to `dev-apply` — no workflow change is
needed.

> **You cannot approve your own deployment** in some configurations. If a run you
> started shows no Approve button, add a second reviewer.

Via the API:

```bash
gh api -X PUT repos/<org>/<repo>/environments/test-apply \
  -F "reviewers[][type]=User" -F "reviewers[][id]=<numeric-user-id>"
```

### Deployment branch policies

On each `-apply` environment, set **Deployment branches** to *Selected branches*
and add `main` and `hotfix/*`.

This duplicates the branch check inside the workflows on purpose. The workflow
check lives in code and is reviewed through a pull request; the environment policy
lives in repository settings. Either alone is a single point of failure.

---

## 6. Branch protection on `main`

Settings → Branches → **Add branch protection rule** for `main`:

| Setting | Value | Why |
| --- | --- | --- |
| Require a pull request before merging | on | Nothing reaches `main` unreviewed |
| Required approvals | 1 (or more) | A second pair of eyes |
| Require status checks to pass | on, with the checks below | Broken code cannot merge |
| Require branches to be up to date | on | The checks ran against what will actually land |
| **Include administrators** | **on** | Without this, admins bypass everything and the rule is decorative |
| Allow force pushes | off | History stays intact |
| Allow deletions | off | `main` cannot be removed |

### Required status checks — exact names

```
Validate Terraform code / validate
Check environment root parity
Plan dev (review only) / plan
Plan test (review only) / plan
Plan prod (review only) / plan
```

The `/ <job>` suffix appears because those jobs call reusable workflows; GitHub
reports them as `<calling job name> / <called job name>`. The names must match
exactly, so if a job is ever renamed, update this list too.

> A check name only becomes selectable after it has run at least once. Open a
> throwaway pull request first if the list is empty.

Via the API:

```bash
gh api -X PUT repos/<org>/<repo>/branches/main/protection \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Validate Terraform code / validate",
      "Check environment root parity",
      "Plan dev (review only) / plan",
      "Plan test (review only) / plan",
      "Plan prod (review only) / plan"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 1 },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

---

## 7. Before handing over to the client

- [ ] Switch `TFVARS` and `BOOTSTRAP_TFVARS` from variables to **secrets** (§4)
- [ ] Decide repository **visibility**. On a public repository every Actions log
      and artefact is world-readable, including `terraform show` output — a full
      resource inventory — and subscription and workspace identifiers
- [ ] If the repository was ever public, review or delete the existing **Actions
      run history and artefacts**
- [ ] Confirm required reviewers are set on `test-apply` and `prod-apply`
- [ ] Confirm **Include administrators** is enabled on the `main` rule
- [ ] Confirm each service principal still holds **Account admin** in Databricks
- [ ] Re-point the required status check names if any job was renamed

---

## 8. Verify the configuration

Run this to assert the setup is complete rather than assuming it. It reads only.

```bash
REPO=<org>/<repo>

echo "== environments =="
gh api repos/$REPO/environments --jq '.environments[].name'

echo "== variables per environment =="
for e in dev-plan dev-apply test-plan test-apply prod-plan prod-apply; do
  echo "-- $e"
  gh api repos/$REPO/environments/$e/variables --jq '.variables[].name' | sort | tr '\n' ' '
  echo
done

echo "== reviewers on apply environments =="
for e in dev-apply test-apply prod-apply; do
  printf '%-12s ' "$e"
  gh api repos/$REPO/environments/$e \
    --jq '[.protection_rules[] | select(.type=="required_reviewers") | .reviewers[].reviewer.login] | join(", ") // "none"'
done

echo "== branch protection on main =="
gh api repos/$REPO/branches/main/protection \
  --jq '{checks: .required_status_checks.contexts,
         approvals: .required_pull_request_reviews.required_approving_review_count,
         admins_included: .enforce_admins.enabled,
         force_pushes: .allow_force_pushes.enabled}'
```

Every one of the six environments should list all nine variables. Anything
missing will surface as a workflow failure naming the variable.
