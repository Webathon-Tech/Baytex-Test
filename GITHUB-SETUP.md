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
| **Azure CLI** (`az`), signed in | Creating the app registrations, credentials and role assignments |
| **GitHub CLI** (`gh`), signed in | Setting environments, variables and protection rules |

Each environment can live in its own subscription. Every command below takes the
subscription as a variable for exactly that reason — run the sequence once per
environment with a different subscription ID.

---

## 2. Identity: three service principals

**One app registration per environment**, each with **two federated credentials**
— one for the `<env>-plan` GitHub Environment and one for `<env>-apply`.

No client secret is ever created. GitHub Actions presents a short-lived OIDC
token which Entra exchanges for an access token, so there is no credential to
rotate, store, or leak.

> **You do not have to do all three at once.** Configure `dev` first and verify
> it end to end; create the `test` and `prod` service principals later. Until an
> environment's variables exist, pull-request plans for it report *"not
> configured yet"* and pass, rather than failing. They begin planning for real as
> soon as you complete §2 and §4 for that environment — nothing in the workflows
> needs changing.

### Create each identity, once per environment

Run once per environment, changing `ENVIRONMENT` and `SUBSCRIPTION_ID` each time.
Signed in to the Azure CLI as a user holding the roles in §1.

```bash
ORG=<github-organisation>
REPO=<github-repository>
ENVIRONMENT=dev                        # then test, then prod
SUBSCRIPTION_ID=<subscription-id>      # this environment's subscription

APP_NAME="sp-bte-dbx-${ENVIRONMENT}-github"

# 1. App registration and service principal. No client secret is created.
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID"

# 2. One federated credential per GitHub Environment, so the same identity can
#    be used by the plan job and the apply job and by nothing else.
for GH_ENV in "${ENVIRONMENT}-plan" "${ENVIRONMENT}-apply"; do
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\":      \"github-${GH_ENV}\",
    \"issuer\":    \"https://token.actions.githubusercontent.com\",
    \"subject\":   \"repo:${ORG}/${REPO}:environment:${GH_ENV}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
done

# 3. Roles at subscription scope - see the table below for why each is needed.
SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
for ROLE in "Contributor" "User Access Administrator" "Storage Blob Data Contributor"; do
  az role assignment create --assignee "$APP_ID" --role "$ROLE" --scope "$SCOPE"
done

# 4. The three values §4 needs for this environment.
echo "AZURE_CLIENT_ID       = $APP_ID"
echo "AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
```

Re-running is safe: `az ad app create` would create a second app registration, so
if the app already exists, look up its id instead —
`APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)` —
and re-run only the steps you need. Federated credentials and role assignments
are rejected as duplicates rather than doubled.

### What this creates

| Item | Value |
| --- | --- |
| App registration | `sp-bte-dbx-<env>-github` |
| Federated credential 1 | Subject `repo:<org>/<repo>:environment:<env>-plan` |
| Federated credential 2 | Subject `repo:<org>/<repo>:environment:<env>-apply` |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience | `api://AzureADTokenExchange` |

The subject ties the credential to **one repository and one GitHub Environment**.
A token issued for `dev-plan` cannot be used by `prod-apply`, by another
repository, or from a workflow that does not declare that environment.

> **If a run fails with `AADSTS700213`**, this organisation issues an *immutable*
> subject that embeds numeric IDs rather than names. Add a second credential per
> environment using that form:
>
> ```bash
> ORG_ID=$(gh api "orgs/${ORG}" --jq .id)
> REPO_ID=$(gh api "repos/${ORG}/${REPO}" --jq .id)
> # subject: repo:${ORG}@${ORG_ID}/${REPO}@${REPO_ID}:environment:${GH_ENV}
> ```
>
> Registering both forms is harmless and makes the setup work either way.

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
| `AZURE_CLIENT_ID` | Service principal application ID | Printed at the end of §2 |
| `AZURE_TENANT_ID` | Entra tenant ID | Printed at the end of §2 |
| `AZURE_SUBSCRIPTION_ID` | Target subscription | Printed at the end of §2 |
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

`BOOTSTRAP_TFVARS` does the same for `bootstrap/<env>`. It must name the **same**
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

Two different rules, applied to different environments:

