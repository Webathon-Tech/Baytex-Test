# Baytex Azure Databricks Greenfield Platform — Development
<!-- concurrency probe b -->

This repository is a **DEV-first Terraform implementation** for the Baytex Terraform Foundations engagement. It is structured so the same modules can later be reused when Baytex creates the dedicated Test subscription and when the new Production platform is approved.

> **Start here, depending on what you need:**
>
> | Document | Purpose |
> | --- | --- |
> | **[DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)** | Step-by-step runbook: from-scratch deployment, two-phase NCC apply, handoffs, validation, DEV/TEST/PROD |
> | **[ARCHITECTURE.md](ARCHITECTURE.md)** | Why each component exists, detailed traffic flows, design rationale and rejected alternatives |
> | **[TERRAFORM-EXPLAINED.md](TERRAFORM-EXPLAINED.md)** | How the code works: modules, state, dependency graph, outputs, CI/CD |
> | **[PIPELINE-SETUP.md](PIPELINE-SETUP.md)** | What must be done and by whom: Global Admin, Databricks account admin, repo admin, running the pipelines |
> | **[PIPELINES-EXPLAINED.md](PIPELINES-EXPLAINED.md)** | How each workflow works and why it is built that way |
> | **[LOCAL-DEVELOPMENT.md](LOCAL-DEVELOPMENT.md)** | What to run from a laptop (the mock on-prem build) and what never to |
> | **[REHEARSAL-RESULTS.md](REHEARSAL-RESULTS.md)** | Evidence from the full three-environment sandbox rehearsal, and the nine defects it found |
>
> The summary below is orientation only.
>
> ⚠️ **CIDRs must be confirmed by Baytex IPAM before any apply.** The values in
> `terraform.tfvars.example` are a proposal drawn from the Data Non-Prod block
> (`10.40.64.0/20`); see [ARCHITECTURE.md §1.3](ARCHITECTURE.md) for how that
> block was chosen and which ranges are already in use.

## Latest confirmed direction

- Deploy a **brand-new DEV platform** in the existing Data Non-Production subscription.
- Baytex will create a dedicated Test subscription later; Test is not deployed by this package.
- The existing Production subscription remains the Production subscription.
- Every new resource uses the new naming convention.
- Existing Azure and Databricks resources are not imported, renamed, modified, or destroyed.
- Existing Production is a reference/accelerator only.
- The existing hub VNet, Cisco firewall, VPN, corporate DNS, and on-premises connectivity remain shared Baytex dependencies.
- AMTRA owns the Azure/Databricks platform foundation.
- Baytex BI owns Unity Catalog, catalogs, storage credentials, external locations, workspace bindings, groups, grants, workloads, data, and migration.

## State and ownership boundaries

The AMTRA root creates the platform but does **not** create or manage Unity Catalog objects. The `baytex-bi-owned-unity-catalog-example` folder is a separate, optional reference that demonstrates the handoff in a separate state.

The existing hub/firewall/VPN are not imported into this Terraform state. This package creates only additive spoke resources and can optionally create the local/spoke side of VNet peering. Baytex must complete the hub-side peering, firewall rules, DNS changes, and on-premises return routes.

## What the DEV platform creates

- New DEV resource groups
- DEV VNet and dedicated Databricks host/container subnets
- Private Endpoint and HAProxy/Private Link Service subnets
- NSGs, route table, NAT Gateway, and optional spoke-to-hub peering
- Premium Hybrid Azure Databricks workspace with VNet injection and no public IPs for classic compute
- Unity Catalog creation-time enablement required for serverless capabilities
- Firewall-protected Databricks-managed default storage using the environment Access Connector
- New ADLS Gen2 data storage, containers, Access Connector, Azure RBAC, Blob/DFS Private Endpoints
- Two-zone HAProxy tier, internal Standard Load Balancer, one frontend and Private Link Service per approved on-premises destination
- Databricks Network Connectivity Configuration (NCC), workspace binding, storage Private Endpoint rules, and customer-managed PLS rules
- Log Analytics workspace and platform diagnostic settings
- Terraform outputs for the Baytex BI Unity Catalog and workload handoff

## Deliberate design choices

