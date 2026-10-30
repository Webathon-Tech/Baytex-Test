# Pre-Deployment Checklist

Complete this checklist for each environment before its first apply. Items marked for the first environment only need
to be completed once.

## Baytex approvals

- [ ] Environment address space and subnet CIDRs approved by Baytex networking
- [ ] Static addresses for the blob and dfs private endpoints agreed, and the DNS records planned against them
- [ ] Baytex change scheduled for the VNet peering in both directions
- [ ] Cisco firewall source, destination and port matrix approved
- [ ] Firewall rules for spoke-to-spoke traffic approved, covering the aggregate prefix in `firewall_routes`
- [ ] Approved outbound destination list confirmed, and the serverless enforcement mode agreed
- [ ] On-premises return routes to the environment's address space approved
- [ ] Corporate DNS server list confirmed
- [ ] Baytex change scheduled for the Private DNS record sets of the blob and dfs private endpoints
- [ ] Existing regional Unity Catalog metastore ID confirmed
- [ ] Baytex BI accepts ownership of the metastore assignment, catalogs, bindings, groups and grants, and the platform's
      ownership of the storage credential and external location over the data storage account
- [ ] Unity Catalog container name, and any grants on the external location, confirmed
- [ ] On-premises destination list approved, including each destination's domain name, port and address
- [ ] Workspace public front-end access approved
- [ ] Private Link Service visibility and connection approval model approved

## Azure and Databricks prerequisites

- [ ] Environment subscription available
- [ ] Deployment service principal created with federated credentials for `<env>-plan` and `<env>-apply`
- [ ] Service principal `app-bte-dbx-<env>-terraform-001` holds Contributor, Storage Blob Data Contributor and Role
      Based Access Control Administrator on the environment subscription
- [ ] Hub-subscription roles granted, only if a hub integration is enabled in `terraform.tfvars` (none by default)
- [ ] Service principal added to the Databricks account with the Account Admin role
- [ ] Service principal granted `CREATE STORAGE CREDENTIAL` and `CREATE EXTERNAL LOCATION` on the metastore by a
      metastore admin ([GitHub setup](github-setup.md#unity-catalog-metastore))
- [ ] In an environment where Unity Catalog objects were created by hand, no external location already covers the
      `unity-catalog` container: `SHOW EXTERNAL LOCATIONS` lists none with that URL
- [ ] GitHub Environments, variables and protection rules configured ([GitHub setup](github-setup.md))
- [ ] State backend bootstrapped
- [ ] HAProxy SSH key pair created for this environment, its public key in `terraform.tfvars`, its private key in a
      Baytex vault, and the administration path agreed
- [ ] HAProxy patch windows accepted for the environment: Sunday 14:00–16:00 and 18:00–20:00 Alberta Time

## Quality gates

- [ ] `Validate Terraform code` passes on the pull request
- [ ] The plan contains only resources for this environment and, where enabled, the VNet peerings and Private DNS zone
      groups
- [ ] No imports of, or references to, existing production resources other than approved shared dependencies
- [ ] Settings fixed at creation reviewed ([Configuration reference](configuration-reference.md#settings-fixed-at-creation))
- [ ] Baytex security and infrastructure-as-code scan passes; it runs outside these pipelines
- [ ] Plan reviewed by AMTRA architecture, Baytex Infrastructure and Baytex Security

## Post-apply acceptance

- [ ] The deploy's approval step reports every NCC private endpoint connection approved, and every rule is
      `ESTABLISHED`
- [ ] VNet peering `Connected` on both the spoke and hub VNets
- [ ] Classic compute starts without public IP addresses
- [ ] Serverless and classic compute reach every approved on-premises destination
- [ ] Serverless compute reaches every approved internet destination, and is refused everywhere else
- [ ] HAProxy service and VM failover tested in both directions
- [ ] Private data storage access and Unity Catalog storage validation pass, including **Test connection** on the
      platform's external location
- [ ] Pipeline deployment and representative workload validation pass
- [ ] Diagnostic logs arrive in Log Analytics
