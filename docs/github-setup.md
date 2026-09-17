# GitHub Setup

Everything that must be configured in Microsoft Entra ID, Azure, Databricks and GitHub before the pipelines can run.
Followed in order, it takes an empty repository to a working platform. Environments can be set up one at a time.

For running the pipelines once this is done, see [Workflows](workflows.md).

---

## 1. Prerequisites

| You need | For |
| --- | --- |
| **Global Administrator** in the Entra tenant, or Application Administrator **and** User Access Administrator | Creating the app registrations and assigning roles |
| **Owner** or **User Access Administrator** on each environment subscription | Granting the service principals their roles |
| **Owner** or **User Access Administrator** on the hub VNet and Private DNS zones | Only for the optional hub-subscription roles in §2 |
| **Databricks Account Admin** | Adding each service principal to the Databricks account console |
| **Admin** on the GitHub repository | Creating environments, variables and protection rules |
| **Azure CLI** (`az`), signed in | Creating the app registrations, credentials and role assignments |
| **GitHub CLI** (`gh`), signed in | Setting environments, variables and protection rules |

Each environment can live in its own subscription. Every command below takes the subscription as a variable for that
reason: run the sequence once per environment.

---

## 2. Identity: one service principal per environment

Each environment has **one app registration** with **two federated credentials**, one for the `<env>-plan` GitHub
Environment and one for `<env>-apply`.

No client secret is created. GitHub Actions presents a short-lived OIDC token, which Entra exchanges for an access
token, so there is no credential to rotate, store or leak.

> **Environments can be onboarded one at a time.** Until an environment's variables exist, pull request plans for it
> report *"not configured yet"* and pass rather than fail. They begin planning as soon as §2 and §4 are complete for
> that environment, with no workflow change.

### Create the identity

Run once per environment, signed in to the Azure CLI as a user holding the roles in §1.

```bash
ORG=<github-organisation>
REPO=<github-repository>
ENVIRONMENT=dev                        # then test, then prod
SUBSCRIPTION_ID=<subscription-id>      # this environment's subscription

APP_NAME="app-bte-dbx-${ENVIRONMENT}-terraform-001"

# 1. App registration and service principal. No client secret is created.
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID"

# 2. One federated credential per GitHub Environment, so the identity can be used by the plan job and the apply job
#    and by nothing else.
for GH_ENV in "${ENVIRONMENT}-plan" "${ENVIRONMENT}-apply"; do
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\":      \"github-${GH_ENV}\",
    \"issuer\":    \"https://token.actions.githubusercontent.com\",
    \"subject\":   \"repo:${ORG}/${REPO}:environment:${GH_ENV}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
done

# 3. Roles at subscription scope. The table below explains each one.
SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
for ROLE in "Contributor" "Storage Blob Data Contributor" "Role Based Access Control Administrator"; do
  az role assignment create --assignee "$APP_ID" --role "$ROLE" --scope "$SCOPE"
done

# 4. The three values §4 needs for this environment.
echo "AZURE_CLIENT_ID       = $APP_ID"
echo "AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
```

To re-run for an app that already exists, look up its ID instead of creating a second app registration —
`APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)` — and run only the steps you need.
Duplicate federated credentials and role assignments are rejected rather than doubled.

### What this creates

| Item | Value |
| --- | --- |
| App registration | `app-bte-dbx-<env>-terraform-001` |
| Federated credential 1 | Subject `repo:<org>/<repo>:environment:<env>-plan` |
| Federated credential 2 | Subject `repo:<org>/<repo>:environment:<env>-apply` |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience | `api://AzureADTokenExchange` |

The subject ties the credential to **one repository and one GitHub Environment**. A token issued for `dev-plan` cannot
be used by `prod-apply`, by another repository, or by a workflow that does not declare that environment.

> **If a run fails with `AADSTS700213`**, the GitHub organisation issues an immutable subject that embeds numeric IDs.
> Add a second credential per GitHub Environment in that form:
>
> ```bash
> ORG_ID=$(gh api "orgs/${ORG}" --jq .id)
> REPO_ID=$(gh api "repos/${ORG}/${REPO}" --jq .id)
> # subject: repo:${ORG}@${ORG_ID}/${REPO}@${REPO_ID}:environment:${GH_ENV}
> ```
>
> Registering both forms is harmless.

