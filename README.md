# Baytex Azure Databricks Platform

Terraform for the Baytex Azure Databricks greenfield platform, delivered as three
environments — **dev**, **test** and **prod** — built from one set of modules and
one set of root `.tf` files, and deployed through gated GitHub Actions pipelines.

## Current state

| Environment | Subscription | Status |
| --- | --- | --- |
| **dev** | Data Non-Production | Live. Service principal `app-bte-dbx-dev-terraform-001` is federated to this repository. |
| **test** | Dedicated Test subscription, to be created by Baytex | Root and pipelines in place. Inactive until its subscription and service principal exist. |
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
- NSGs, route table, NAT Gateway for internet egress
- Optional spoke-side VNet peering to the existing Baytex hub

**Databricks**
- Premium Hybrid Azure Databricks workspace with VNet injection and no public IPs
  for classic compute
- Unity Catalog creation-time enablement, required for serverless capabilities
- Firewall-protected Databricks-managed default storage using the environment
  Access Connector
- Network Connectivity Configuration (NCC), workspace binding, storage private
  endpoint rules and customer-managed Private Link Service rules

**Data foundation**
- ADLS Gen2 data storage account with `managed`, `external`, `landing` and
  `checkpoints` containers
- Access Connector and the Azure RBAC it requires
- Blob and DFS Private Endpoints

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

Everything that changes Azure runs through GitHub Actions. There is no supported
path that applies from a workstation.

Each environment has **two** GitHub Environments. Every Terraform run is split
into a plan job and an apply job, and the apply consumes the exact binary plan the
plan job produced — it never re-plans, so what a reviewer approves is what reaches
Azure.

```
Plan dev deployment   ──▶   Apply dev deployment
   (dev-plan)                  (dev-apply)   ◀── required reviewers attach here
```

