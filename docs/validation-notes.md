# Validation Notes

## Automated checks

Every pull request runs **Terraform Pull Request Checks** ([WORKFLOWS.md](../WORKFLOWS.md) §3.4):

- `terraform fmt -check` and `terraform validate` across every deployed root
- A parity report for the three environment roots and the three bootstrap roots
- A plan of each affected environment, using the values in its `TFVARS` variable

Input rules in `environments/<env>/variables.tf` reject malformed values at plan time, before any resource is touched. They cover GUID formats, subnet CIDRs inside the VNet, proxy VM, frontend and NAT addresses inside the proxy subnet and never reused, hub VNet and Private DNS zone resource IDs, a hub VNet ID whenever a peering flag is `true`, and a Databricks route table without `0.0.0.0/0`.

## Checks that must run in Baytex before approval

1. `terraform fmt -check -recursive`
2. `terraform init` against the DEV backend
3. `terraform validate`
4. Provider version review
5. `terraform plan` using approved DEV inputs
6. IaC security/policy scan
7. Review that the plan creates only new DEV resources and, where enabled, the VNet peerings and Private DNS zone groups
8. Private Link/NCC, Power BI, classic compute, serverless, HAProxy failover, DNS, firewall, peering and on-premises connectivity validation

Do not apply the example variable values without Baytex approval.
