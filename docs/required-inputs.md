# Required inputs before DEV deployment

The platform code is intentionally parameterized. Do not treat the values in `terraform.tfvars.example` as approved production inputs.

## Azure and Databricks

- Baytex tenant ID
- DEV subscription ID
- Existing Azure Databricks account ID
- Existing Canada Central Unity Catalog metastore ID
- Confirmation that the deployment identity is registered in the Databricks account and authorized for NCC operations

## Networking

- Approved DEV VNet CIDR
- Approved Databricks host/container subnet CIDRs
- Approved Private Endpoint subnet CIDR
- Approved HAProxy/PLS subnet CIDR
- Existing hub VNet resource ID
- Decision on whether AMTRA creates the spoke-side peering or Baytex creates both directions
- Cisco firewall private IP
- All on-premises route CIDRs
- Exact SQL/Oracle destination FQDN/IP/port matrix
- On-premises return-route owner and change ticket
- Corporate DNS servers
- Central Blob/DFS Private DNS zone IDs, or an approved manual DNS handoff

## Private Link Service/NCC

- Preferred: Microsoft/Databricks-managed consumer subscription IDs for restricted PLS visibility
- Alternative: explicit approval to temporarily allow all-subscription visibility while keeping manual connection approval
- Decision on manual versus automatic Private Endpoint connection approval

## Security and operations

- SSH public key
- Approved SSH source CIDRs or Bastion/jump-host path
- Log Analytics retention
- Alert receivers
- EDR/Arctic Wolf/Azure Monitor Agent onboarding owner
- Exception approval for initially public workspace front-end, if retained
- Confirmation that default Databricks storage firewall is enabled

## Baytex BI handoff

- Existing metastore ID and metastore administrator
- DEV catalog and storage-location naming
- Account-level groups and owners
- Workspace binding model
- Cross-environment access model for future Test/Prod
- Representative workload and pass/fail criteria
