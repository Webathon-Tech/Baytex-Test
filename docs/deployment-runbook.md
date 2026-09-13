# Deployment Runbook

The gated procedure for deploying a platform environment. Follow it for each environment in turn — dev, then test, then
prod — completing every gate before moving to the next.

## Gate 0 — approvals

- Confirm the architecture and ownership boundaries in [Architecture and boundaries](architecture-and-boundaries.md).
- Confirm the environment's IP address plan with Baytex networking.
- Confirm the exact matrix of on-premises destinations, ports and domain names.
- Decide whether Terraform manages the VNet peering and the Private DNS registration of the storage private endpoints.
  For each one Terraform manages, Baytex grants the hub role in
  [GitHub setup](github-setup.md#optional-roles-in-the-hub-subscription).
- Submit the firewall, return-route and DNS changes, and the hub peering change if Terraform does not manage it
  ([Firewall and DNS handoff](firewall-and-dns-handoff.md)).
- Confirm the deployment identity's Azure roles, including any hub-subscription roles, and its Databricks account admin
  access.
- Complete the [pre-deployment checklist](pre-deployment-checklist.md).

## Gate 1 — state backend

1. Set `BOOTSTRAP_TFVARS` on `<env>-plan` and `<env>-apply` from `bootstrap/<env>/baytex.terraform.tfvars.example`, and
   the `TF_STATE_*` variables to the same names ([GitHub setup](github-setup.md#4-variables-per-environment)).
2. Run **Terraform Bootstrap State Backend** for the environment and approve the apply
   ([Workflows](workflows.md#31-bootstrap-the-state-backend)).
3. Confirm the summary shows the expected storage account, container and state key.

The state storage account has blob versioning and 30-day soft delete, so state can be recovered if it is corrupted or
deleted.

## Gate 2 — plan

1. Set `TFVARS` on `<env>-plan` and `<env>-apply` from the approved values, following
   `environments/<env>/baytex.terraform.tfvars.example`.
2. Open a pull request for any code change, or run **Terraform Deploy Platform** for the environment and stop at the
   approval gate.
3. In the plan, confirm that:
   - every action creates a new resource for this environment, or updates one as intended
   - no existing Baytex resource is referenced other than the approved hub VNet, Private DNS zones and shared inputs
   - the **Replacements** count is `none`, unless a replacement is expected and understood

## Gate 3 — network prerequisites

Before approving the first apply:

- **VNet peering:** both peering flags are `true` and the service principal holds Network Contributor on the hub VNet,
  or the hub-side peering change is approved and scheduled.
- **Private DNS:** the zone IDs are set and the service principal holds Private DNS Zone Contributor on both zones, or
  the DNS change for the storage private endpoints is approved and scheduled.
- **Firewall:** the firewall objects and rules, including proxy subnet access to the Ubuntu package mirrors, are
  approved and scheduled.
- **Routing:** the on-premises return routes to the environment's address space are approved and scheduled.

## Gate 4 — apply

Approve the apply of **Terraform Deploy Platform** after reading its plan
([Workflows](workflows.md#32-deploy-the-platform)). The evidence bundle keeps the plan, apply log and outputs for 30
days.

## Gate 5 — Private Link approvals

Databricks creates a private endpoint for every NCC rule from its own subscriptions, so each connection arrives as
Pending and serverless compute cannot use it until it is approved. After every deploy that creates NCC rules, approve:

- one connection on each Private Link Service
- two connections on the data storage account, one for blob and one for dfs

Approve only connections whose private endpoint name matches an `endpoint_name` in the `ncc_private_endpoint_rules`
output, and reject anything else. `scripts/Approve-BaytexDatabricksPrivateEndpoints.ps1` approves pending connections
whose names match the list it is given and skips all others. Afterwards, confirm every rule in
`ncc_private_endpoint_rules` reports `ESTABLISHED`.

## Gate 6 — handoffs

- Baytex Infrastructure completes the changes in [Firewall and DNS handoff](firewall-and-dns-handoff.md), using the
  `firewall_handoff` output.
- Baytex BI attaches the workspace to the existing metastore and configures Unity Catalog, using the
  `unity_catalog_handoff` output and [Unity Catalog handoff](unity-catalog-handoff.md).

## Gate 7 — technical validation

Work through the acceptance criteria in [Validation and acceptance](validation-notes.md#acceptance-criteria):

- Workspace sign-in and single sign-on
- Classic compute starts without public IP addresses
- Egress: Databricks subnets through the NAT Gateway, proxy subnet through the firewall
- VNet peering connected in both directions
- DNS resolution of on-premises names and storage private endpoints
- Private access to the data storage account
- NCC binding and every private endpoint rule established
- Serverless and classic compute connectivity to each approved SQL Server and Oracle destination
- HAProxy failover in both directions
- Pipeline runs through GitHub OIDC
- Diagnostic logs arriving in Log Analytics

## Gate 8 — representative workload

Baytex BI deploys a representative notebook, table or report asset and validates its connectivity and data access.

## Promotion to the next environment

Once dev passes Gates 7 and 8, repeat the runbook for test, and then for prod. Every code change reaches the three
environments in that order through **Terraform Deploy Platform**.

## Rollback

Before business adoption, an environment can be removed and rebuilt:

1. Stop new workloads.
2. Preserve the Terraform state and the evidence artefacts.
3. Remove the Baytex-managed hub, firewall and DNS changes through the Baytex change process.
4. Confirm that no Baytex data has been loaded, then run **Terraform Destroy Platform** for the environment. Peerings and
   DNS zone groups created by Terraform are removed with it.
5. Other environments and existing resources remain unaffected.

After Baytex BI begins using an environment's storage, never destroy it without explicit data-owner approval and a
confirmed backup. For changes after adoption, roll forward as described in [Workflows](workflows.md#a-rollback).
