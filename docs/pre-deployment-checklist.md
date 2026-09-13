# DEV Pre-Deployment Checklist

Do not apply the DEV root until every mandatory item is complete.

## Baytex approvals

- [ ] DEV CIDRs approved by IPAM/networking
- [ ] VNet peering ownership decided: Terraform-managed (both peering flags `true`, Network Contributor on the hub VNet granted) or Baytex-managed (change ticket confirmed)
- [ ] Cisco firewall source/destination/port matrix approved
- [ ] On-premises return routes approved
- [ ] Corporate DNS server list and Private DNS zone ownership confirmed
- [ ] Private DNS registration decided: zone IDs set with Private DNS Zone Contributor granted, or a manual DNS change
- [ ] Existing regional Unity Catalog metastore ID confirmed
- [ ] Baytex BI accepts ownership of metastore assignment, catalogs, external locations, bindings, groups and grants
- [ ] SQL/Oracle destination list approved; SQL6, Trimble/TMW and SQL03YYC disposition documented
- [ ] Workspace public-front-end decision approved
- [ ] Workspace default-storage firewall decision recorded (off by default; the root Access Connector exists only when it is on)
- [ ] Private Link Service visibility decision approved

## Azure and Databricks prerequisites

- [ ] Resource providers registered in the DEV subscription, or the deployment identity allowed to register them (Terraform registers the set it needs)
- [ ] GitHub OIDC service principal created and federated to the repository/environment
- [ ] OIDC principal has required Azure roles, including state data-plane access
- [ ] OIDC principal holds the hub-subscription roles for every integration enabled in tfvars
- [ ] OIDC principal exists in the Databricks account with NCC permissions
- [ ] Terraform backend created and tested
- [ ] Approved HAProxy SSH public key and administration path provided

## Quality gates

- [ ] `terraform fmt -check -recursive` passes
- [ ] `terraform init` succeeds using Entra ID authentication
- [ ] `terraform validate` passes
- [ ] Plan contains only new DEV resources and, where enabled, the VNet peerings and Private DNS zone groups
- [ ] No import blocks or references to existing Prod resource IDs except approved shared dependencies
- [ ] Security/IaC scan passes
- [ ] Plan reviewed by AMTRA architecture, Baytex Infrastructure and Security

## Post-apply acceptance

- [ ] NCC rules become `ESTABLISHED` after expected endpoint approval
- [ ] VNet peering shows `Connected` on both the spoke and hub VNets
- [ ] Classic compute launches without public IPs
- [ ] Serverless and classic compute reach approved on-premises targets
- [ ] HAProxy service and VM failover tested in both directions
- [ ] Blob/DFS private access and Unity Catalog storage validation pass
- [ ] GitHub federated deployment and representative workload validation pass
- [ ] Diagnostics arrive in Log Analytics
