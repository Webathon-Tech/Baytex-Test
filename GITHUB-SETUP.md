# GitHub Setup — Everything to Configure in the Repository

All the GitHub-side configuration the pipelines depend on: environments,
variables, protection rules and repository settings. None of it lives in the
repository, so a fresh clone has working *code* and a non-working *pipeline*
until this is done.

Companion to [PIPELINES.md](PIPELINES.md) (how the workflows behave) and
[PIPELINE-SETUP.md](PIPELINE-SETUP.md) (the Azure and Databricks prerequisites).

**Who needs to do this:** somebody with **admin** on the repository.

---

## 0. Do the Azure side first

Two things must exist before any of this is useful, both covered in
[PIPELINE-SETUP.md](PIPELINE-SETUP.md):

1. **A service principal per environment**, created by
   `scripts/New-GitHubOidcServicePrincipal.ps1`. It prints the
   `AZURE_CLIENT_ID` you need below.
2. **Databricks account admin** granted to each of those principals, or
   `module.ncc` fails.

You cannot configure GitHub meaningfully without the client IDs from step 1.

---

## 1. Create six environments

`Settings → Environments → New environment`, six times:

```
dev-plan     dev-apply
test-plan    test-apply
prod-plan    prod-apply
```

Two per stage is not redundancy. A federated credential is bound to a subject
containing the environment name, so the credential that can *plan* an environment
is a different credential from the one that can *apply* it — and it gives a place
to hang an approval that affects applies only.

---

## 2. Set variables on every environment

Each of the six needs **all eight**. `plan` and `apply` for the same stage take
identical values.

| Variable | Value | Where it comes from |
| --- | --- | --- |
| `AZURE_CLIENT_ID` | app ID for that environment | printed by the SP script |
| `AZURE_TENANT_ID` | tenant GUID | your tenant |
| `AZURE_SUBSCRIPTION_ID` | that environment's subscription | one per environment in a real deployment |
| `TF_STATE_RESOURCE_GROUP` | e.g. `rg-bte-dbx-dev-tfstate-cnc-001` | you choose; the bootstrap workflow creates it |
| `TF_STATE_STORAGE_ACCOUNT` | e.g. `stbtedbxdevtfcnc001` | globally unique |
| `TF_STATE_CONTAINER` | `tfstate` | convention |
| `TF_STATE_KEY` | `<env>/platform.tfstate` | one key per environment |
| `TFVARS` | the whole `terraform.tfvars` for that environment | see §5 |

> The workflows read `vars.*`, never hard-coded values. That is what lets one
> workflow serve three environments: the job declares `environment: dev-apply`
> and GitHub injects that environment's values.

---

## 3. Protection rules

This is the part that actually enforces anything.

| Environment | Required reviewers | Deployment branches |
| --- | --- | --- |
| `dev-plan` | none | **any** |
| `test-plan` | none | **any** |
| `prod-plan` | none | **any** |
| `dev-apply` | none | `main`, `hotfix/*` |
| `test-apply` | **yes** | `main`, `hotfix/*` |
| `prod-apply` | **yes** | `main`, `hotfix/*` |

Three things worth understanding:

**Plan environments must allow any branch.** Pull-request plans run from feature
branches. Restricting `*-plan` breaks every PR check.

**`dev-apply` gets a branch policy but no reviewer.** Deploying dev should stay
fast, but it should still only deploy reviewed code.

**Branch policies duplicate a check already in the workflows.** That is
deliberate: the workflow guard can be edited by anyone who can edit workflows;
the environment policy is repository settings and needs admin.

> Deployment protection rules require a **public** repository on the Free plan,
> or **Pro / Team / Enterprise** on a private one. If the reviewer section is
> missing, that is why — the environments and variables still work, you just lose
> the gate.

---

## 4. Protect `main` — do not skip this

Without it, anyone with write access can push straight to `main`, which bypasses
every PR check *and* puts unreviewed code on the branch that applies run from.

`Settings → Branches → Add branch ruleset` (or classic branch protection) on
`main`:

- **Require a pull request before merging** — at least 1 approval
- **Require status checks to pass**, selecting:
  - `Root parity (report only)`
  - `plan-dev / Plan dev`
  - (add `plan-test` / `plan-prod` once those environments are bootstrapped)
- **Do not allow bypassing the above settings**
- Block force pushes

Everything else in this document is pointless without this. The workflow ref
guards restrict applies to `main` and `hotfix/*` — which only means anything if
getting code onto `main` requires review.

---

## 5. `TFVARS` — variable or secret

Currently a **variable** so its content is visible while testing. Each workflow
has the secret line commented directly above it:

```yaml
# TFVARS: ${{ secrets.TFVARS }}   # <- switch back for client delivery
TFVARS: ${{ vars.TFVARS }}
```

**Switch it back to a secret before any real deployment.** GitHub masks secrets in
logs automatically and does **not** mask variables. On a public repository that
masking is genuinely protective.

To switch: uncomment the `secrets.` line and delete the `vars.` line in
`_terraform-plan.yml`, `_terraform-apply.yml` and `terraform-destroy.yml`, then
move the value:

```bash
gh secret   set TFVARS --env dev-apply --repo <ORG>/<REPO> < environments/dev/terraform.tfvars
gh variable delete TFVARS --env dev-apply --repo <ORG>/<REPO>
```

Nothing in the file is a credential — the SSH key is a public key — but the
topology, subscription IDs and storage names are not worth publishing.

---

## 6. Repository settings

