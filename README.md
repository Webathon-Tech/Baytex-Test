# Baytex Azure Databricks Platform

Terraform for a greenfield Azure Databricks platform, deployable to **dev, test
and prod** from one set of modules, driven entirely by GitHub Actions.

| I want to… | Go to |
| --- | --- |
| **Run a pipeline** — deploy, bootstrap, destroy | **[WORKFLOWS.md](WORKFLOWS.md)** |
| **Configure the repository** — identities, environments, variables, protection | **[GITHUB-SETUP.md](GITHUB-SETUP.md)** |
| Understand boundaries, handoffs and required inputs | [`docs/`](docs/) |

> **All Terraform runs through GitHub Actions.** Nothing is applied from a
> laptop. The pipelines hold the credentials, the state locking and the approval
> gates, and they produce the evidence trail.

---

## What it builds

Per environment:

- Resource groups, VNet, and dedicated Databricks host and container subnets
- Private Endpoint and HAProxy / Private Link Service subnets
- NSGs, route table, NAT Gateway, and optionally the spoke side of VNet peering
- **Premium Databricks workspace** with VNet injection and no public IPs for
  classic compute
- Unity Catalog creation-time enablement, required for serverless
- Firewall-protected Databricks-managed default storage via the environment
  Access Connector
- ADLS Gen2 data storage, containers, Access Connector, Azure RBAC, and Blob/DFS
  private endpoints
- Two-zone HAProxy tier, internal Standard Load Balancer, and one frontend plus
  Private Link Service per approved on-premises destination
- Databricks **Network Connectivity Configuration** (NCC), workspace binding,
  storage private endpoint rules, and customer-managed PLS rules
- Log Analytics workspace and platform diagnostic settings
- Outputs for the Baytex BI Unity Catalog handoff

## Ownership boundaries

This Terraform creates the **platform**. It does not create or manage Unity
Catalog objects — catalogs, storage credentials, external locations, grants — and
it does not import the existing hub, firewall or VPN.

`baytex-bi-owned-unity-catalog-example/` is a separate, optional reference in its
own state showing the handoff.

Baytex retains the hub-side VNet peering, firewall rules, DNS changes and
on-premises return routes. See [`docs/firewall-and-dns-handoff.md`](docs/firewall-and-dns-handoff.md).

## Design choices worth knowing

1. **No clone of current production.** The existing estate informs the design;
   legacy proxy VMs, old names and permissive rules are not copied.
2. **Internet egress uses a NAT Gateway.** Only approved on-premises prefixes
   route to the Cisco firewall. A `0.0.0.0/0` firewall route belongs to an
   approved egress design, not to this default.
3. **The workspace front-end is public initially**, preserving user, Power BI and
   GitHub access while private front-end requirements are validated. Classic
   compute still has no public IPs and data connectivity stays private.
4. **Private Link Service visibility is fail-closed.** Terraform refuses to
   create PLS objects until visibility subscriptions are supplied explicitly, or
   the all-subscription exception is deliberately enabled.
5. **HAProxy configuration is code.** SSH-only authentication, Trusted Launch,
   platform patching, cloud-init-managed configuration.
6. **One NCC per environment**, because a workspace can bind to only one.

## Repository layout

```text
.
├── bootstrap/state/                       # Creates the Azure Blob state backend
├── environments/{dev,test,prod}/          # One root per environment
├── modules/
│   ├── spoke-network/
│   ├── data-foundation/
│   ├── haproxy-tier/
│   └── ncc/
├── baytex-bi-owned-unity-catalog-example/ # Baytex BI reference, separate state
├── scripts/                               # Operational PowerShell
├── docs/                                  # Boundaries, handoffs, required inputs
└── .github/workflows/
    ├── terraform-pull-request.yml         # Automatic checks on every PR
    ├── terraform-bootstrap.yml            # Create the state backend
    ├── terraform-deploy.yml               # Deploy: dev → test → prod
    ├── terraform-destroy.yml              # Tear an environment down
    ├── _terraform-validate.yml            # Reusable: fmt and validate
    ├── _terraform-plan.yml                # Reusable: plan (deploy or destroy)
    ├── _terraform-apply.yml               # Reusable: apply the approved plan
    ├── _bootstrap-plan.yml                # Reusable: plan the state backend
    └── _bootstrap-apply.yml               # Reusable: apply and migrate state
```

The three environment roots hold **identical `.tf` files**; only the variables
differ, and those live in GitHub rather than in git. The pull-request checks
report any drift between them.

## Getting started

1. Complete **[GITHUB-SETUP.md](GITHUB-SETUP.md)** — service principals,
   environments, variables, protection rules
2. Run **Terraform Bootstrap State Backend** for the environment
3. Run **Terraform Deploy Platform** for the same environment

Both are described step by step in **[WORKFLOWS.md](WORKFLOWS.md)**.

## Before any apply

⚠️ **CIDRs must be confirmed by Baytex IPAM.** The values in the
`terraform.tfvars.example` files are proposals, not approvals.

The full list of decisions required before a first deployment is in
[`docs/required-inputs.md`](docs/required-inputs.md) and
[`docs/pre-deployment-checklist.md`](docs/pre-deployment-checklist.md). At
minimum: VNet and subnet CIDRs, hub VNet resource ID and peering ownership, the
firewall private IP, the on-premises source/destination/port matrix, corporate
DNS server IPs and Private DNS zone IDs, the Databricks account ID and regional
metastore ID, approved SSH source ranges and public key, the PLS visibility
model, and the exact SQL/Oracle destinations in scope.
