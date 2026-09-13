# DEV Deployment Runbook

## Gate 0 — approvals

- Confirm architecture and ownership boundary.
- Confirm IPAM values.
- Confirm the exact endpoint matrix.
- Decide whether Terraform manages the VNet peering and the Private DNS registration of the storage private endpoints. For each one Terraform manages, Baytex grants the hub role in [GITHUB-SETUP.md](../GITHUB-SETUP.md) §2.
- Submit firewall, route and DNS changes, and the hub peering change if Terraform does not manage it.
- Confirm deployment identity permissions, including any hub-subscription roles.
- Confirm Databricks account-admin access.

## Gate 1 — state bootstrap

Run **Terraform Bootstrap State Backend** for the environment ([WORKFLOWS.md](../WORKFLOWS.md) §3.1). It creates the state storage account with blob versioning and soft delete, and its summary records the backend values.

## Gate 2 — plan

- Set `TFVARS` on the `dev-plan` and `dev-apply` GitHub Environments from the approved values, following `environments/dev/baytex.terraform.tfvars.example`.
- Open a pull request. The checks format and validate the code and plan every environment.
- Confirm the plan references no existing Baytex resource IDs other than the approved hub VNet, Private DNS zones and shared service inputs.
- Confirm all plan actions are creates for the new DEV foundation.

## Gate 3 — network prerequisites

Before applying the workspace and connectivity tier:

- VNet peering: both peering flags are `true` and the service principal holds Network Contributor on the hub VNet, or the hub-side peering change is approved or scheduled.
- Private DNS: the zone IDs are set and the service principal holds Private DNS Zone Contributor on both zones, or the DNS change for the storage private endpoints is approved or scheduled.
- Firewall objects and rules are approved or scheduled.
- On-premises return routes are approved or scheduled.

## Gate 4 — apply

Run **Terraform Deploy Platform** from `main` and approve the apply after reading its plan ([WORKFLOWS.md](../WORKFLOWS.md) §3.2). The evidence bundle keeps the plan, apply log and outputs.

## Gate 5 — Private Link approvals

Databricks creates a private endpoint for every NCC rule from its own subscriptions, so each connection arrives as Pending and serverless compute cannot use it until it is approved. After every deploy, approve one connection on each Private Link Service and two on the data storage account (blob and dfs). Approve only connections whose private endpoint name matches an `endpoint_name` in the `ncc_private_endpoint_rules` output; reject anything else.

## Gate 6 — Baytex BI handoff

Baytex BI attaches the workspace to the existing metastore and applies DEV-specific Unity Catalog configuration.

## Gate 7 — technical validation

- Workspace login and SSO
- Classic compute launch and no-public-IP validation
- Egress: Databricks subnets through the NAT Gateway, proxy subnet through the firewall
- VNet peering connected in both directions
- DNS resolution
- Storage Blob/DFS private access
- NCC binding and all private endpoint rules established
- Serverless SQL/Oracle connectivity
- Classic compute SQL/Oracle connectivity
- HAProxy failover in both directions
- GitHub OIDC pipeline
- Logs present in the agreed monitoring destination

## Gate 8 — representative workload

Baytex BI deploys a representative notebook/table/metric asset and validates its required connectivity.

## Rollback

DEV is greenfield. If a deployment must be reversed before business adoption:

1. Stop new workloads.
2. Preserve Terraform state and logs.
3. Remove Baytex-created hub/firewall/DNS changes using their change process.
4. Destroy only the new DEV resources after confirming no Baytex data has been loaded. Peerings and DNS zone groups created by Terraform are removed with them.
5. Existing environments remain unaffected.

Never run `terraform destroy` after Baytex BI begins using the new storage without explicit data-owner approval and backup confirmation.
