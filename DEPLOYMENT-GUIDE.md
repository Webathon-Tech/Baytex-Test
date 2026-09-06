# Deployment Guide

End-to-end instructions for deploying this Azure Databricks platform, from an
empty subscription to a validated environment.

There are two audiences here and they use the **same Terraform code**:

| Part | Who | Purpose |
| --- | --- | --- |
| [Part 1](#part-1--sandbox-rehearsal) | AMTRA / F12 | Rehearse the whole deployment in a personal subscription before touching Baytex |
| [Part 2](#part-2--real-deployment-dev--test--prod) | AMTRA + Baytex | The real DEV / TEST / PROD deployment |
| [Part 3](#part-3--running-a-second-environment) | AMTRA | How one codebase serves dev, test and prod |

> **Read [Part 0](#part-0--before-you-touch-anything) first.** It contains the
> single most important safety control in this repository.

---

## Part 0 — Before you touch anything

### 0.1 Subscription safety

A single `az login` commonly has access to **both** personal subscriptions and
Baytex production subscriptions at once. Confirm what you are pointed at before
every Terraform command:

```powershell
az account show --query "{name:name, id:id, tenant:tenantId}" -o json
```

Rules that prevent the worst-case mistake:

1. **Never rely on the "current" subscription.** Every `az` command in this guide
   passes `--subscription` explicitly, and every Terraform root pins
   `subscription_id`/`tenant_id` in its `.tfvars`.
2. **Never copy the tenant/subscription IDs out of `README.md` for a rehearsal.**
   Those point at Baytex's real tenant.
3. A subscription named `SUB-BTE-*` is **real Baytex**. Nothing in Part 1 may run
   against it.

### 0.2 Tooling

| Tool | Version used | Notes |
| --- | --- | --- |
| Terraform | 1.16.x | `required_version = ">= 1.10.0, < 2.0.0"` |
| Azure CLI | 2.88+ | needs the `databricks` extension for some checks |
| PowerShell | 5.1 or 7.x | scripts in `scripts/` require 7.2+ |

### 0.3 Provider versions — read before "upgrading"

| Provider | Pinned | Latest available | Why |
| --- | --- | --- | --- |
| `hashicorp/azurerm` | `~> 4.81.0` | 4.81.0 (5.3.0 exists) | **Do not move to 5.x.** The AVM module `Azure/avm-res-databricks-workspace/azurerm` v0.5.0 declares `azurerm >= 4.12, < 5.0.0`. Bumping the root to 5.x makes `terraform init` unsolvable. 4.81.0 is the newest 4.x, so this repo is already as current as the module allows. |
| `Azure/azapi` | `~> 2.4` | 2.12.0 | Resolves to latest automatically. |
| `databricks/databricks` | `~> 1.130.0` | 1.130.0 | Current. |
| AVM Databricks module | `0.5.0` | 0.5.0 | Current. |

**Databricks provider note:** this was previously pinned to `1.128.0` because a
freshly-downloaded `1.130.0` binary was blocked from executing by endpoint
security on an F12-managed Windows workstation (`fork/exec ... Access is
denied`) — a low-prevalence executable rule, not a code fault.

That no longer applies. `1.130.0` now downloads and executes normally, verified by
`terraform init` followed by `terraform validate`, which has to launch the
provider plugin to succeed. All five `versions.tf` files are on `~> 1.130.0`.

### 0.4 Required Azure resource providers

```powershell
$sub = "<YOUR-SUBSCRIPTION-ID>"
foreach ($ns in @("Microsoft.Databricks","Microsoft.Storage","Microsoft.Network","Microsoft.Compute","Microsoft.Insights","Microsoft.ManagedIdentity")) {
    az provider show --subscription $sub -n $ns --query "{ns:namespace,state:registrationState}" -o tsv
}
```

The `azurerm` provider is configured with `resource_provider_registrations = "none"`,
so **Terraform will not register these for you**. Anything showing
`NotRegistered` must be registered before you plan.

---

## Part 1 — Sandbox rehearsal

Goal: prove the exact code that ships to Baytex applies cleanly, in a
subscription where mistakes are free.

The Baytex build consumes an **existing** hub VNet, an **existing** Cisco
Firepower NVA, and **existing** on-premises databases. A personal subscription
has none of these, so Part 1 builds throwaway stand-ins first.

Everything in `sandbox/` is **gitignored** and never ships to the client.

### 1.1 Generate an SSH key for the proxy VMs

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\baytex-sandbox-haproxy-ed25519" -N '""' -C "sandbox-rehearsal"
```

### 1.2 Build the mock Baytex hub

```powershell
cd "<repo root>"
.\sandbox\Deploy-SandboxHub.ps1
```

This creates, in `rg-sbx-hub-cnc-001`:

| Resource | Address | Stands in for |
| --- | --- | --- |
| `vnet-sbx-hub-cnc-001` | `10.98.0.0/16` | Baytex hub VNet |
| `vm-sbx-hub-fwsim-01` | `10.98.0.4` | Cisco Firepower (IP forwarding + MASQUERADE) |
| `vm-sbx-hub-dbsim-01` | `10.98.1.4` | On-prem SQL (1433) and Oracle (1521) |
| `sandbox.internal` zone | — | Baytex corporate DNS |
| `privatelink.blob/dfs...` zones | — | Baytex central private DNS zones |
| NAT gateway | — | Hub egress (needed for VM agent/extensions) |

The script is idempotent and refuses to run against a `SUB-BTE-*` subscription.
It prints the exact `.tfvars` values to paste in the next step.

### 1.3 Bootstrap the Terraform state backend

```powershell
cd bootstrap\dev-state
Copy-Item terraform.tfvars.example terraform.tfvars
# edit: tenant_id, subscription_id, resource_group_name, storage_account_name,
#       and state_blob_data_contributor_principal_ids (your own object ID:
#       az ad signed-in-user show --query id -o tsv)
terraform init
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Storage account names are **globally unique**. Check first:

```powershell
az storage account check-name --name "<candidate>" -o json
```

### 1.4 Configure the platform root

```powershell
cd ..\..\environments\dev
Copy-Item terraform.tfvars.example terraform.tfvars
Copy-Item backend.hcl.example backend.hcl
```

For a rehearsal, the values that must differ from the shipped example are:

```hcl
tenant_id       = "<your tenant>"
subscription_id = "<your subscription>"
organization    = "sbx"            # keeps sandbox names clearly distinct

# from Deploy-SandboxHub.ps1 output
hub_subscription_id       = "<your subscription>"
hub_resource_group_name   = "rg-sbx-hub-cnc-001"
hub_vnet_name             = "vnet-sbx-hub-cnc-001"
hub_vnet_id               = "<printed by the script>"
cisco_firewall_private_ip = "10.98.0.4"
create_spoke_to_hub_peering = true

on_prem_routes = { onprem_sim = { address_prefix = "10.98.1.0/24" } }

on_prem_endpoints = {
  sqlsim = { frontend_ip = "10.99.83.11", pls_nat_ip = "10.99.83.21", listen_port = 1433,
             target_fqdn = "sqlsim.sandbox.internal", target_port = 1433,
             domain_name = "sqlsim.sandbox.internal" }
  orasim = { frontend_ip = "10.99.83.12", pls_nat_ip = "10.99.83.22", listen_port = 1521,
             target_fqdn = "orasim.sandbox.internal", target_port = 1521,
             domain_name = "orasim.sandbox.internal" }
}

pls_visibility_subscription_ids = ["<your subscription>"]  # so you can self-approve
dns_servers                     = ["168.63.129.16"]        # Azure default resolver
```

`databricks_account_id` stays a placeholder for now — see step 1.6.

### 1.5 Init, validate, plan

```powershell
terraform init -backend-config=backend.hcl
terraform fmt -recursive -check
terraform validate
terraform plan -out dev.tfplan
terraform show -no-color dev.tfplan > dev-plan.txt
```

Confirm in `dev-plan.txt`: **all creates, zero destroys**, and the only
subscription ID present is your own.

### 1.6 Apply — phase 1 of 2

The `modules/ncc` resources talk to the **Databricks account API**, which needs
an account ID that does not exist until the tenant's first workspace exists.
So the first apply deliberately excludes that module:

```powershell
terraform apply -lock-timeout=10m `
  -target=azurerm_resource_group.network -target=azurerm_resource_group.platform `
  -target=azurerm_resource_group.data -target=azurerm_resource_group.connectivity `
  -target=azurerm_resource_group.ops -target=azurerm_log_analytics_workspace.this `
  -target=module.network -target=module.data_foundation -target=module.haproxy `
  -target=module.databricks_workspace `
  -target=azurerm_monitor_diagnostic_setting.data_storage `
  -target=azurerm_monitor_diagnostic_setting.data_storage_blob `
  -target=azurerm_monitor_diagnostic_setting.load_balancer `
  -target=azurerm_monitor_diagnostic_setting.nat_gateway
```

> `-target` pulls in dependencies automatically, so the resource-group entries
> are belt-and-braces. Expect roughly 60 resources and 15–20 minutes.

### 1.7 Complete the "Baytex-owned" handoffs

These steps mirror work that is **Baytex's responsibility** in the real build.
Doing them yourself in the sandbox is what makes the test end-to-end.

**a. Hub side of the peering** — Terraform only creates the spoke side:

```powershell
terraform output -raw hub_side_peering_command
# then run the command it prints
```

**b. DNS** — link the private zones to the newly created spoke VNet:

```powershell
..\..\sandbox\Link-SandboxDnsToSpoke.ps1
```

### 1.8 Get the Databricks account ID

```powershell
terraform output databricks_workspace_url
```

Open that URL → sign in → click your username (top right) → **Manage Account**.
That deep-links into the account console already scoped to the right tenant. Copy
the **Account ID**.

> **This step is interactive by design.** There is no `az` or REST equivalent:
> `accounts.azuredatabricks.net` rejects an Entra bearer token
> (`BAD_REQUEST: Cookie DBAUTH not found`) and the account ID appears nowhere in
> the workspace's ARM properties. Budget a browser round-trip.

**The metastore ID, however, *is* scriptable.** Azure auto-creates a regional
Unity Catalog metastore, and the workspace will tell you which one it is:

```powershell
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv
$ws    = (terraform output -raw databricks_workspace_url)
curl.exe -s -H "Authorization: Bearer $token" "$ws/api/2.0/unity-catalog/metastore_summary"
```

Returns `metastore_id`, `name`, `region` and `global_metastore_id` — use this to
confirm the `existing_metastore_id` input rather than taking it on trust.

### 1.9 Apply — phase 2 of 2

Set the real `databricks_account_id` in `terraform.tfvars`, then:

```powershell
terraform plan -out ncc.tfplan
terraform apply ncc.tfplan
```

Only the six `module.ncc` resources should appear. Nothing from phase 1 should
change.

### 1.10 Approve the NCC private endpoints

Databricks raises private endpoint connections that land in **Pending**:

```powershell
terraform output -json ncc_private_endpoint_rules
terraform output -json private_link_service_ids
terraform output -raw data_storage_account_id
```

```powershell
cd ..\..\scripts
.\Approve-BaytexDatabricksPrivateEndpoints.ps1 `
  -SubscriptionId "<your subscription>" `
  -TargetResourceIds @("<storage account id>","<sqlsim PLS id>","<orasim PLS id>") `
  -ExpectedPrivateEndpointNames @("<endpoint_name values from the NCC output>")
```

> The storage account will show **four** private endpoint connections: two
> created directly by Terraform (auto-approved) and two raised by the Databricks
> control plane (these are the pending ones). That is expected.

### 1.11 Validate

One script runs the whole sweep. It uses `az vm run-command`, so it needs no
inbound SSH and works with `admin_ssh_source_cidrs = []`:

```powershell
.\sandbox\Invoke-SandboxValidation.ps1
```

It checks, and fails loudly on any of:

| # | Check | Proves |
| --- | --- | --- |
| 1 | Spoke↔hub peering is `Connected` | Both peering directions exist |
| 2 | `sqlsim/orasim.sandbox.internal` → `10.98.1.4` | Private DNS zone linked to the spoke |
| 3 | `<storage>.dfs.core.windows.net` → `10.99.82.x` | privatelink zone group works |
| 4 | Proxy VM → on-prem sim on 1433/1521 | Route table → NVA → on-prem path |
| 5 | `haproxy` active with listeners bound | cloud-init rendered a valid config |
| 6 | ILB frontends proxy through to the sims | Floating IP + HAProxy binding |

Because the sandbox has real listeners behind the mock NVA, these should **PASS**
— unlike a placeholder target, which can only prove Terraform ran.

The original `scripts\Test-BaytexDevConnectivity.ps1` is the client-facing
equivalent and still works:

```powershell
cd scripts
.\Test-BaytexDevConnectivity.ps1 `
  -SubscriptionId "<your subscription>" `
  -ConnectivityResourceGroupName "rg-sbx-dbx-dev-connectivity-cnc-001" `
  -ProxyVmNames @("vm-sbx-dbx-dev-cnc-001-proxy-01","vm-sbx-dbx-dev-cnc-001-proxy-02") `
  -Endpoints @{
      sqlsim = @{ fqdn = "sqlsim.sandbox.internal"; port = 1433 }
      orasim = @{ fqdn = "orasim.sandbox.internal"; port = 1521 }
  }
```

### 1.11a Validate from *inside* Databricks (the check that actually matters)

`Invoke-SandboxValidation.ps1` proves connectivity **from the HAProxy VMs**,
which sit in the proxy subnet. Databricks classic compute runs in the host and
container subnets, behind different NSGs (including Databricks' own injected
rules), so it is a genuinely different path — passing §1.11 does **not** prove
Databricks can reach SQL.

Start a small single-node cluster, then run this in a notebook:

```python
import socket, subprocess, json

def probe(host, port):
    out = {"target": f"{host}:{port}"}
    try:
        out["dns"] = socket.gethostbyname(host)
        s = socket.create_connection((host, port), timeout=10)
        out["banner"] = s.recv(64).decode(errors="replace").strip()
        s.close(); out["tcp"] = "OPEN"
    except Exception as e:
        out["tcp"] = f"FAIL({type(e).__name__})"
    return out

print(json.dumps({
    # classic compute -> route table -> firewall -> on-prem
    "direct":  [probe("sqlsim.sandbox.internal", 1433),
                probe("orasim.sandbox.internal", 1521)],
    # classic compute -> internal LB -> HAProxy -> on-prem
    "via_ilb": [probe("10.99.83.11", 1433), probe("10.99.83.12", 1521)],
    "storage": probe("stsbxdbxdevcnc001.dfs.core.windows.net", 443),
    "egress":  subprocess.run(["curl","-s","--max-time","15","https://ifconfig.me"],
                              capture_output=True, text=True).stdout.strip(),
    "nics":    subprocess.run(["bash","-lc","ip -4 -o addr show | awk '{print $2\"=\"$4}'"],
                              capture_output=True, text=True).stdout.strip(),
}, indent=2))
```

Expected, and what each result proves:

| Result | Proves |
| --- | --- |
| `sqlsim/orasim` → `SIMULATED-*-OK` | Classic compute reaches on-prem via the UDR → firewall path |
| `10.99.83.11/12` → `SIMULATED-*-OK` | The HAProxy/ILB tier works *from Databricks*, not just from the proxy VMs |
| storage DNS → `10.99.82.x`, TCP 443 open | Private endpoint + privatelink DNS resolve and are reachable from compute |
| `egress` == the NAT gateway public IP | Egress leaves via NAT, so the node has no public IP |
| `nics` shows only `10.99.81.x` | The driver sits in the container subnet, VNet-injected, no public interface |

For the Baytex run, substitute the real SQL/Oracle FQDNs and the real
`frontend_ip` values from `terraform output firewall_handoff`.

Still confirm by hand:

- [ ] Workspace UI loads and SSO works
- [ ] NCC rules report `ESTABLISHED` after approval (needs §1.9)
- [ ] Serverless compute reaches on-prem through the NCC/PLS path
- [ ] Diagnostics arrive in Log Analytics

### 1.12 Tear down (order matters)

```powershell
cd ..\environments\dev
terraform destroy                      # 1. spoke platform (also removes the peering)
cd ..\..\bootstrap\dev-state
terraform destroy                      # 2. state backend
..\..\sandbox\Remove-SandboxHub.ps1    # 3. mock hub
```

Order matters in both directions:

- Destroying the **state backend before the platform** orphans resources with no
  state left to manage them.
- Destroying the **hub before the spoke** leaves a peering pointing at a VNet
  that no longer exists. `Remove-SandboxHub.ps1` checks for a live spoke peering
  and refuses unless you pass `-Force`.

---

## Part 2 — Real deployment in the client subscription, from scratch

This is the full procedure for deploying into a Baytex subscription. Every step
below was executed end-to-end in the sandbox rehearsal, including NCC, so the
gotchas called out here are ones that were actually hit — not theoretical.

> **Difference from Part 1:** the hub, firewall, DNS and on-premises systems
> already exist and are **Baytex-owned**. You create only the spoke and hand off
> the rest.

### 2.0 Workstation prerequisites

| Requirement | Why |
| --- | --- |
| Terraform 1.10–1.x | `required_version` |
| Azure CLI 2.60+ | provider auth and endpoint approval |
| **PowerShell 7.2+** (`pwsh`) | `scripts/*.ps1` declare `#Requires -Version 7.2`. Windows PowerShell 5.1 **will not run them** |
| **Run az/approval commands from PowerShell, not Git Bash** | Git Bash (MSYS) rewrites arguments that look like Unix paths, so `--id /subscriptions/...` becomes a mangled Windows path and Azure returns an HTML `Bad Request` |

### 2.1 What Baytex must supply before you can plan

See `docs/required-inputs.md`. The blocking ones:

| Input | Notes |
| --- | --- |
| CIDRs for the VNet + 4 subnets | ⚠️ Must come from the correct landing-zone block — see [ARCHITECTURE.md §1.3](ARCHITECTURE.md). The shipped example previously pointed at **OT Prod** space |
| Hub VNet resource ID | And who creates each peering direction |
| Cisco firewall private IP | `10.40.240.36` per the current-state diagram |
| Approved on-premises route prefixes | Drives `on_prem_routes` |
| Corporate DNS servers + privatelink zone IDs | `172.19.65.x` per the diagram |
| **Databricks account ID** | §2.3 — browser-only, no API |
| Existing regional metastore ID | Verifiable via API, see §2.3 |
| SSH public key + admin source ranges | |
| **PLS visibility decision** | §2.5 — fail-closed, and the obvious answer is wrong |
| Exact destination matrix | FQDN + port per system |

### 2.2 Confirm the deployment identity

The identity running Terraform needs **both**:

1. **Azure**: rights to create the resource groups, network, storage, VMs, and —
   critically — the `Storage Blob Data Contributor` role assignment for the
   Access Connector. Role assignment requires `Microsoft.Authorization/roleAssignments/write`
   (Owner or User Access Administrator), which Contributor alone does **not** grant.
2. **Databricks**: **account admin** on the Databricks account, required to create
   the NCC. Entra ID **Global Administrators** get this automatically on first
   account-console sign-in; anyone else must be granted it by an existing account
   admin.

Verify Databricks account admin before planning — this call must return HTTP 200:

```powershell
$sub   = "<subscription-id>"
$acct  = "<databricks-account-id>"
$token = az account get-access-token --subscription $sub `
           --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv
curl.exe -s -o NUL -w "%{http_code}`n" -H "Authorization: Bearer $token" `
  "https://accounts.azuredatabricks.net/api/2.0/accounts/$acct/workspaces"
```

`200` = the account ID is right **and** you hold account admin. `401/403` = not
an account admin. `400/404` = wrong account ID.

### 2.3 Get the Databricks account ID (browser-only)

There is **no `az`, CLI or REST route** to discover this. `accounts.azuredatabricks.net`
rejects Entra bearer tokens without an interactive `DBAUTH` cookie, and the ID
appears nowhere in the workspace ARM properties, SCIM `/Me`, `metastore_summary`
or the workspace UI bootstrap. Budget a browser round-trip.

1. Open any existing Baytex workspace
2. Username (top-right) → **Manage Account** — this opens a **new site**,
   `accounts.azuredatabricks.net`
3. The **Account ID** is a **UUID** at bottom-left under your profile, also in the
   URL as `?account_id=<uuid>`

> **Do not confuse it with the workspace ID.** The workspace ID is a 16-digit
> number embedded in `adb-<workspaceid>.NN.azuredatabricks.net`. The account ID
> is a 36-character UUID. Terraform derives the workspace ID itself.

The **metastore ID**, by contrast, *is* scriptable:

```powershell
curl.exe -s -H "Authorization: Bearer $token" `
  "https://<workspace-url>/api/2.0/unity-catalog/metastore_summary"
```

### 2.4 Populate the inputs

```powershell
cd environments\dev
Copy-Item terraform.tfvars.example terraform.tfvars
Copy-Item backend.hcl.example backend.hcl
```

Replace every placeholder. Two fields are easy to get subtly wrong:

**`target_fqdn` vs `domain_name` are different things.**

| Field | Consumed by | Constraint |
| --- | --- | --- |
| `target_fqdn` | HAProxy backend | Must resolve **from the proxy VMs** via corporate DNS |
| `domain_name` | Databricks NCC private endpoint rule | Databricks **validates** it and rejects reserved TLDs (`.internal`, `.local`) with `Cannot use these domain names: …` |

For Baytex both are normally the same real FQDN (`sqlbidb01yyc.baytexenergy.com`),
which satisfies both. They only diverge if an internal-only TLD is in play.

### 2.5 ⚠️ Private Link Service visibility — the obvious answer is wrong

NCC private endpoints are created from a **Microsoft/Databricks-managed
subscription**, *not* from Baytex's. Setting `pls_visibility_subscription_ids`
to a Baytex subscription makes the PLS **invisible to Databricks**, and the
endpoint rules fail.

Two supported options:

```hcl
# PREFERRED — pin the Databricks-managed consumer subscription.
# Confirmed for canadacentral during the sandbox rehearsal:
allow_all_subscriptions_pls_visibility = false
pls_visibility_subscription_ids        = ["d6477524-1928-4a60-80fc-4df76eaa7749"]
pls_auto_approval_subscription_ids     = []   # keep manual approval

# FALLBACK — all-subscription visibility WITH manual approval.
# Safe because nothing connects until explicitly approved.
allow_all_subscriptions_pls_visibility = true
pls_visibility_subscription_ids        = []
pls_auto_approval_subscription_ids     = []
```

> `d6477524-1928-4a60-80fc-4df76eaa7749` (resource group `prod-canadacentral-snp-1`)
> is the Databricks control-plane subscription observed for **canadacentral**.
> **Confirm it for your region** by applying with the fallback first and reading
> the subscription off the resulting pending connections (§2.8), then pin it.

### 2.6 Init, validate, plan

```powershell
terraform init -backend-config=backend.hcl
terraform fmt -recursive -check
terraform validate
terraform plan -out dev.tfplan
terraform show -no-color dev.tfplan > dev-plan.txt
```

Review against `docs/pre-deployment-checklist.md`: all creates, no destroys, and
no subscription ID other than the intended one.

### 2.7 Apply

Set this for every plan/apply — the CI workflows set it too:

```powershell
$env:DATABRICKS_TF_ENABLED_PF_RESOURCES = "databricks_mws_ncc_private_endpoint_rule"
```

**If the tenant already has a Databricks account** (Baytex does), a single apply
works because `databricks_account_id` is known up front:

```powershell
terraform apply dev.tfplan
```

**If it does not** (a fresh tenant), use the two-phase apply in §1.6/§1.9.

> The `databricks` provider is pinned to the real tenant via
> `azure_tenant_id = var.tenant_id`. Without it the provider defaults to
> `azure_tenant_id = "common"` and the apply fails with
> `cannot get access token: Status_InteractionRequired`. This is already fixed in
> `providers.tf` — do not remove it.

### 2.8 Hand off to Baytex

```powershell
cd ..\..\scripts
pwsh .\Export-BaytexDevHandoff.ps1        # requires PowerShell 7.2+
```

Baytex Infrastructure then completes:

1. **Hub-side peering** — run the emitted `hub_side_peering_command` verbatim
2. **Firewall rules** — from `firewall_handoff` (source CIDRs, next hop, matrix)
3. **On-premises return routes** for the new spoke CIDR
4. **DNS** — corporate resolution plus privatelink zone links to the spoke VNet

Confirm peering reaches `Connected` (not `Initiated` — that means only one side
exists):

```powershell
az network vnet peering list -g <network-rg> --vnet-name <spoke-vnet> `
  --subscription <sub> --query "[].{name:name,state:peeringState}" -o table
```

### 2.9 Approve the NCC private endpoints

The NCC raises private endpoint connections that sit **Pending** until approved.
Until then the rules stay `PENDING` and serverless cannot reach anything.

```powershell
terraform output -json ncc_private_endpoint_rules   # endpoint names + states
```

Approve with the repo script (PowerShell 7.2+), which only approves endpoints
whose names match this deployment's own outputs:

```powershell
pwsh .\scripts\Approve-BaytexDatabricksPrivateEndpoints.ps1 `
  -SubscriptionId "<sub>" `
  -TargetResourceIds @("<storage-account-id>","<pls-id-1>","<pls-id-2>") `
  -ExpectedPrivateEndpointNames @("<endpoint names from the output above>")
```

Notes from the rehearsal:

- The storage account shows **two extra** connections beyond the Databricks ones
  — those are Terraform's own private endpoints, already `Approved`. Leave them.
- **Run from PowerShell, not Git Bash** (§2.0).
- `az network private-endpoint-connection approve --id …` has an internal CLI bug
  (`'NoneType' object is not subscriptable`) in some versions; the PowerShell
  path above worked reliably.

Then confirm every rule is `ESTABLISHED`:

```powershell
curl.exe -s -H "Authorization: Bearer $token" `
  "https://accounts.azuredatabricks.net/api/2.0/accounts/$acct/network-connectivity-configs/<ncc-id>/private-endpoint-rules"
```

### 2.10 Validate

Run §1.11 **and** §1.11a — the in-cluster probe is the one that proves Databricks
itself reaches SQL, substituting the real FQDNs and frontend IPs. Then hand
`unity_catalog_handoff` to Baytex BI.

### 2.11 What this Terraform deliberately does **not** do

It creates only the spoke side of the peering and never touches the hub,
firewall, VPN, corporate DNS, or any existing resource. Unity Catalog objects
are Baytex BI's, via a separate state — see
`baytex-bi-owned-unity-catalog-example/`.

---

## Part 3 — Running a second environment

The root module is fully parameterised: **every** resource name derives from
`organization` / `workload` / `environment` / `region_short` / `instance`.
Switching `environment = "dev"` to `"test"` renames all ~25 resource types
(verified by planning both).

### 3.1 What changes per environment

| Input | Why it must change |
| --- | --- |
| `environment` | Drives every resource name |
| `subscription_id` | Each environment is a separate subscription |
| `vnet_cidr` + 4 subnet CIDRs | Must not overlap other spokes |
| `proxy_vm_private_ips`, `frontend_ip`, `pls_nat_ip` | Must sit inside the new proxy subnet |
| `data_storage_account_name`, `workspace_root_storage_account_name` | **Globally unique** across Azure |
| `backend.hcl` → `key` | Separate state file per environment |
| `on_prem_endpoints` | Test/prod point at different database hosts |

Everything else — module code, naming logic, NSG rules, HAProxy templates — is
unchanged.

### 3.2 Recommended layout

Keep one root and one `.tfvars` per environment:

```text
environments/
  dev/    terraform.tfvars   backend.hcl   # key = "dev/platform.tfstate"
  test/   terraform.tfvars   backend.hcl   # key = "test/platform.tfstate"
  prod/   terraform.tfvars   backend.hcl   # key = "prod/platform.tfstate"
```

To add TEST, copy `environments/dev/*.tf` unchanged and supply a new
`terraform.tfvars`. Because the `.tf` files contain no environment literals,
they are copied verbatim.

> The CI workflows are currently scoped to `environments/dev/**`. Adding TEST or
> PROD means adding matching workflow paths and a matching protected GitHub
> Environment.

### 3.3 Verifying before you commit

```powershell
terraform plan -var environment=test `
  -var data_storage_account_name=<unique> `
  -var workspace_root_storage_account_name=<unique>
```

Scan the plan for any name that still contains `dev`. There should be none.

---

## Appendix A — Fixes applied to this repository

All of the below were found by actually deploying this code into a sandbox
subscription against a mock hub. **Every one of them passed `terraform fmt`,
`terraform validate` and `terraform plan`** — they only surfaced at apply time
or, worse, at runtime after a fully successful apply.

Final sandbox result after the fixes: **11/11 end-to-end checks passing**,
including internal load balancer front ends proxying real TCP through to the
simulated on-premises hosts.

Issues found while rehearsing, and what was changed:

| Issue | Impact | Fix |
| --- | --- | --- |
| `versioning_enabled = true` + `change_feed_enabled = true` on an `is_hns_enabled` (ADLS Gen2) account | **Hard blocker.** The data lake storage account cannot be created: `` `versioning_enabled` can't be true when `is_hns_enabled` is true ``. Passes `validate` **and `plan`** — only fails at apply, after the account is half-created and left tainted | Both set to `false`, with a comment. Soft delete (blob + container, 30 days) is supported with HNS and still provides the data protection |
| `databricks` provider had no `azure_tenant_id` | **NCC apply always fails.** The provider defaulted to `azure_tenant_id = "common"` and asked the Azure CLI for a token against the common endpoint, which cannot be issued silently: `cannot get access token: Status_InteractionRequired`. `azurerm` and `azapi` were both pinned to the tenant; only `databricks` was not | Added `azure_tenant_id = var.tenant_id` to the account provider |
| CRLF line endings in `modules/haproxy-tier/templates/*.tftpl` | **Silent total failure of the HAProxy tier.** On a Windows checkout (`core.autocrlf=true`) `templatefile()` embeds `\r`, so the cloud-init script's shebang becomes `#!/usr/bin/env bash\r` → `/usr/bin/env: 'bash\r': No such file or directory`. `dummy0` is never created, the ILB frontend IPs are never bound to loopback, HAProxy cannot bind its listeners and dies — **while `terraform apply` reports complete success** | Added `.gitattributes` pinning `*.tftpl`/`*.sh`/`*.yaml` to `eol=lf`, **and** a defensive `replace(..., "\r\n", "\n")` around all three `templatefile()` calls so the module is correct regardless of checkout settings |
| HAProxy start race + systemd rate limit | **HAProxy never starts.** The `haproxy` package auto-starts on install, before `baytex-lb-ips.service` has added the ILB floating IPs to `dummy0`, so it dies with `cannot bind socket (Cannot assign requested address)`. Five such failures exhaust systemd's `StartLimitBurst`, and the `systemctl restart haproxy` at the end of `runcmd` is then refused with `Start request repeated too quickly` — the tier stays dead even once the IPs exist and the config is valid | Added `net.ipv4.ip_nonlocal_bind = 1` so HAProxy can bind the floating IPs irrespective of ordering, plus `systemctl reset-failed haproxy` before the restart to clear the rate limiter |
| `terraform fmt -check` failed in 6 files | Both CI workflows fail on the **first** pipeline run | `terraform fmt -recursive` |
| AVM module's `data "azurerm_resource_group" "parent"` resolved at plan time | **First `plan` against empty state always fails** with "Resource Group not found" | Added `depends_on = [azurerm_resource_group.platform]` to the module block |
| `computer_name = "dbxdevproxy..."` hardcoded | TEST/PROD proxy VMs would carry `dev` hostnames | Derived from `var.name_prefix` |
| Action group `short_name = "dbxdev"` hardcoded | Same, for alerting | Derived via `substr("${workload}${environment}", 0, 12)` (Azure caps this at 12 chars) |
| `enable_floating_ip` on `azurerm_lb_rule` | Deprecated; removed in azurerm 5.x | Renamed to `floating_ip_enabled` |
| CI pinned Terraform 1.15.9 | Behind current | Raised to 1.16.1 |

## Appendix B — Script inventory

**`scripts/` — ships to Baytex.** Client-facing tooling referenced by the
runbook and the Part 2 handoffs.

| Script | Purpose |
| --- | --- |
| `Approve-BaytexDatabricksPrivateEndpoints.ps1` | Approve only the NCC-raised private endpoints whose names match the deployment outputs |
| `Export-BaytexDevHandoff.ps1` | Package the peering/firewall/DNS/Unity Catalog outputs as JSON for Baytex |
| `Test-BaytexDevConnectivity.ps1` | Prove classic compute can reach each approved on-prem destination |

**`sandbox/` — gitignored, never ships.** Rehearsal scaffolding that fakes the
parts of Baytex's estate a personal subscription does not have.

| Script | Purpose |
| --- | --- |
| `Deploy-SandboxHub.ps1` | Build the mock hub: VNet, NVA simulator, on-prem DB simulator, NAT gateway, private DNS zones. Idempotent; refuses to run against `SUB-BTE-*` |
| `Link-SandboxDnsToSpoke.ps1` | Link the three private DNS zones to the Terraform-created spoke (stands in for Baytex's DNS handoff) |
| `Invoke-SandboxValidation.ps1` | Six-check end-to-end sweep — peering, DNS, privatelink, routing, HAProxy, ILB |
| `cloud-init-*.yaml` | Cloud-init for the two simulator VMs (no package downloads required) |
| `Remove-SandboxHub.ps1` | Tear down the mock hub; warns if the spoke peering still exists |

## Appendix C — Known constraints

1. **azurerm cannot go to 5.x** until the AVM Databricks module supports it
   (§0.3). This is the single biggest upgrade blocker in the repo.
2. **NCC needs a two-phase apply** on any tenant without an existing Databricks
   workspace (§1.6/§1.9). Baytex already has an account, so their DEV run may be
   single-phase — confirm the account ID before planning.
3. **PLS visibility is fail-closed.** `terraform plan` refuses to build the
   Private Link Services until either `pls_visibility_subscription_ids` is
   non-empty or `allow_all_subscriptions_pls_visibility` is explicitly set.
4. **Storage account names are global.** Always `az storage account check-name`
   before committing a new environment's `.tfvars`.
5. **A successful apply is not acceptance.** Connectivity, failover, DNS and a
   representative workload must all be validated — see
   `docs/deployment-runbook.md` Gate 7.
6. **`plan` does not prove `apply` will work.** The ADLS Gen2 versioning bug in
   Appendix A passed `fmt`, `validate` *and* `plan`, then failed mid-apply — the
   storage account was created, its `blob_properties` update rejected, and the
   resource left **tainted** (next plan shows `1 to destroy`). Rehearsing in a
   sandbox is the only way to catch this class of defect before the client does.
7. **Check the real exit code.** In a shell chain like
   `terraform apply > log 2>&1; tail log`, the chain's status is `tail`'s, not
   Terraform's — a failed apply can look like success. Capture `$?` immediately
   after the `terraform` call, or grep the log for `Error:`.
8. **A green apply does not mean the VMs work.** The CRLF defect in Appendix A
   produced a fully successful `terraform apply` with a completely dead HAProxy
   tier. Anything driven by cloud-init needs runtime proof, not just a
   provisioning result — which is why §1.11 checks `systemctl is-active haproxy`
   and real TCP responses rather than trusting Terraform's output.

### Fast triage for a dead HAProxy tier

```bash
cloud-init status --long          # 'error' => runcmd/scripts_user failed
systemctl status haproxy          # bind failures show here
systemctl status baytex-lb-ips    # status=127 => CRLF shebang
ip -4 addr show dummy0            # missing => frontend IPs never bound
haproxy -c -f /etc/haproxy/haproxy.cfg
```

`haproxy.cfg` reporting "Configuration file is valid" while the service still
fails means the config is fine and the **bind addresses are missing** — i.e.
`baytex-lb-ips.service` did not run.