### Azure roles at subscription scope

| Role | Why it is needed |
| --- | --- |
| **Contributor** | Creates and manages the platform resources, registers the resource providers they need, and approves the Databricks private endpoint connections on the data storage account and the Private Link Services |
| **Storage Blob Data Contributor** | Maintains the storage account containers, and reads and writes the Terraform state; the backend authenticates with Microsoft Entra ID (`use_azuread_auth = true`), never with an account key |
| **Role Based Access Control Administrator** | Assigns the data Access Connector its four roles on the data storage account |

Owner can replace all three. The split above is the least privilege that works. Role Based Access Control Administrator
grants only `Microsoft.Authorization/roleAssignments` write and delete, which is narrower than User Access
Administrator.

### Optional roles in the hub subscription

The roles above cover the environment's own subscription only. Two integrations act on resources in the Baytex hub
subscription, and each needs one more role. Grant them only for the integrations Terraform should manage. Without them,
leave the matching values at their defaults, and Terraform makes no calls to the hub subscription.

| Integration | tfvars | Role | Scope |
| --- | --- | --- | --- |
| VNet peering, in either direction | `hub_vnet_id`, with `create_spoke_to_hub_peering` and `create_hub_to_spoke_peering` set to `true` | Network Contributor | The hub VNet |
| Private DNS registration of the storage private endpoints | `blob_private_dns_zone_ids` and `dfs_private_dns_zone_ids` | Private DNS Zone Contributor | Each `privatelink` zone, or the resource group or subscription that holds them |

Terraform addresses the hub VNet and zones by their full resource IDs, so the service principal needs these roles only,
not any other access to the hub subscription. Run the assignments as someone with Owner or User Access Administrator on
those scopes:

```bash
HUB_VNET_ID=<hub-vnet-resource-id>
BLOB_ZONE_ID=<privatelink.blob.core.windows.net-zone-resource-id>
DFS_ZONE_ID=<privatelink.dfs.core.windows.net-zone-resource-id>

az role assignment create --assignee "$APP_ID" --role "Network Contributor" --scope "$HUB_VNET_ID"
for ZONE_ID in "$BLOB_ZONE_ID" "$DFS_ZONE_ID"; do
  az role assignment create --assignee "$APP_ID" --role "Private DNS Zone Contributor" --scope "$ZONE_ID"
done
```

Then set the values in the environment's `TFVARS` and deploy. A new role assignment can take a few minutes to take
effect.

### Databricks account console

Each service principal, `app-bte-dbx-<env>-terraform-001`, must be added to the Databricks account **and granted the
Account Admin role**. Without it, the Network Connectivity Configuration API returns
*"API disabled without account admin"* and the deploy fails.

> Account console → **User management** → **Service principals** → add by Application ID → enable **Account admin**.

---

## 3. The six GitHub Environments

**Settings → Environments → New environment.** Create all six with these exact names:

```
dev-plan     dev-apply
test-plan    test-apply
prod-plan    prod-apply
```

The plan job and the apply job run in different GitHub Environments so that approval can be attached to the apply alone.
Planning changes nothing and needs no sign-off; applying is the decision.

---

## 4. Variables, per environment

Set these on **every one of the six environments** (Settings → Environments → pick one → **Environment variables**).
The plan and apply jobs each read the full set.

| Variable | Holds | Where the value comes from |
| --- | --- | --- |
| `AZURE_CLIENT_ID` | Service principal application ID | Printed at the end of §2 |
| `AZURE_TENANT_ID` | Entra tenant ID | Printed at the end of §2 |
| `AZURE_SUBSCRIPTION_ID` | Environment subscription | Printed at the end of §2 |
| `TF_STATE_RESOURCE_GROUP` | Resource group of the state storage account | `resource_group_name` in `BOOTSTRAP_TFVARS` |
| `TF_STATE_STORAGE_ACCOUNT` | State storage account name | `storage_account_name` in `BOOTSTRAP_TFVARS` |
| `TF_STATE_CONTAINER` | Blob container for state | `container_name` in `BOOTSTRAP_TFVARS`, normally `tfstate` |
| `TF_STATE_KEY` | Blob name of the platform state | `<env>/platform.tfstate` |
| `TFVARS` | **The entire `terraform.tfvars`** for `environments/<env>` | `environments/<env>/baytex.terraform.tfvars.example` |
| `BOOTSTRAP_TFVARS` | **The entire `terraform.tfvars`** for `bootstrap/<env>` | `bootstrap/<env>/baytex.terraform.tfvars.example` |

