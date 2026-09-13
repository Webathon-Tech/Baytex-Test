# Baytex Azure Databricks Platform

Terraform for the Baytex Azure Databricks greenfield platform, delivered as three
environments — **dev**, **test** and **prod** — built from one set of modules and
one set of root `.tf` files, and deployed through gated GitHub Actions pipelines.

## Current state

| Environment | Subscription | Status |
| --- | --- | --- |
| **dev** | Data Non-Production | Live. Service principal `app-bte-dbx-dev-terraform-001` is federated to this repository. |
| **test** | Dedicated Test subscription | Root and pipelines in place. Inactive until its service principal exists. |
| **prod** | Existing Production subscription | Root and pipelines in place. Inactive until its service principal exists. |

Test and prod are planned by every pull request and report a clean skip while they
are unconfigured, so an unconfigured environment never shows up as a red check.

- Every new resource uses the new naming convention.
- Existing Azure and Databricks resources are not imported, renamed, modified or
  destroyed. Existing Production is a reference and accelerator only.
- The existing hub VNet, Cisco firewall, VPN, corporate DNS and on-premises
  connectivity remain shared Baytex dependencies, integrated additively.
- AMTRA owns the Azure/Databricks platform foundation.
- Baytex BI owns Unity Catalog, catalogs, storage credentials, external locations,
  workspace bindings, groups, grants, workloads, data and migration.

## What the platform provides

Each environment gets its own complete stack:

**Networking**
- Environment resource groups following the naming convention
- VNet with dedicated Databricks host and container subnets
- Private Endpoint and HAProxy/Private Link Service subnets
- NSGs and two route tables: the Databricks subnets send on-premises traffic to the firewall and reach the internet
  through a NAT Gateway; the proxy and private endpoint subnets send all traffic to the firewall
- Optional VNet peering with the existing Baytex hub, in either or both directions

**Databricks**
- Premium Azure Databricks workspace with VNet injection and no public IPs for classic compute
- A root Access Connector for the Databricks-managed default storage, created and attached only when the storage
  firewall is turned on
- Network Connectivity Configuration (NCC), workspace binding, storage private
  endpoint rules and customer-managed Private Link Service rules

**Data foundation**
- ADLS Gen2 data storage account with `managed`, `external`, `landing` and
  `checkpoints` containers
- A data Access Connector with the Azure RBAC Unity Catalog needs on the data storage account
- Blob and DFS Private Endpoints, optionally registered in central Private DNS zones

**On-premises connectivity**
- Two-zone HAProxy tier on Trusted Launch Linux VMs, configuration managed as
  cloud-init code
- Internal Standard Load Balancer
- One frontend and one Private Link Service per approved on-premises destination

**Operations**
- Log Analytics workspace and platform diagnostic settings
- Terraform outputs for the Baytex BI Unity Catalog and workload handoff
- Remote state per environment in an Azure Blob backend, authenticated through
  Microsoft Entra ID rather than account keys

## How it runs

Deployments run through GitHub Actions. [LOCAL-RUNS.md](LOCAL-RUNS.md) describes
planning and applying dev from a workstation against the same state file, for
when a pipeline run is not practical.

Each environment has **two** GitHub Environments. Every Terraform run is split
into a plan job and an apply job, and the apply consumes the exact binary plan the
plan job produced — it never re-plans, so what a reviewer approves is what reaches
Azure.

```
Plan dev deployment   ──▶   Apply dev deployment
   (dev-plan)                  (dev-apply)   ◀── required reviewers attach here
```

Attaching reviewers to `<env>-apply` gates deploy, destroy, bootstrap and unlock
for that environment at once.

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `Terraform Bootstrap State Backend` | Manual | Creates the state storage account for an environment and migrates this root's own state into it. Safe to re-run — it detects whether to create, import or no-op. |
| `Terraform Deploy Platform` | Manual, `main` or `hotfix/*` | Builds or updates the platform. Environments are checkboxes; promotion order is enforced for whatever is ticked, so prod waits on dev. |
| `Terraform Destroy Platform` | Manual, `main` only | Two-phase teardown of the platform roots. Requires retyping the ticked environments. Does not destroy the state backend. |
| `Terraform Unlock State` | Manual, `main` only | Releases a state lock left behind by a cancelled or killed pipeline run. |
| `Terraform Pull Request Checks` | Pull request | Validates, reports root parity, and plans all three environments — plus the state backend when bootstrap files change. Plan only; it holds no path to an apply. |

Every job that touches Azure uploads an evidence bundle recording the commit, the
run, the plan and the approval trail.

Operator detail is in [WORKFLOWS.md](WORKFLOWS.md).

## Configuration model

**Nothing environment-specific lives in git** — no CIDRs, no resource names, no
hostnames, no subscription IDs.

Each of the six GitHub Environments holds the deployment identity, the state
backend coordinates, and two whole-file variables that the workflows write to disk
at run time:

