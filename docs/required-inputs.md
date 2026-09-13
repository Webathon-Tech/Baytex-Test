# Required Inputs

The decisions and values to collect and approve for each environment before its first plan. They become the
environment's `TFVARS` and `BOOTSTRAP_TFVARS`; every input is described in the
[configuration reference](configuration-reference.md), and `baytex.terraform.tfvars.example` in each root shows the
format. Proposed values in the example files are not approvals.

## Azure and Databricks

- Baytex Microsoft Entra tenant ID
- Environment subscription ID
- Azure Databricks account ID
- Existing Canada Central Unity Catalog metastore ID
- Confirmation that the deployment service principal is in the Databricks account with the Account Admin role

## Naming and tagging

- Organisation, workload, region and instance codes
- Owner, cost centre and data classification tag values
- Globally unique names for the data storage account, the workspace root storage account and the state storage account

## Networking

- Environment VNet CIDR, not overlapping any other network the hub reaches
- Databricks host and container subnet CIDRs
- Private endpoint subnet CIDR
- Proxy subnet CIDR
- Existing hub VNet resource ID
- Which peering directions Terraform creates (`create_spoke_to_hub_peering`, `create_hub_to_spoke_peering`), with Network
  Contributor on the hub VNet for any Terraform-managed direction
- Cisco firewall private IP
- On-premises prefixes the Databricks subnets route to the firewall
- Corporate DNS servers
- Blob and dfs Private DNS zone IDs with Private DNS Zone Contributor on those zones, or an approved manual DNS change
- Owner and change reference for the on-premises return routes

## On-premises destinations

For each SQL Server or Oracle destination:

- Domain name that serverless compute connects to
- Target fully qualified domain name and port that HAProxy forwards to
- Listener port
- Load balancer frontend IP and Private Link Service NAT IP in the proxy subnet

## Private Link Service and NCC

- Visibility model: explicit subscription IDs, or approved all-subscription visibility with manual connection approval
- Automatic or manual approval of private endpoint connections

## Security and operations

- HAProxy SSH public key
- Approved SSH source CIDRs, or confirmation that administration uses `az vm run-command` only
- HAProxy VM size
- Log Analytics retention
- Alert email receivers
- Owner of Azure Monitor Agent, endpoint detection and Arctic Wolf onboarding for the HAProxy VMs
- Approval for public workspace front-end access
- Default storage firewall decision, off by default

## Unity Catalog handoff

- Metastore administrator
- Catalog and storage location naming for the environment
- Account-level groups and owners
- Workspace binding model and cross-environment access
- Representative workload and its acceptance criteria