A repository variable, `TERRAFORM_VERSION`, sets the Terraform version every workflow installs. Set it once under
Settings → Secrets and variables → Actions → **Variables**.

### Why whole files live in variables

`TFVARS` holds the complete contents of `environments/<env>/terraform.tfvars`, and the workflow writes it to disk at run
time. This is what lets one set of `.tf` files serve three environments with no environment-specific values in git.
The format, every input and the example files are described in the [configuration reference](configuration-reference.md).

`BOOTSTRAP_TFVARS` does the same for `bootstrap/<env>`. It must name the **same** resource group, storage account and
container as the `TF_STATE_*` variables. If they disagree, the bootstrap workflow creates one storage account and stores
its state in another.

### Variables or secrets

The workflows read `TFVARS` and `BOOTSTRAP_TFVARS` as environment variables. Variables are visible to anyone who can view
the repository settings, and GitHub does not mask them in logs; secrets are masked. To store them as secrets, each
reusable workflow already carries the alternative line, commented out directly above the one in use:

```yaml
# TFVARS: ${{ secrets.TFVARS }}
TFVARS: ${{ vars.TFVARS }}
```

Swap which line is commented in these four files, then move the values from Environment *variables* to Environment
*secrets*:

- `.github/workflows/_terraform-plan.yml`
- `.github/workflows/_terraform-apply.yml`
- `.github/workflows/_bootstrap-plan.yml` (uses `BOOTSTRAP_TFVARS`)
- `.github/workflows/_bootstrap-apply.yml` (uses `BOOTSTRAP_TFVARS`)

---

## 5. Environment protection rules

| Rule | Where | Purpose |
| --- | --- | --- |
| **Required reviewers** | `-apply` environments | Pause for approval before Azure changes |
| **Deployment branches** | **All six** environments | Refuse runs from branches that may not deploy |

### Required reviewers

Settings → Environments → `<env>-apply` → **Required reviewers** → add one or more people or teams.

| Environment | Recommended | Effect |
| --- | --- | --- |
| `dev-apply` | Optional | Keeps iteration on dev fast when no reviewer is set |
| `test-apply` | 1 or more reviewers | Runs pause before applying to test |
| `prod-apply` | 1 or more reviewers | Runs pause before applying to prod |

Every workflow that changes an environment routes its apply through `<env>-apply`, so a reviewer here gates **deploy,
destroy, bootstrap and unlock** for that environment at once.

> **You cannot approve your own deployment** when the protection rule prevents self-review. If a run you started shows
> no Approve button, a second reviewer is needed.

Via the API:

```bash
gh api -X PUT repos/<org>/<repo>/environments/test-apply \
  -F "reviewers[][type]=User" -F "reviewers[][id]=<numeric-user-id>"
```

### Deployment branch policies

Settings → Environments → pick one → **Deployment branches** → *Selected branches* → add `main` and `hotfix/*`. Apply
this to **all six** environments.

Via the API:

```bash
REPO=<org>/<repo>
for ENV in dev-plan dev-apply test-plan test-apply prod-plan prod-apply; do
  gh api -X PUT "repos/$REPO/environments/$ENV" \
    -F "deployment_branch_policy[protected_branches]=false" \
    -F "deployment_branch_policy[custom_branch_policies]=true"
  for BRANCH in main 'hotfix/*'; do
    gh api -X POST "repos/$REPO/environments/$ENV/deployment-branch-policies" -f "name=$BRANCH"
  done
done
```

