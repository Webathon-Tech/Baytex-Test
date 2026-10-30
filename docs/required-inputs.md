# Required Inputs

The decisions and values to collect and approve for each environment before its first plan. They are recorded in the
environment's `environments/<env>/terraform.tfvars` and `bootstrap/<env>/terraform.tfvars`, which show the format;
every input is described in the [configuration reference](configuration-reference.md). A value is approved when the
pull request that sets it is approved.

## Azure and Databricks

- Baytex Microsoft Entra tenant ID
- Environment subscription ID
- Azure Databricks account ID
- Existing Canada Central Unity Catalog metastore ID
- Confirmation that the deployment service principal is in the Databricks account with the Account Admin role
- Confirmation that a metastore admin has granted the deployment service principal `CREATE STORAGE CREDENTIAL` and
  `CREATE EXTERNAL LOCATION` on the metastore

## Naming and tagging

- Organisation, workload, region and instance codes
- Owner, cost centre and data classification tag values
- Globally unique names for the data storage account, the workspace root storage account and the state storage account

## Networking

- Environment VNet CIDR, not overlapping any other network the hub reaches
- Databricks host and container subnet CIDRs
- Private endpoint subnet CIDR
- Proxy subnet CIDR
- Static addresses for the blob and dfs private endpoints, inside the private endpoint subnet
- Existing hub VNet resource ID, used for the hub-side peering command in the outputs
- Confirmation that Baytex Infrastructure creates the VNet peering in both directions; the Terraform peering flags stay
  `false`
- Cisco firewall private IP
- The prefixes the Databricks subnets route to the firewall: the aggregate covering the other Azure spokes, the
  on-premises ranges and any vendor VPN host
- Corporate DNS servers
- Confirmation that Baytex Infrastructure creates the blob and dfs Private DNS record sets; the zone ID lists stay empty
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

- Visibility model: all-subscription visibility by default, because Azure Databricks does not publish the subscriptions
  its NCC private endpoints come from; explicit subscription IDs only if Baytex requires them
- Auto-approval subscriptions, normally none: the deploy pipeline approves the Databricks connections by private
  endpoint name

## Security and operations

- HAProxy SSH public key, from a key pair created for this environment, with the private key held in a Baytex vault
- Approved SSH source CIDRs, or confirmation that administration uses `az vm run-command` only
- HAProxy VM size
- Acceptance of the HAProxy patch windows: Sunday 14:00–16:00 and 18:00–20:00 Alberta Time
- Log Analytics retention
- Alert email receivers
- Owner of Azure Monitor Agent, endpoint detection and Arctic Wolf onboarding for the HAProxy VMs
- Approval for public workspace front-end access

## Unity Catalog handoff

- Metastore administrator
- The container the platform's external location covers, `unity-catalog` unless another name is agreed; it cannot be
  changed safely once catalogs use it
- The account-level groups, if any, that the platform grants privileges on the external location through
  `unity_catalog_external_location_grants`
- Catalog naming for the environment
- Account-level groups and owners
- Workspace binding model and cross-environment access
- Representative workload and its acceptance criteria
