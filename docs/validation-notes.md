# Validation and Acceptance

How the platform is checked automatically on every change, and the criteria each environment must meet before it is
accepted. A successful `terraform apply` is not acceptance.

## Automated checks

Every pull request runs **Terraform Pull Request Checks** ([Workflows](workflows.md#34-pull-request-checks)):

- `terraform fmt -check` and `terraform validate` across every environment and bootstrap root
- A parity report for the three environment roots and the three bootstrap roots
- A plan of each affected environment, using the values in its `TFVARS` variable

Input rules in `variables.tf` reject malformed values when a plan is created, before any resource is touched
([Configuration reference](configuration-reference.md#input-validation)).

Every deploy then plans before it applies, the apply uses the reviewed plan, and the evidence bundle records the plan,
apply log, outputs and state list.

## Checks before the first apply

1. The pull request checks pass for the change.
2. The plan uses the approved inputs for the environment.
3. The plan creates only resources for this environment and, where enabled, the VNet peerings and Private DNS zone
   groups.
4. The provider versions installed by the run are reviewed.
5. The infrastructure-as-code security and policy scan passes.
6. The [pre-deployment checklist](pre-deployment-checklist.md) is complete.

## Acceptance criteria

| Area | Criterion |
| --- | --- |
| Workspace | Users sign in with single sign-on; Power BI and GitHub reach the workspace |
| Classic compute | Clusters start with no public IP addresses |
| Egress | Databricks subnets leave through the NAT Gateway public IP; the proxy subnet leaves through the firewall |
| Peering | The peering is `Connected` on both the spoke and the hub VNet |
| DNS | On-premises names and the storage private endpoint names resolve to private addresses |
| Data storage | Blob and dfs access works privately from classic and serverless compute, and is refused from public networks |
| NCC | The workspace is bound and every private endpoint rule is `ESTABLISHED` |
| On-premises connectivity | Serverless and classic compute connect to every approved SQL Server and Oracle destination |
| Spoke-to-spoke | Traffic from the Databricks subnets to another Azure spoke leaves through the firewall |
| Serverless egress | Serverless compute reaches every approved internet destination and is refused everywhere else |
| Resilience | Connections survive stopping HAProxy, and stopping each VM, in turn |
| Configuration changes | A change to `on_prem_endpoints` or `dns_servers` reaches both HAProxy VMs without replacing them |
| Pipelines | A deploy runs through GitHub OIDC with the approval gate and evidence bundle |
| Monitoring | Diagnostic logs and metrics arrive in Log Analytics, and no platform alert is raised |
| Unity Catalog | Baytex BI's storage credential, external locations and catalog work from the workspace |
| Workload | A representative Baytex BI workload runs end to end |

`scripts/Test-BaytexDevConnectivity.ps1` tests DNS resolution and TCP connectivity from the HAProxy VMs to each
destination and records the results as JSON.

Do not apply example values without Baytex approval.