**Include the `-plan` environments.** Without a policy there, a run started from an unapproved branch still signs in to
Azure, takes the state lock and produces a full plan before anything refuses it. With the policy set, the job never
starts.

#### Why the workflows check branches as well

The workflows also compare the branch against an allow-list, for three reasons:

1. **A branch policy cannot vary per workflow.** Deploy, destroy, bootstrap and unlock share the same `<env>-apply`
   environment. Destroy and unlock are restricted to `main`, while deploy and bootstrap also permit `hotfix/*`; only the
   workflow can express that difference.
2. **It fails earlier.** The `Check the run is allowed` job stops a disallowed run in seconds, before any Azure sign-in.
3. **It is reviewable.** The workflow check is code, changed through a pull request, while an environment policy is a
   repository setting.

---

## 6. Branch protection on `main`

Settings → Branches → **Add branch protection rule** for `main`:

| Setting | Value | Why |
| --- | --- | --- |
| Require a pull request before merging | On | Nothing reaches `main` unreviewed |
| Required approvals | 1 or more | A second reviewer for every change |
| Require status checks to pass | On, with `Validate Terraform code / validate` | Broken code cannot merge |
| Require branches to be up to date | On | Checks ran against what will actually merge |
| **Include administrators** | **On** | Administrators follow the same rule |
| Allow force pushes | Off | History stays intact |
| Allow deletions | Off | `main` cannot be removed |

**Require only `Validate Terraform code / validate`.** The other pull request checks run only when the files they cover
change, and a required check that is skipped leaves a pull request unmergeable. A check name becomes selectable after it
has run once, so open a pull request first if the list is empty.

Via the API:

```bash
gh api -X PUT repos/<org>/<repo>/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Validate Terraform code / validate"]
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

## 7. Before the first production deployment

- [ ] `TFVARS` and `BOOTSTRAP_TFVARS` stored as secrets, if that is the chosen model (§4)
- [ ] Repository visibility is private or internal; on a public repository every Actions log and artefact, including
      plan output, is world-readable
- [ ] Required reviewers set on `test-apply` and `prod-apply`
- [ ] Deployment branch policies set on all six environments
- [ ] Branch protection on `main` requires `Validate Terraform code / validate` and includes administrators
- [ ] Each service principal holds **Account admin** in Databricks
- [ ] Where Terraform manages the hub peering or Private DNS registration, each service principal holds the hub roles
      in §2
- [ ] `TERRAFORM_VERSION` is set as a repository variable

---

## 8. Verify the configuration

This script only reads.

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

echo "== repository variables =="
gh api repos/$REPO/actions/variables --jq '.variables[].name'

echo "== reviewers on apply environments =="
for e in dev-apply test-apply prod-apply; do
  printf '%-12s ' "$e"
  gh api repos/$REPO/environments/$e \
    --jq '[.protection_rules[] | select(.type=="required_reviewers") | .reviewers[].reviewer.login] | join(", ")'
done

echo "== deployment branch policies (expected on all six) =="
for e in dev-plan dev-apply test-plan test-apply prod-plan prod-apply; do
  printf '%-12s ' "$e"
  gh api repos/$REPO/environments/$e/deployment-branch-policies \
    --jq '[.branch_policies[].name] | join(", ")' 2>/dev/null || echo "NONE SET"
done

echo "== branch protection on main =="
gh api repos/$REPO/branches/main/protection \
  --jq '{checks: .required_status_checks.contexts,
         approvals: .required_pull_request_reviews.required_approving_review_count,
         admins_included: .enforce_admins.enabled,
         force_pushes: .allow_force_pushes.enabled}'
```

| Check | Expected |
| --- | --- |
| Environments | All six present |
| Variables | All nine on every configured environment |
| Repository variables | `TERRAFORM_VERSION` |
| Reviewers | Set on `test-apply` and `prod-apply` |
| Deployment branch policies | `main, hotfix/*` on all six |
| Branch protection | `Validate Terraform code / validate` required, `admins_included: true`, `force_pushes: false` |

A missing variable surfaces at run time as a workflow failure naming it. A missing deployment branch policy surfaces as
nothing at all, which is why it is worth checking here.