| Variable | Holds |
| --- | --- |
| `TFVARS` | The complete `environments/<env>/terraform.tfvars` |
| `BOOTSTRAP_TFVARS` | The complete `bootstrap/<env>/terraform.tfvars` |

`BOOTSTRAP_TFVARS` must name the same resource group, storage account and
container as the `TF_STATE_*` variables on the same environment. If they disagree,
the bootstrap workflow creates one storage account and stores its state in
another.

Each root folder has two examples of that content. `terraform.tfvars.example` is
what the GitHub variable holds, and `baytex.terraform.tfvars.example` holds the
values for Baytex's subscriptions. Both list their values in the section order of
`variables.tf`, with a comment on what each controls.

`variables.tf` validates the inputs at plan time. It rejects subnets outside the
VNet, proxy addresses outside the proxy subnet or used twice, malformed hub VNet
and Private DNS zone IDs, and a peering flag without a hub VNet ID.

This is what lets one set of `.tf` files serve all three environments. Repository
administration — service principals, environments, variables, protection rules and
branch protection — is documented in [GITHUB-SETUP.md](GITHUB-SETUP.md).

## Repository layout

```text
.
├── bootstrap/{dev,test,prod}/               # Azure Blob state backend, one root per environment
├── environments/
│   ├── dev/                                 # Platform root, one per environment
│   ├── test/
│   └── prod/
├── modules/
│   ├── spoke-network/                       # VNet, subnets, NSGs, NAT Gateway, route tables, hub peering
│   ├── data-foundation/                     # Data storage, data Access Connector, private endpoints
│   ├── databricks-workspace/                # Workspace and root Access Connector
│   ├── haproxy-tier/                        # HAProxy VMs, load balancer, Private Link Services
│   └── ncc/                                 # Network Connectivity Configuration and rules
├── baytex-bi-owned-unity-catalog-example/   # Separate Baytex BI reference/state
├── scripts/
├── docs/
├── .github/workflows/
├── GITHUB-SETUP.md
├── LOCAL-RUNS.md
└── WORKFLOWS.md
```

The three environment roots hold identical `.tf` files; only their `terraform.tfvars`
differs, and that is not in git. Every Terraform file is divided into commented
sections. Every pull request reports where the roots have drifted.

## State and ownership boundaries

The AMTRA root creates the platform but does **not** create or manage Unity Catalog
objects. The `baytex-bi-owned-unity-catalog-example` folder is a separate, optional
reference that demonstrates the handoff in its own Terraform state. It is not
called by the platform roots and is not deployed by these pipelines.

The existing hub, firewall and VPN are not imported into this Terraform state. This
platform creates additive spoke resources. Two integrations with the hub
subscription are optional, each enabled in tfvars once Baytex grants the deployment
service principal one role ([GITHUB-SETUP.md](GITHUB-SETUP.md) §2):

| Integration | tfvars | Role |
| --- | --- | --- |
| VNet peering, in either direction | `hub_vnet_id`, `create_spoke_to_hub_peering`, `create_hub_to_spoke_peering` | Network Contributor on the hub VNet |
| Private DNS registration of the storage private endpoints | `blob_private_dns_zone_ids`, `dfs_private_dns_zone_ids` | Private DNS Zone Contributor on each zone |

With both peering flags `false` and both zone lists empty, Terraform makes no calls
to the hub subscription. Baytex completes the firewall rules, DNS changes,
on-premises return routes, and any peering or DNS registration Terraform does not
manage.

Full ownership matrix: [docs/architecture-and-boundaries.md](docs/architecture-and-boundaries.md).

## Deliberate design choices

1. **No current-state clone.** Current Production informs the design, but legacy
   proxy VMs, existing names, permissive rules and unrelated resources are not
   copied.
2. **Two route tables, matching the existing Baytex spokes.** The Databricks subnets route only the approved
   on-premises prefixes to the Cisco firewall and reach the internet through the NAT Gateway, because forcing their
   traffic through the firewall would mean allow-listing every Databricks control-plane endpoint there. The proxy and
   private endpoint subnets send all traffic to the firewall.
3. **Workspace front-end is public initially.** This preserves compatibility for
   user, Power BI and GitHub access while private front-end requirements are
   validated. Classic compute still has no public IPs, and data/storage
   connectivity is private.
4. **The default storage firewall is off.** The root Access Connector is created and attached only when
   `workspace_default_storage_firewall_enabled` is set to `true`; Databricks then grants it access to the managed
   default storage account itself.
5. **Hub integration is opt-in.** VNet peering and Private DNS registration in the hub subscription are off by
   default, so a deployment identity with roles only in its own subscription deploys cleanly. Turning either on is a
   tfvars change once the hub role is granted. The hub-side peering is addressed by the hub VNet's resource ID, so no
   provider is configured for the hub subscription.
6. **Private Link Service visibility is fail-closed.** Terraform refuses to create
   the PLS objects until explicit visibility subscriptions are provided or the
   all-subscription exception is deliberately enabled.