| Setting | Recommended | Why |
| --- | --- | --- |
| Visibility | **private** for a client repo | Content, git history, Actions logs and artefacts are all public otherwise |
| Default branch | `main` | The ref guards and workflow triggers assume it |
| Allow forking | off for a client repo | Fork PRs cannot read secrets, so their plan jobs fail noisily anyway |
| Actions permissions | allow `actions/*` and `azure/login`, `hashicorp/setup-terraform` | The workflows use nothing else |

> On a **public** repository every Actions log and artefact is world-readable.
> Terraform plan output is a complete resource inventory. Weigh that against the
> free protection rules before choosing public.

---

## 7. Doing it with the CLI

Everything above, scripted. Replace the placeholders and run once per
environment. These are the exact calls used to configure this repository.

```bash
R=<ORG>/<REPO>
TENANT=<tenant-guid>

# --- per environment -------------------------------------------------------
for e in dev test prod; do
  SUB=<subscription-id-for-$e>
  CID=<client-id-for-$e>          # from New-GitHubOidcServicePrincipal.ps1
  for p in plan apply; do
    ENV="$e-$p"
    gh api -X PUT "repos/$R/environments/$ENV" --silent

    gh variable set AZURE_CLIENT_ID          --env "$ENV" --repo "$R" --body "$CID"
    gh variable set AZURE_TENANT_ID          --env "$ENV" --repo "$R" --body "$TENANT"
    gh variable set AZURE_SUBSCRIPTION_ID    --env "$ENV" --repo "$R" --body "$SUB"
    gh variable set TF_STATE_RESOURCE_GROUP  --env "$ENV" --repo "$R" --body "rg-bte-dbx-$e-tfstate-cnc-001"
    gh variable set TF_STATE_STORAGE_ACCOUNT --env "$ENV" --repo "$R" --body "stbtedbx${e}tfcnc001"
    gh variable set TF_STATE_CONTAINER       --env "$ENV" --repo "$R" --body "tfstate"
    gh variable set TF_STATE_KEY             --env "$ENV" --repo "$R" --body "$e/platform.tfstate"

    # TFVARS: use ONE of these. Secret is correct for a real deployment.
    gh secret   set TFVARS --env "$ENV" --repo "$R" < "environments/$e/terraform.tfvars"
    # gh variable set TFVARS --env "$ENV" --repo "$R" < "environments/$e/terraform.tfvars"
  done
done

# --- branch policy on all three apply environments -------------------------
for ENV in dev-apply test-apply prod-apply; do
  gh api -X PUT "repos/$R/environments/$ENV" \
    -F "deployment_branch_policy[protected_branches]=false" \
    -F "deployment_branch_policy[custom_branch_policies]=true" --silent
  for B in main "hotfix/*"; do
    gh api -X POST "repos/$R/environments/$ENV/deployment-branch-policies" \
      -f "name=$B" -f "type=branch" --silent
  done
done

# --- required reviewers on test and prod only ------------------------------
REVIEWER_ID=$(gh api users/<github-username> --jq .id)
for ENV in test-apply prod-apply; do
  gh api -X PUT "repos/$R/environments/$ENV" \
    -F "reviewers[][type]=User" -F "reviewers[][id]=$REVIEWER_ID" \
    -F "deployment_branch_policy[protected_branches]=false" \
    -F "deployment_branch_policy[custom_branch_policies]=true" --silent
done
```

> Re-running is safe. `PUT .../environments/<name>` is idempotent, and
> `gh variable set` overwrites.
>
> One caveat: `PUT` on an environment **replaces** its protection rules. Setting a
> branch policy without re-sending `reviewers` clears the reviewers. Always send
> both together, as the last block does.

---

## 8. Verify

```bash
R=<ORG>/<REPO>

gh api "repos/$R/environments" --jq '.environments[].name'

for e in dev-plan dev-apply test-plan test-apply prod-plan prod-apply; do
  printf '%-11s rules=%-38s ' "$e" \
    "$(gh api "repos/$R/environments/$e" --jq '[.protection_rules[]?.type]|join(",")//"none"')"
  gh api "repos/$R/environments/$e/deployment-branch-policies" \
    --jq '[.branch_policies[]?.name]|join(", ")' 2>/dev/null || echo "any branch"
done

gh api "repos/$R/environments/dev-apply/variables" --jq '.variables[].name' | sort
```

Expected:

```
dev-plan     rules=none                                  any branch
dev-apply    rules=branch_policy                         hotfix/*, main
test-plan    rules=none                                  any branch
test-apply   rules=required_reviewers,branch_policy      hotfix/*, main
prod-plan    rules=none                                  any branch
prod-apply   rules=required_reviewers,branch_policy      hotfix/*, main
```

A `404` from the branch-policies endpoint on the `*-plan` environments is
**correct** — they have no policy, which is what lets PR plans run from feature
branches.

---

## 9. Handover checklist

- [ ] Service principals created, one per environment
- [ ] Each SP granted **Databricks account admin**
- [ ] Six environments created
- [ ] All eight variables set on each
- [ ] `TFVARS` moved back to a **secret**
- [ ] Branch policy (`main`, `hotfix/*`) on all three `*-apply`
- [ ] Required reviewers on `test-apply` and `prod-apply`
- [ ] `*-plan` environments left unrestricted
- [ ] **Branch protection on `main`** with required PR review and status checks
- [ ] Repository set to **private**
- [ ] Actions run history reviewed or cleared if the repo was ever public

Then run **Terraform Bootstrap State Backend** for each environment, and the
pipelines are live.
