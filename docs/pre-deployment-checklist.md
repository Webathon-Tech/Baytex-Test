# Pre-Deployment Checklist

Complete this checklist for each environment before its first apply. Items marked for the first environment only need
to be completed once.

## Baytex approvals

- [ ] Environment address space and subnet CIDRs approved by Baytex networking
- [ ] VNet peering ownership decided: Terraform-managed (both peering flags `true` and Network Contributor on the hub
      VNet granted) or Baytex-managed (change scheduled)
- [ ] Cisco firewall source, destination and port matrix approved
- [ ] On-premises return routes to the environment's address space approved
- [ ] Corporate DNS server list confirmed
- [ ] Private DNS registration decided: zone IDs set with Private DNS Zone Contributor granted, or a manual DNS change
- [ ] Existing regional Unity Catalog metastore ID confirmed
- [ ] Baytex BI accepts ownership of the metastore assignment, catalogs, external locations, bindings, groups and grants
- [ ] On-premises destination list approved, including each destination's domain name, port and address
- [ ] Workspace public front-end access approved
- [ ] Default storage firewall decision recorded; when it is enabled, the root Access Connector is created
- [ ] Private Link Service visibility and connection approval model approved

## Azure and Databricks prerequisites

- [ ] Environment subscription available
- [ ] Deployment service principal created with federated credentials for `<env>-plan` and `<env>-apply`
- [ ] Service principal holds Contributor, User Access Administrator and Storage Blob Data Contributor on the
      environment subscription
- [ ] Service principal holds the hub-subscription roles for every integration enabled in `TFVARS`
- [ ] Service principal added to the Databricks account with the Account Admin role
- [ ] GitHub Environments, variables and protection rules configured ([GitHub setup](github-setup.md))
- [ ] State backend bootstrapped
- [ ] Approved HAProxy SSH public key and administration path provided

## Quality gates

- [ ] `Validate Terraform code` passes on the pull request
- [ ] The plan contains only resources for this environment and, where enabled, the VNet peerings and Private DNS zone
      groups
- [ ] No imports of, or references to, existing production resources other than approved shared dependencies
- [ ] Settings fixed at creation reviewed ([Configuration reference](configuration-reference.md#settings-fixed-at-creation))
- [ ] Security and infrastructure-as-code scan passes
- [ ] Plan reviewed by AMTRA architecture, Baytex Infrastructure and Baytex Security

## Post-apply acceptance

- [ ] NCC private endpoint connections approved and every rule `ESTABLISHED`
- [ ] VNet peering `Connected` on both the spoke and hub VNets
- [ ] Classic compute starts without public IP addresses
- [ ] Serverless and classic compute reach every approved on-premises destination
- [ ] HAProxy service and VM failover tested in both directions
- [ ] Private data storage access and Unity Catalog storage validation pass
- [ ] Pipeline deployment and representative workload validation pass
- [ ] Diagnostic logs arrive in Log Analytics