Attaching reviewers to `<env>-apply` gates deploy, destroy and bootstrap for that
environment at once.

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `Terraform Bootstrap State Backend` | Manual | Creates the state storage account for an environment and migrates this root's own state into it. Safe to re-run — it detects whether to create, import or no-op. |
| `Terraform Deploy Platform` | Manual, `main` or `hotfix/*` | Builds or updates the platform. Environments are checkboxes; promotion order is enforced for whatever is ticked, so prod waits on dev. |
| `Terraform Destroy Platform` | Manual, `main` only | Two-phase teardown of the platform roots. Requires retyping the ticked environments. Does not destroy the state backend. |
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
container as the `TF_STATE_*` variables on the same environment. The bootstrap
workflow cross-checks them and refuses to run if they disagree, because otherwise
it would create one storage account and store its state in a different one.

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
│   ├── spoke-network/
│   ├── data-foundation/
│   ├── haproxy-tier/
│   └── ncc/
├── baytex-bi-owned-unity-catalog-example/   # Separate Baytex BI reference/state
├── scripts/
├── docs/
└── .github/workflows/
```

The three environment roots hold identical `.tf` files; only their `terraform.tfvars`
differs, and that is not in git. Every pull request reports where the roots have
drifted.

## State and ownership boundaries

The AMTRA root creates the platform but does **not** create or manage Unity Catalog
objects. The `baytex-bi-owned-unity-catalog-example` folder is a separate, optional
reference that demonstrates the handoff in its own Terraform state. It is not
called by the platform roots and is not deployed by these pipelines.

The existing hub, firewall and VPN are not imported into this Terraform state. This
platform creates only additive spoke resources and can optionally create the
spoke side of the VNet peering. Baytex completes the hub-side peering, firewall
rules, DNS changes and on-premises return routes.

Full ownership matrix: [docs/architecture-and-boundaries.md](docs/architecture-and-boundaries.md).

## Deliberate design choices

1. **No current-state clone.** Current Production informs the design, but legacy
   proxy VMs, existing names, permissive rules and unrelated resources are not
   copied.
2. **Internet egress uses NAT Gateway.** Only approved on-premises prefixes are
   routed to the existing Cisco firewall. A `0.0.0.0/0` firewall route should be
   introduced only through an approved egress design.
3. **Workspace front-end is public initially.** This preserves compatibility for
   user, Power BI and GitHub access while private front-end requirements are
   validated. Classic compute still has no public IPs, and data/storage
   connectivity is private.
4. **Default workspace storage is firewalled.** The Azure Verified Module uses the
   environment Access Connector to disallow public access to the Databricks-managed
   default storage account.
5. **Private Link Service visibility is fail-closed.** Terraform refuses to create
   the PLS objects until explicit visibility subscriptions are provided or the
   all-subscription exception is deliberately enabled.
6. **HAProxy configuration is code.** Both Linux VMs use SSH-only authentication,
   Trusted Launch, platform patching and cloud-init-managed HAProxy configuration.
7. **One NCC per environment.** All of an environment's storage and on-premises
   rules go in a single NCC, because one workspace can bind to only one NCC.
8. **Unity Catalog remains Baytex BI-owned.** The platform output supplies the
   metastore ID, workspace ID/URL, Access Connector and storage paths; Baytex BI
   completes the data-governance layer.

## Inputs that must be approved before deployment

See [docs/required-inputs.md](docs/required-inputs.md) and
[docs/pre-deployment-checklist.md](docs/pre-deployment-checklist.md). Example CIDRs
in the `.example` files are proposed placeholders, not Baytex IPAM approvals.

At minimum, per environment:

- VNet and subnet CIDRs
- Hub VNet resource ID and peering ownership
- Cisco firewall private IP
- On-premises route CIDRs and the exact source/destination/port matrix
- Corporate DNS server IPs and Private DNS zone IDs
- Databricks account ID and the existing regional metastore ID
- GitHub OIDC deployment identity and its Azure and Databricks permissions
- Approved SSH source ranges and public key
- Private Link Service visibility model and approval process
- Exact SQL/Oracle destinations in scope

## Operating sequence for a new environment

1. **Create the deployment identity.** Run the service principal script in
   [GITHUB-SETUP.md](GITHUB-SETUP.md) §2, add it to the Databricks account and
   grant it **Account Admin** — without that, NCC creation fails partway through a
   deploy.
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

- Hub-side peering, firewall policy, VPN and on-premises routes, and corporate DNS
  changes are Baytex-owned handoffs. See
  [docs/firewall-and-dns-handoff.md](docs/firewall-and-dns-handoff.md).
- Required Azure resource providers must be pre-registered; the provider is
  deliberately configured not to register them.
- Azure Monitor Agent, EDR and Arctic Wolf onboarding for the HAProxy VMs run
  through Baytex endpoint-management procedures.
- The Unity Catalog example folder is not AMTRA-owned and is not called by the
  platform roots.
- Test and prod cannot be deployed until their subscriptions and service
  principals exist.
- A successful `terraform apply` is not acceptance. End-to-end connectivity,
  failover, data access and representative workload validation are required.

## Documentation

| Document | Audience |
| --- | --- |
| [WORKFLOWS.md](WORKFLOWS.md) | Operators running deploys, destroys and bootstraps |
| [GITHUB-SETUP.md](GITHUB-SETUP.md) | Repository administrators |
| [docs/architecture-and-boundaries.md](docs/architecture-and-boundaries.md) | Architecture and ownership |
| [docs/deployment-runbook.md](docs/deployment-runbook.md) | Gated deployment procedure |
| [docs/pre-deployment-checklist.md](docs/pre-deployment-checklist.md) | Pre-apply sign-off |
| [docs/required-inputs.md](docs/required-inputs.md) | Values needed before planning |
| [docs/firewall-and-dns-handoff.md](docs/firewall-and-dns-handoff.md) | Baytex Infrastructure handoff |
| [docs/unity-catalog-handoff.md](docs/unity-catalog-handoff.md) | Baytex BI handoff |
| [docs/validation-notes.md](docs/validation-notes.md) | Acceptance validation |