| Rule | Where | Purpose |
| --- | --- | --- |
| **Required reviewers** | `-apply` only | Pause for approval before Azure changes |
| **Deployment branches** | **all six** | Refuse runs from branches that may not deploy |

Required reviewers belong on the `-apply` environments alone — planning changes
nothing, and gating it would only slow reviews down. Deployment branch policies
belong on **all six**, including `-plan`; see below for why.

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

Settings → Environments → pick one → **Deployment branches** → *Selected
branches* → add the patterns below. Apply to **all six** environments:

| Environment | Allowed branches |
| --- | --- |
| `dev-plan`, `test-plan`, `prod-plan` | `main`, `hotfix/*` |
| `dev-apply`, `test-apply`, `prod-apply` | `main`, `hotfix/*` |

Via the API:

```bash
REPO=<org>/<repo>
for ENV in dev-plan dev-apply test-plan test-apply prod-plan prod-apply; do
  gh api -X PUT "repos/$REPO/environments/$ENV"     -F "deployment_branch_policy[protected_branches]=false"     -F "deployment_branch_policy[custom_branch_policies]=true"
  for BRANCH in main 'hotfix/*'; do
    gh api -X POST "repos/$REPO/environments/$ENV/deployment-branch-policies"       -f "name=$BRANCH"
  done
done
```

**Do not skip the `-plan` environments.** They are the ones people forget, and
without them a run started from an unapproved branch still signs in to Azure,
takes the Terraform state lock for up to ten minutes and produces a full plan
before anything refuses it. With the policy set, the job never starts.

#### Why the workflows check this as well

The reusable workflows also compare `github.ref` against an allow-list. That is
deliberate duplication, for three reasons:

1. **A branch policy cannot vary per workflow.** Deploy, destroy and bootstrap
   all route through the same `<env>-apply` environment, so one policy governs
   all three. Destroy is restricted to `main` while deploy also permits
   `hotfix/*` — only the workflow can express that difference.
2. **It fails earlier and more cheaply.** The `Check the run is allowed` job
   stops a disallowed run in seconds, before any Azure sign-in.
3. **It is reviewable.** The workflow check is code, changed through a pull
   request and visible in git history. An environment policy is repository
   settings, which an administrator can change silently.

Either layer alone is a single point of failure. Keep both.

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
Plan dev platform (review only) / plan
Plan test platform (review only) / plan
Plan prod platform (review only) / plan
```

The `/ <job>` suffix appears because those jobs call reusable workflows; GitHub
reports them as `<calling job name> / <called job name>`. The names must match
exactly, so if a job is ever renamed, update this list too.

> **Only `Validate Terraform code / validate` should be required.** Every other check in that workflow is conditional
> — the platform plans run when `environments/**` or `modules/**` changed, the bootstrap plans and both parity checks
> when their own directory changed. A required check that gets skipped leaves the pull request permanently unmergeable,
> so listing any of them here would block ordinary merges.

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
      "Plan dev platform (review only) / plan",
      "Plan test platform (review only) / plan",
      "Plan prod platform (review only) / plan"
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

echo "== deployment branch policies (expected on ALL six) =="
for e in dev-plan dev-apply test-plan test-apply prod-plan prod-apply; do
  printf '%-12s ' "$e"
  gh api repos/$REPO/environments/$e/deployment-branch-policies     --jq '[.branch_policies[].name] | join(", ")' 2>/dev/null || echo "NONE SET"
done

echo "== branch protection on main =="
gh api repos/$REPO/branches/main/protection \
  --jq '{checks: .required_status_checks.contexts,
         approvals: .required_pull_request_reviews.required_approving_review_count,
         admins_included: .enforce_admins.enabled,
         force_pushes: .allow_force_pushes.enabled}'
```

What to expect:

| Check | Expected |
| --- | --- |
| Environments | all six present |
| Variables | all nine on every environment you have configured so far |
| Reviewers | on `test-apply` and `prod-apply` at minimum |
| Deployment branch policies | `main, hotfix/*` on **all six** — a `NONE SET` here is the gap described in §5 |
| Branch protection | required checks listed, `admins_included: true`, `force_pushes: false` |

A missing variable surfaces at run time as a workflow failure naming it. A
missing deployment branch policy surfaces as nothing at all, which is why it is
worth asserting here.
