# DEV Deployment Runbook

## Gate 0 — approvals

- Confirm architecture and ownership boundary.
- Confirm IPAM values.
- Confirm the exact endpoint matrix.
- Submit hub peering, firewall, route, and DNS changes.
- Confirm required Azure providers are registered.
- Confirm deployment identity permissions.
- Confirm Databricks account-admin access.

## Gate 1 — state bootstrap

Deploy `bootstrap/state` using an approved administrative identity. Enable Blob versioning and soft delete. Record the backend values.

## Gate 2 — plan

- Populate `environments/dev/terraform.tfvars`.
- Populate `environments/dev/backend.hcl`.
- Run `terraform init`, `fmt`, `validate`, and `plan`.
- Confirm there are no references to existing Baytex resource IDs other than the approved hub VNet and shared service inputs.
- Confirm all plan actions are creates for the new DEV foundation.

## Gate 3 — network prerequisites

Before applying the workspace and connectivity tier:

- Hub-side peering is approved or scheduled.
- Firewall objects and rules are approved or scheduled.
- DNS/private-zone changes are approved or scheduled.
- On-premises return routes are approved or scheduled.

## Gate 4 — apply

Apply the reviewed saved plan. Save the apply transcript and final outputs.

## Gate 5 — Private Link approvals

Databricks-created endpoints will be pending. Approve only the endpoints whose names and target resources match the DEV deployment outputs.

## Gate 6 — Baytex BI handoff

Baytex BI attaches the workspace to the existing metastore and applies DEV-specific Unity Catalog configuration.

## Gate 7 — technical validation

- Workspace login and SSO
- Classic compute launch and no-public-IP validation
- NAT egress
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
4. Destroy only the new DEV resources after confirming no Baytex data has been loaded.
5. Existing environments remain unaffected.

Never run `terraform destroy` after Baytex BI begins using the new storage without explicit data-owner approval and backup confirmation.
