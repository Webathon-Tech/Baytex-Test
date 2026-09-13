# Baytex Azure Databricks Platform

Infrastructure as code for the Baytex Azure Databricks platform. One set of Terraform modules builds three isolated
environments — **dev**, **test** and **prod** — each in its own spoke network connected to the existing Baytex hub.
GitHub Actions pipelines deploy every change from a reviewed plan, through an approval gate, with an audit record.

## What this project delivers

### In each environment

| Area | Delivered |
| --- | --- |
| **Networking** | A spoke VNet with Databricks host and container subnets, a private endpoint subnet and a proxy subnet; network security groups; a NAT Gateway for Databricks internet egress; two route tables that send on-premises traffic to the Cisco firewall; and optional VNet peering with the hub in either or both directions |
| **Databricks** | A Premium Azure Databricks workspace with VNet injection and secure cluster connectivity, so classic compute has no public IP addresses; a Network Connectivity Configuration (NCC) bound to the workspace; and a root Access Connector when the default storage firewall is enabled |
| **Data foundation** | An ADLS Gen2 storage account with hierarchical namespace, zone-redundant storage, no public network access and no shared keys; `managed`, `external`, `landing` and `checkpoints` containers; a data Access Connector with the roles Unity Catalog needs; and blob and dfs private endpoints, optionally registered in central Private DNS zones |
| **On-premises connectivity for serverless compute** | Two HAProxy VMs in separate availability zones behind an internal Standard Load Balancer, with one frontend and one Private Link Service per approved SQL Server or Oracle destination, reached from serverless compute through NCC private endpoint rules |
| **Operations** | A Log Analytics workspace, diagnostic settings for the workspace, storage, load balancer and NAT Gateway, an optional alert action group, and Terraform outputs for the firewall and Unity Catalog handoffs |
| **Terraform state** | A dedicated state storage account with versioning, soft delete and Microsoft Entra ID-only access |

### Across all environments

- **Pipelines** — pull request checks, state backend bootstrap, deployment with enforced dev → test → prod promotion,
  teardown and state lock recovery, all authenticated with GitHub OIDC and gated at the apply step.
- **Evidence** — every run that touches Azure uploads its plan, logs and run metadata as an artefact.
- **Operational scripts** — private endpoint approval, connectivity testing and handoff export, in `scripts/`.
- **Unity Catalog reference** — a separate, optional Terraform configuration that shows Baytex BI how to attach a
  workspace to the existing metastore.
- **Documentation** — architecture, configuration reference, setup, operations, runbook, handoffs and acceptance
  criteria, in `docs/`.

## Architecture at a glance

```text
  Existing Baytex hub subscription
  +--------------------------------------------------------------------------+
  |  Hub VNet    Cisco firewall    VPN to on-premises    Corporate DNS        |
  |  Central Private DNS zones                          On-premises SQL/Oracle|
  +--------------------------------------^-----------------------------------+
                                         |  VNet peering
  Environment spoke subscription         |
  +--------------------------------------+-----------------------------------+
  |  Databricks host and container subnets                                   |
  |     - on-premises prefixes -> firewall                                   |
  |     - everything else      -> NAT Gateway -> internet and Databricks     |
  |  Private endpoint subnet: data storage (blob, dfs)                       |
  |  Proxy subnet: Private Link Services -> load balancer -> 2 x HAProxy     |
  |     - all traffic          -> firewall -> on-premises destinations       |
  +--------------------------------------^-----------------------------------+
                                         |  NCC private endpoints
                          Databricks serverless compute
```

Full design, traffic flows and resource inventory: [docs/architecture-and-boundaries.md](docs/architecture-and-boundaries.md).

## Repository layout

```text
.
├── environments/{dev,test,prod}/            # Platform root per environment; identical .tf files
├── bootstrap/{dev,test,prod}/               # Terraform state backend root per environment
├── modules/
│   ├── spoke-network/                       # VNet, subnets, NSGs, NAT Gateway, route tables, hub peering
│   ├── data-foundation/                     # Data storage, data Access Connector, private endpoints
│   ├── databricks-workspace/                # Workspace and root Access Connector
│   ├── haproxy-tier/                        # HAProxy VMs, load balancer, Private Link Services
│   └── ncc/                                 # Network Connectivity Configuration and private endpoint rules
├── baytex-bi-owned-unity-catalog-example/   # Optional Unity Catalog reference with its own state
├── scripts/                                 # Operational PowerShell scripts
├── docs/                                    # Project documentation
└── .github/workflows/                       # GitHub Actions pipelines
```

The three environment roots hold identical `.tf` files, and each environment's values come from its GitHub
Environment rather than from git. Every Terraform file is divided into commented sections, and every variable and
output carries a description.

## Getting started

| Step | What to do | Guide |
| --- | --- | --- |
| 1 | Understand the design and who owns what | [Architecture and boundaries](docs/architecture-and-boundaries.md) |
| 2 | Collect and approve the inputs for each environment | [Required inputs](docs/required-inputs.md), [Configuration reference](docs/configuration-reference.md) |
| 3 | Create the deployment identities, GitHub Environments, variables and protection rules | [GitHub setup](docs/github-setup.md) |
| 4 | Complete the pre-deployment sign-off | [Pre-deployment checklist](docs/pre-deployment-checklist.md) |
| 5 | Bootstrap state, deploy and approve private endpoints, environment by environment | [Deployment runbook](docs/deployment-runbook.md), [Workflows](docs/workflows.md) |
| 6 | Complete the network and Unity Catalog handoffs | [Firewall and DNS handoff](docs/firewall-and-dns-handoff.md), [Unity Catalog handoff](docs/unity-catalog-handoff.md) |
| 7 | Validate and accept the environment | [Validation and acceptance](docs/validation-notes.md) |