7. **HAProxy configuration is code.** Both Linux VMs use SSH-only authentication,
   Trusted Launch, platform patching and cloud-init-managed HAProxy configuration.
8. **One NCC per environment.** All of an environment's storage and on-premises
   rules go in a single NCC, because one workspace can bind to only one NCC.
9. **Unity Catalog remains Baytex BI-owned.** The platform output supplies the
   metastore ID, workspace ID/URL, data Access Connector and storage paths; Baytex BI
   completes the data-governance layer.

## Inputs that must be approved before deployment

See [docs/required-inputs.md](docs/required-inputs.md) and
[docs/pre-deployment-checklist.md](docs/pre-deployment-checklist.md). Example CIDRs
in the `.example` files are proposed placeholders, not Baytex IPAM approvals.

At minimum, per environment:

- VNet and subnet CIDRs
- Hub VNet resource ID, and which peering directions Terraform manages
- Cisco firewall private IP
- On-premises route CIDRs and the exact source/destination/port matrix
- Corporate DNS server IPs, and Private DNS zone IDs or a manual DNS handoff
- Databricks account ID and the existing regional metastore ID
- GitHub OIDC deployment identity and its Azure and Databricks permissions, including any hub-subscription roles
- Approved SSH source ranges and public key
- Private Link Service visibility model and approval process
- Exact SQL/Oracle destinations in scope

## Operating sequence for a new environment

1. **Create the deployment identity.** Run the service principal script in
   [GITHUB-SETUP.md](GITHUB-SETUP.md) §2, add it to the Databricks account and
   grant it **Account Admin** — without that, NCC creation fails partway through a
   deploy. If Terraform will manage the hub peering or Private DNS registration,
   have Baytex grant the hub roles in the same section.
2. **Create the GitHub Environments and variables.** `<env>-plan` and `<env>-apply`,
   both with the full variable set (§3–§4). Attach required reviewers to
   `<env>-apply` (§5).
3. **Bootstrap the state backend.** Run `Terraform Bootstrap State Backend` for
   that environment and approve the apply. Re-running later is safe.
4. **Open a pull request** with the intended change and read the plan it publishes
   for that environment.
5. **Deploy.** Run `Terraform Deploy Platform` from `main`, tick the environment,
   and approve the apply after reading the published plan.
6. **Approve the NCC-created private endpoints.** Databricks-created endpoint
   requests stay `PENDING` until approved. Use
   `scripts/Approve-BaytexDatabricksPrivateEndpoints.ps1`, approving only endpoints
   whose names and targets match the deployment outputs, then confirm the NCC rules
   report `ESTABLISHED`.
7. **Hand off to Baytex BI.** Read the `unity_catalog_handoff` output and follow
   [docs/unity-catalog-handoff.md](docs/unity-catalog-handoff.md).
8. **Validate.** Work through [docs/validation-notes.md](docs/validation-notes.md).
   A successful apply is not acceptance.

Gate-by-gate detail: [docs/deployment-runbook.md](docs/deployment-runbook.md).

## Limitations and required Baytex actions

- Firewall policy, VPN and on-premises routes, and corporate DNS changes are
  Baytex-owned handoffs. The hub-side peering and Private DNS registration are
  Baytex-owned too, unless the hub roles are granted and the integration is enabled
  in tfvars. See [docs/firewall-and-dns-handoff.md](docs/firewall-and-dns-handoff.md).
- Terraform registers the Azure resource providers the platform needs in each
  environment subscription. It registers nothing in the hub subscription.
- Azure Monitor Agent, EDR and Arctic Wolf onboarding for the HAProxy VMs run
  through Baytex endpoint-management procedures.
- The Unity Catalog example folder is not AMTRA-owned and is not called by the
  platform roots.
- Test and prod cannot be deployed until their service principals exist.
- A successful `terraform apply` is not acceptance. End-to-end connectivity,
  failover, data access and representative workload validation are required.

## Documentation

| Document | Audience |
| --- | --- |
| [WORKFLOWS.md](WORKFLOWS.md) | Operators running deploys, destroys and bootstraps |
| [GITHUB-SETUP.md](GITHUB-SETUP.md) | Repository administrators |
| [LOCAL-RUNS.md](LOCAL-RUNS.md) | Engineers planning or applying dev from a workstation |
| [docs/architecture-and-boundaries.md](docs/architecture-and-boundaries.md) | Architecture and ownership |
| [docs/deployment-runbook.md](docs/deployment-runbook.md) | Gated deployment procedure |
| [docs/pre-deployment-checklist.md](docs/pre-deployment-checklist.md) | Pre-apply sign-off |
| [docs/required-inputs.md](docs/required-inputs.md) | Values needed before planning |
| [docs/firewall-and-dns-handoff.md](docs/firewall-and-dns-handoff.md) | Baytex Infrastructure handoff |
| [docs/unity-catalog-handoff.md](docs/unity-catalog-handoff.md) | Baytex BI handoff |
| [docs/validation-notes.md](docs/validation-notes.md) | Acceptance validation |