1. **No current-state clone.** Current Production informs the design, but legacy proxy VMs, existing names, permissive rules, and unrelated resources are not copied.
2. **Internet egress uses NAT Gateway.** Only approved on-premises prefixes are routed to the existing Cisco firewall. A `0.0.0.0/0` firewall route should be introduced only through an approved egress design.
3. **Workspace front-end is public initially.** This preserves compatibility for user, Power BI, and GitHub access while private front-end requirements are validated. Classic compute still has no public IPs, and data/storage connectivity is private.
4. **Default workspace storage is firewalled.** The Azure Verified Module uses the environment Access Connector to disallow public access to the Databricks-managed default storage account.
5. **Private Link Service visibility is fail-closed.** Terraform refuses to create the PLS objects until explicit visibility subscriptions are provided or the all-subscription exception is deliberately enabled.
6. **HAProxy configuration is code.** Both Linux VMs use SSH-only authentication, Trusted Launch, platform patching, and cloud-init-managed HAProxy configuration.
7. **One NCC per environment.** All DEV storage and on-premises rules are placed in a single DEV NCC because one workspace can bind to only one NCC.
8. **Unity Catalog remains Baytex BI-owned.** The platform output supplies the existing metastore ID, workspace ID/URL, Access Connector, and storage paths; Baytex BI completes the data-governance layer.

## Repository layout

```text
.
├── bootstrap/state/                    # One-time Azure Blob backend creation
├── environments/dev/                       # DEV platform root module
├── modules/
│   ├── spoke-network/
│   ├── data-foundation/
│   ├── haproxy-tier/
│   └── ncc/
├── baytex-bi-owned-unity-catalog-example/   # Separate Baytex BI reference/state
├── scripts/                                 # Operational PowerShell
├── docs/
└── .github/workflows/
    ├── terraform-bootstrap-state.yml        # Creates + migrates the state backend
    ├── terraform-deploy.yml                 # Manual deploy; dev -> test -> prod
    ├── terraform-destroy.yml                # Manual destroy, one environment
    ├── terraform-plan-pr.yml                # Plan-only check on pull requests
    ├── _terraform-plan.yml                  # Reusable plan
    └── _terraform-apply.yml                 # Reusable apply of the exact plan
```

`sandbox/` is not tracked: it is rehearsal scaffolding that never ships to a
client. See [LOCAL-DEVELOPMENT.md](LOCAL-DEVELOPMENT.md).

## Inputs that must be approved before plan/apply

See `docs/required-inputs.md` and `docs/pre-deployment-checklist.md`. The example CIDRs are proposed placeholders, not Baytex IPAM approvals.

At minimum:

- DEV VNet/subnet CIDRs
- Hub VNet resource ID and peering ownership
- Cisco firewall private IP
- On-premises route CIDRs and exact source/destination/port matrix
- Corporate DNS server IPs and Private DNS zone IDs
- Databricks account ID and existing regional metastore ID
- GitHub OIDC deployment identity and permissions
- Databricks account-level permissions for NCC creation/binding
- Approved SSH source ranges and public key
- PLS visibility model and approval process
- Exact SQL/Oracle destinations in scope

## Deployment sequence

### 1. Create the remote state backend