## How configuration works

Nothing environment-specific is committed to git. Each environment has two GitHub Environments, `<env>-plan` and
`<env>-apply`, which hold the deployment identity, the state backend coordinates and two whole-file variables:

| Variable | Holds |
| --- | --- |
| `TFVARS` | The complete `terraform.tfvars` for `environments/<env>` |
| `BOOTSTRAP_TFVARS` | The complete `terraform.tfvars` for `bootstrap/<env>` |

Each root folder carries two example files that list every value in the section order of `variables.tf`, with a
comment on what each controls: `baytex.terraform.tfvars.example` holds the values for Baytex's subscriptions, and
`terraform.tfvars.example` is a complete reference configuration. Input validation rejects malformed values when a plan
is created, before anything in Azure changes. Details: [docs/configuration-reference.md](docs/configuration-reference.md).

## How changes reach Azure

Every Terraform run is split into a plan job in `<env>-plan` and an apply job in `<env>-apply`. The apply consumes the
exact binary plan the plan job produced, so what a reviewer approves is what reaches Azure. Required reviewers
attached to `<env>-apply` gate every deploy, destroy, bootstrap and unlock for that environment.

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `Terraform Pull Request Checks` | Every pull request | Formats and validates the code, reports root parity, and plans the environments or state backends the change affects |
| `Terraform Bootstrap State Backend` | Manual, `main` or `hotfix/*` | Creates an environment's state storage account; safe to re-run |
| `Terraform Deploy Platform` | Manual, `main` or `hotfix/*` | Builds or updates the ticked environments in dev → test → prod order |
| `Terraform Destroy Platform` | Manual, `main` only | Tears down the ticked environments after the names are retyped; keeps the state backend |
| `Terraform Unlock State` | Manual, `main` only | Releases a state lock left by a cancelled or killed run |

Operator guide: [docs/workflows.md](docs/workflows.md). Planning or applying from a workstation:
[docs/local-runs.md](docs/local-runs.md).

## Ownership

| Party | Owns |
| --- | --- |
| **AMTRA** | The platform foundation in this repository: networking, workspace, data foundation, connectivity tier, NCC, operations, Terraform state and pipelines |
| **Baytex Infrastructure** | The hub VNet, Cisco firewall policy, VPN, on-premises routes, corporate DNS and Private DNS zones, and the hub-subscription roles that let Terraform manage peering or DNS registration |
| **Baytex BI** | Unity Catalog: metastore assignment, catalogs, schemas, storage credentials, external locations, workspace bindings, groups, grants, workloads and data |

Existing Azure and Databricks resources are not imported, renamed, modified or destroyed. Two integrations with the hub
subscription are optional — VNet peering and Private DNS registration — and each is enabled in `TFVARS` once Baytex
grants the deployment service principal one role. Without them, Terraform makes no calls to the hub subscription.

## Design principles

1. **Built new, not cloned.** The existing production estate informs the design, but legacy proxy VMs, names,
   permissive rules and unrelated resources are not copied.
2. **Two route tables.** The Databricks subnets send only approved on-premises prefixes to the firewall and reach the
   internet through the NAT Gateway, so the firewall does not have to allow every Databricks endpoint. The proxy and
   private endpoint subnets send all traffic to the firewall.
3. **Private data paths.** The data storage account has no public network access; classic compute uses the spoke
   private endpoints and serverless compute uses NCC private endpoints.
4. **Public workspace front end, private compute.** Users, Power BI and GitHub reach the workspace front end, while
   classic compute has no public IP addresses.
5. **Hub integration is opt-in.** Peering and Private DNS registration in the hub subscription are off by default, so an
   identity with roles only in its own subscription deploys cleanly.
6. **Fail-closed Private Link Service visibility.** Terraform refuses to create the Private Link Services until
   explicit visibility subscriptions are provided or all-subscription visibility is deliberately enabled.
7. **Configuration as code for HAProxy.** Both VMs use SSH-key authentication, Trusted Launch, platform patching and a
   cloud-init configuration rendered by Terraform.
8. **One NCC per environment.** A workspace can bind to only one NCC, so every storage and on-premises rule for an
   environment lives in one.
9. **Unity Catalog stays with Baytex BI.** The platform outputs everything Baytex BI needs, and creates no Unity
   Catalog objects itself.

## Documentation

All documentation lives in [`docs/`](docs/README.md), grouped by the stage in which it is used.

| Stage | Document | Purpose |
| --- | --- | --- |
| Understand | [Architecture and boundaries](docs/architecture-and-boundaries.md) | Design, network layout, traffic flows, resource inventory and ownership |
| Understand | [Configuration reference](docs/configuration-reference.md) | Configuration model, naming, tags, every input and output |
| Prepare | [Required inputs](docs/required-inputs.md) | Decisions and values to collect before planning |
| Prepare | [GitHub setup](docs/github-setup.md) | Identities, GitHub Environments, variables, protection rules |
| Prepare | [Pre-deployment checklist](docs/pre-deployment-checklist.md) | Sign-off before an environment's first apply |
| Deploy and operate | [Deployment runbook](docs/deployment-runbook.md) | Gated procedure for deploying and promoting an environment |
| Deploy and operate | [Workflows](docs/workflows.md) | Running, approving and troubleshooting the pipelines |
| Deploy and operate | [Local runs](docs/local-runs.md) | Planning and applying from a workstation |
| Hand off and accept | [Firewall and DNS handoff](docs/firewall-and-dns-handoff.md) | Changes Baytex Infrastructure completes |
| Hand off and accept | [Unity Catalog handoff](docs/unity-catalog-handoff.md) | Changes Baytex BI completes |
| Hand off and accept | [Validation and acceptance](docs/validation-notes.md) | Automated checks and acceptance criteria |
