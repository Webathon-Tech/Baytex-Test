# Local Development

What you can and should do from a laptop, and what you deliberately cannot.

**Terraform is never applied locally.** Every `apply` goes through GitHub Actions
so that state, identity and audit trail live in one place. Locally you can read
state and produce a plan for inspection, but the pipeline owns changes.

The one genuinely local task is **building the mock on-premises environment** for
a rehearsal. In a real client deployment even this is unnecessary — the hub,
firewall and on-premises systems already exist.

---

## Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| Azure CLI | 2.60+ | `az login` |
| Terraform | 1.16.x | only for read-only plans |
| GitHub CLI | any | `gh auth login` |
| PowerShell | 5.1 or 7.x | `scripts/*.ps1` except the SP script need **7.2+** (`pwsh`) |

> **Run `az` from PowerShell, not Git Bash.** MSYS rewrites arguments that look
> like Unix paths, so `--id /subscriptions/...` arrives mangled. In Git Bash,
> `export MSYS_NO_PATHCONV=1` first.

---

## Building the mock on-premises environment

The real deployment consumes an existing hub VNet, an existing Cisco Firepower
NVA and existing on-premises databases. A personal subscription has none of
these, so the sandbox scripts stand up throwaway equivalents.

```powershell
# 1. SSH key for the HAProxy VMs
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\baytex-sandbox-haproxy-ed25519" -N '""'

# 2. Build the mock hub
.\sandbox\Deploy-SandboxHub.ps1
```

This creates, in `rg-sbx-hub-cnc-001`:

| Resource | Address | Stands in for |
| --- | --- | --- |
| `vnet-sbx-hub-cnc-001` | `10.98.0.0/16` | the hub VNet |
| `vm-sbx-hub-fwsim-01` | `10.98.0.4` | Cisco Firepower (IP forwarding + MASQUERADE) |
| `vm-sbx-hub-dbsim-01` | `10.98.1.4` | on-prem SQL (1433) and Oracle (1521) |
| `sandbox.baytexdemo.net` | — | corporate DNS |
| `privatelink.blob/dfs...` | — | central private DNS zones |
| NAT gateway | — | hub egress |

The script refuses to run against a subscription named `SUB-BTE-*`, and prints
the exact `.tfvars` values for the spoke.

### Why the DNS zone is not `sandbox.internal`

Databricks **rejects reserved TLDs** (`.internal`, `.local`) in an NCC private
endpoint rule's `domain_name`, with `Cannot use these domain names: ...`. Since
the rehearsal exercises NCC, the zone must be a normal-looking name. That is the
only reason it is `sandbox.baytexdemo.net`.

### After the platform pipeline has run

```powershell
.\sandbox\Link-SandboxDnsToSpoke.ps1   # link the three zones to the new spoke
```

Then run the hub-side peering command from the `hub_side_peering_command` output
— in a real deployment both of these are customer-owned handoffs, and doing them
yourself here is what makes the rehearsal end-to-end.

---

## Validating

```powershell
.\sandbox\Invoke-SandboxValidation.ps1
```

Eleven checks: peering state, on-prem DNS, storage privatelink resolution, the
routed path from both proxy VMs, HAProxy health, and the internal load balancer
front ends proxying through to the simulators.

It takes parameters for every environment-specific value — DNS zone, on-prem IP,
private-endpoint prefix and both ILB front-end IPs — so it does not report false
failures when addressing changes:

```powershell
.\sandbox\Invoke-SandboxValidation.ps1 `
  -DnsZone "sandbox.baytexdemo.net" `
  -PrivateEndpointPrefix "10.99.18." `
  -IlbSqlFrontendIp "10.99.18.75" -IlbOraFrontendIp "10.99.18.76"
```

Passing all eleven still does **not** prove Databricks can reach the targets —
the proxy VMs sit in a different subnet behind different NSGs. For that, run the
in-cluster notebook probe in DEPLOYMENT-GUIDE §1.11a.

---

## Reading state and planning locally

Read-only inspection is fine and often the fastest way to understand drift.

```powershell
cd environments\dev
terraform init `
  -backend-config="resource_group_name=<rg>" `
  -backend-config="storage_account_name=<sa>" `
  -backend-config="container_name=tfstate" `
  -backend-config="key=dev/platform.tfstate" `
  -backend-config="use_azuread_auth=true"

terraform state list
terraform plan          # inspect only -- do not apply
```

You need **Storage Blob Data Contributor** on the state account. Owner is not
enough: blob content is a data-plane permission that Owner does not include.

Do not run `terraform apply` locally. The state is shared with the pipeline, and
an out-of-band apply produces changes with no plan artefact, no approval and no
audit record.

---

## Tearing down the sandbox

Order matters.

```powershell
# 1. platform (via Actions, or locally if you accept the caveat above)
# 2. state backend
# 3. mock hub
.\sandbox\Remove-SandboxHub.ps1
```

Destroying the hub while the spoke peering still references it leaves a peering
pointing at a VNet that no longer exists. `Remove-SandboxHub.ps1` checks for a
live spoke peering and refuses unless given `-Force`.

---

## Note on `sandbox/`

`sandbox/` is **not tracked in git** — it is rehearsal scaffolding that should
never reach a client repository. It lives only on the machine that created it, so
it will not survive a fresh clone. Keep a copy if you need to rehearse again.