```powershell
cd bootstrap/state
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Create `environments/dev/backend.hcl` from `backend.hcl.example` using the outputs. Populate `state_blob_data_contributor_principal_ids` so the GitHub OIDC deployment principal can access the state through Microsoft Entra ID.

### 2. Pre-register providers and configure authentication

The Azure provider is configured not to register providers. Baytex must pre-register the required resource providers. The deployment identity needs Azure permissions to create the DEV foundation and create the Access Connector storage role assignment.

```powershell
az login --tenant 9a6302b1-6a51-4f41-ad6b-ad23218c074d
az account set --subscription e3a6598e-28b1-4d6a-8698-6683cd1d6995
```

The same workload identity must also be present in the Databricks account with permission to create/bind NCC objects.

Configure two GitHub Environments for DEV:

- `dev-plan`: contains the DEV variables/secrets required to create plans and has no deployment approval gate.
- `dev`: contains the same backend/Azure variables and is protected by the required Baytex deployment approvers.

The apply workflow creates an exact plan in `dev-plan`, then pauses at the protected `dev` environment before applying that same plan.

### 3. Configure variables

```powershell
cd environments/dev
Copy-Item terraform.tfvars.example terraform.tfvars
Copy-Item backend.hcl.example backend.hcl
```

Replace every placeholder. Resolve the PLS visibility gate before planning.

### 4. Initialize and review

```powershell
terraform init -backend-config=backend.hcl
terraform fmt -recursive -check
terraform validate
terraform plan -out dev.tfplan
terraform show -no-color dev.tfplan > dev-plan.txt
```

Do not apply until the target resource list, network handoff, firewall ticket, DNS handoff, and Unity Catalog ownership are approved.

### 5. Apply DEV foundation

```powershell
terraform apply dev.tfplan
```

> **If the target tenant has no existing Azure Databricks account**, this single
> apply cannot succeed: `modules/ncc` calls the Databricks *account* API, whose
> account ID only exists once the tenant's first workspace does. Use the
> two-phase apply in [DEPLOYMENT-GUIDE.md §1.6/§1.9](DEPLOYMENT-GUIDE.md).
> Baytex already has an account, so confirm the account ID before planning and
> this step stays single-phase.

NCC-created Private Endpoint requests can remain `PENDING` until Baytex approves them against the storage accounts and Private Link Services.

### 6. Approve NCC-created connections

Use `scripts/Approve-BaytexDatabricksPrivateEndpoints.ps1`, then verify the NCC rule status is `ESTABLISHED`.

### 7. Baytex BI Unity Catalog handoff

Read the `unity_catalog_handoff` output. Baytex BI then:

- Assigns the workspace to the existing regional metastore, if not already assigned automatically
- Creates DEV-specific storage credentials and external locations
- Creates environment-specific catalogs and schemas
- Applies workspace-catalog bindings
- Applies environment-specific group grants

The optional reference is in `baytex-bi-owned-unity-catalog-example`.

### 8. Validate

- Workspace SSO and UI/API access
- Classic compute with no public IP
- Serverless NCC status `ESTABLISHED`
- Blob/DFS access
- All approved SQL/Oracle destinations
- HAProxy service failure and VM failover
- Hub/firewall/on-premises return paths
- GitHub federation and platform deployment
- Baytex BI Unity Catalog bindings/grants
- Representative Baytex workload

## Validation status

This platform has been **deployed and validated end-to-end in an isolated
sandbox subscription** (see [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) Part 1),
against a mock hub containing a simulated firewall NVA and simulated on-premises
SQL/Oracle hosts. Verified working:

- Spoke↔hub peering, using this repo's own generated `hub_side_peering_command`
- Route table → NVA → on-premises TCP path on 1433 and 1521
- HAProxy tier healthy on both nodes, internal load balancer front ends
  proxying through to the simulated on-premises hosts
- Storage private endpoints resolving via privatelink DNS to private addresses
- Databricks workspace (Premium, Hybrid, VNet-injected, no public IP for
  classic compute) with firewalled default storage
- **Verified from inside a running Databricks cluster**: classic compute reaches
  both simulated on-premises databases on 1433/1521 — both directly via the
  route table/firewall path and through the internal load balancer/HAProxy tier
  — resolves storage over privatelink to a private address, and egresses via the
  NAT gateway with no public IP on the node

That rehearsal found and fixed **four deployment-blocking defects** that `fmt`,
`validate` and `plan` all passed — see
[DEPLOYMENT-GUIDE.md Appendix A](DEPLOYMENT-GUIDE.md#appendix-a--fixes-applied-to-this-repository).

Still unvalidated: the Databricks NCC module, which requires a Databricks
account ID that only exists once the target tenant has a workspace.

## Limitations and required customer actions

- The code has not been applied to the Baytex tenant.
- Example names/CIDRs/IPs must be approved before use.
- Hub-side peering, firewall policy, VPN/on-premises routes, and corporate DNS changes are Baytex-owned handoffs.
- Azure Monitor Agent, EDR, and Arctic Wolf onboarding for HAProxy VMs require Baytex endpoint-management procedures.
- The optional Unity Catalog folder is not AMTRA-owned and is not called by the platform root.
- A successful `terraform apply` is not acceptance; end-to-end connectivity, failover, data access, and representative workload validation are required.
