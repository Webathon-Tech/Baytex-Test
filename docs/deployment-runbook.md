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

- **VNet peering:** the Baytex change that creates the peering in both directions is approved and scheduled, or both
  peering flags are `true` and the service principal holds Network Contributor on the hub VNet.
- **Private DNS:** the Baytex change that creates the zones and the record sets for the storage private endpoints is
  approved and scheduled against the static addresses in `TFVARS`, or the zone IDs are set and the service principal
  holds Private DNS Zone Contributor on both zones. With the default storage firewall enabled, the change also covers
  the root storage account's endpoints, at the addresses in the `workspace_root_private_endpoint_ips` output.
- **Firewall:** the firewall objects and rules are approved and scheduled, covering the on-premises destinations,
  spoke-to-spoke traffic for the aggregate prefix in `firewall_routes`, and proxy subnet access to the Ubuntu package
  mirrors.
- **Routing:** the on-premises return routes to the environment's address space are approved and scheduled.
- **Outbound destinations:** the approved list is in `serverless_allowed_internet_destinations`, and the enforcement
  mode is the agreed one.

## Gate 4 — apply

Approve the apply of **Terraform Deploy Platform** after reading its plan
([Workflows](workflows.md#32-deploy-the-platform)). The evidence bundle keeps the plan, apply log and outputs for 30
days.

## Gate 5 — Private Link approvals

Databricks creates a private endpoint for every NCC rule from its own subscriptions, so each connection arrives as
Pending and serverless compute cannot use it until it is approved. Each environment has:

- one connection on each Private Link Service
- two connections on the data storage account, one for blob and one for dfs

The apply job of **Terraform Deploy Platform** approves them after every deploy, in its
**Approve the NCC private endpoint connections** step
([Workflows](workflows.md#32-deploy-the-platform)). The step runs
`scripts/Approve-BaytexDatabricksPrivateEndpoints.ps1` against the outputs of the apply it follows:

- It approves only pending connections whose private endpoint name matches an `endpoint_name` in the
  `ncc_private_endpoint_rules` output, so a connection for a new rule is approved on the deploy that creates the rule.
- It leaves connections that are already approved unchanged, so re-running a deploy is safe.
- It reports, without changing, any connection whose endpoint name is not in the output, such as the platform's own
  storage private endpoints.
- It waits up to 20 minutes for endpoints Databricks is still creating.

When a deploy removes an on-premises destination, the same job first removes the connections from that destination's
Private Link Service, so Azure can delete it in the same apply.

Confirm in the step's log, kept in the evidence bundle as `approve-private-endpoints.log`, that every expected
connection is approved, and that every private endpoint rule of the environment's Network Connectivity Configuration
shows `ESTABLISHED` in the Databricks account console.

The same script approves the connections after a deploy run from a workstation. It needs PowerShell 7.2 or later and
an Azure CLI session with Contributor on the environment subscription:

```powershell
terraform -chdir=environments/dev output -json > dev-outputs.json
./scripts/Approve-BaytexDatabricksPrivateEndpoints.ps1 -TerraformOutputPath dev-outputs.json -WaitMinutes 20
```

Add `-WhatIf` to see what it would approve without changing anything. The exit code says what happened:

| Exit code | Meaning |
| --- | --- |
| `0` | Every expected connection is approved |
| `2` | Expected connections are still pending, which happens only with `-WhatIf` |
| `3` | Expected private endpoints did not appear within the wait, or a rule in the output has no private endpoint name |
| `4` | An expected connection is rejected or disconnected; recreate the matching NCC rule to raise a fresh connection |

## Gate 6 — handoffs

- Baytex Infrastructure completes the changes in [Firewall and DNS handoff](firewall-and-dns-handoff.md), using the
  `firewall_handoff`, `data_private_endpoint_ips`, `workspace_root_private_endpoint_ips` and
  `private_link_service_ids` outputs. This covers the Private DNS
  zones and record sets, the peering in both directions, the firewall rules and the connectivity tests.
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
- Traffic from the Databricks subnets to another Azure spoke leaving through the firewall
- Serverless compute reaching each approved internet destination, and being refused elsewhere
- HAProxy failover in both directions
- HAProxy running on every VM, with no platform alert raised
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
2. Detach the serverless network policy: apply the environment once with `attach_serverless_network_policy = false`.
   Azure Databricks refuses to delete a policy a running workspace still refers to.
3. Preserve the Terraform state and the evidence artefacts.
4. Remove the Baytex-managed hub, firewall and DNS changes through the Baytex change process.
5. Confirm that no Baytex data has been loaded, then run **Terraform Destroy Platform** for the environment. Peerings and
   DNS zone groups created by Terraform are removed with it.

Other environments and existing resources remain unaffected.

After Baytex BI begins using an environment's storage, never destroy it without explicit data-owner approval and a
confirmed backup. For changes after adoption, roll forward as described in [Workflows](workflows.md#a-rollback).
