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
- Static addresses for the data storage blob and dfs private endpoints, inside the private endpoint subnet
- Existing hub VNet resource ID
- Which peering directions Terraform creates (`create_spoke_to_hub_peering`, `create_hub_to_spoke_peering`), with Network
  Contributor on the hub VNet for any Terraform-managed direction
- Cisco firewall private IP
- The prefixes the Databricks subnets route to the firewall: the aggregate covering the other Azure spokes, the
  on-premises ranges and any vendor VPN host
- Corporate DNS servers
- Blob and dfs Private DNS zone IDs with Private DNS Zone Contributor on those zones, or an approved manual DNS change
- Owner and change reference for the on-premises return routes

## Outbound destinations

- The approved list of outbound destinations, by domain name, for serverless compute
- Whether the serverless policy is enforced from the first apply or run in dry-run mode first
- The destinations to record as network security group rules for classic compute, as addresses, CIDR ranges or service
  tags
- Whether classic compute egress is restricted by a Deny rule, and which destinations must be covered first

## On-premises destinations

For each SQL Server or Oracle destination:

- Domain name that serverless compute connects to
- Target fully qualified domain name and port that HAProxy forwards to
- Listener port
- Load balancer frontend IP and Private Link Service NAT IP in the proxy subnet

## Private Link Service and NCC

- Visibility model: explicit subscription IDs, or approved all-subscription visibility with manual connection approval
- Subscriptions whose connections to the Private Link Services Azure approves automatically; the deploy pipeline
  approves the remaining Databricks connections

## Security and operations

- HAProxy SSH public key
- Approved SSH source CIDRs, or confirmation that administration uses `az vm run-command` only
- HAProxy VM size
- Acceptance of the HAProxy weekend patch windows
- Log Analytics retention
- Alert email receivers
- Owner of Azure Monitor Agent, endpoint detection and Arctic Wolf onboarding for the HAProxy VMs
- Approval for public workspace front-end access
- Default storage firewall decision, off by default and fixed when the workspace is created

## Unity Catalog handoff

- Metastore administrator
- Catalog and storage location naming for the environment
- Account-level groups and owners
- Workspace binding model and cross-environment access
- Representative workload and its acceptance criteria
