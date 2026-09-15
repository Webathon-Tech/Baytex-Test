# Configuration Reference

How configuration reaches Terraform, how resources are named and tagged, and every input and output of the platform
and state backend roots.

## How configuration is supplied

The `.tf` files in `environments/dev`, `environments/test` and `environments/prod` are identical. What makes each
environment different is its `terraform.tfvars`, which is never committed to git.

1. Each environment has two GitHub Environments, `<env>-plan` and `<env>-apply`.
2. Both hold a `TFVARS` variable containing the complete `terraform.tfvars` for `environments/<env>`, and a
   `BOOTSTRAP_TFVARS` variable containing the complete `terraform.tfvars` for `bootstrap/<env>`.
3. At run time the workflow writes that content to disk and runs Terraform against it.

Setting the variables is described in [GitHub setup](github-setup.md#4-variables-per-environment).

### Example files

Each root folder carries example files in the same format:

| File | Contents |
| --- | --- |
| `baytex.terraform.tfvars.example` | The values for Baytex's subscriptions. This is the content to place in `TFVARS` or `BOOTSTRAP_TFVARS`. |
| `terraform.tfvars.example` | A complete reference configuration that sets every input. |
| `environments/<env>/backend.hcl.example` | Backend settings for initialising a platform root by hand. |

Every example lists its values in the section order of the root's `variables.tf`, under the same section headings,
with a comment on what each value controls.

### Input validation

`variables.tf` rejects malformed values when a plan is created, before anything in Azure changes. The rules check:

- GUID formats for the tenant, subscription, Databricks account, metastore and Private Link Service subscriptions
- Lowercase naming codes and a three-digit instance number
- IPv4 CIDRs, with every subnet inside `vnet_cidr`
- IPv4 addresses for the DNS servers and the firewall
- Proxy VM, load balancer frontend and Private Link Service NAT addresses inside the proxy subnet, with no address used
  twice
- A VNet resource ID for `hub_vnet_id`, required whenever a peering flag is `true`
- `privatelink.blob.core.windows.net` and `privatelink.dfs.core.windows.net` zone resource IDs for the DNS zone lists
- Static private endpoint addresses inside the private endpoint subnet, above the four addresses Azure reserves at the
  start of every subnet, and different from each other
- Unique IPv4 prefixes in `firewall_routes`, at least one of them, and no `0.0.0.0/0`
- Network security group rule names, priorities between 1000 and 4096, unique within a direction, a valid direction,
  access and protocol, and exactly one form of destination address
- Domain names without a scheme, port or path in `serverless_allowed_internet_destinations`, and at least one of them
  whenever the serverless restriction mode is `RESTRICTED_ACCESS`
- Storage account names, container names, SSH key format, email addresses and Log Analytics retention between 30 and
  730 days
- Auto-approval subscriptions that are also in the visibility list

A failed rule stops the plan with `Invalid value for variable` and a message naming the value to correct.

## Naming convention

Names are composed from `organization`, `workload`, `environment`, `region_short` and `instance`. The resource prefix is
`<organization>-<workload>-<environment>-<region_short>-<instance>`, for example `bte-dbx-dev-cnc-001`.

| Resource | Pattern | Example for dev |
| --- | --- | --- |
| Resource groups | `rg-<org>-<workload>-<env>-<purpose>-<region>-<instance>` | `rg-bte-dbx-dev-network-cnc-001` |
| Databricks managed resource group | `rg-<org>-<workload>-<env>-dbx-managed-<region>-<instance>` | `rg-bte-dbx-dev-dbx-managed-cnc-001` |
| Virtual network | `vnet-<prefix>` | `vnet-bte-dbx-dev-cnc-001` |
| Subnets | `snet-<org>-<workload>-<env>-<purpose>-<region>-<instance>` | `snet-bte-dbx-dev-dbx-host-cnc-001` |
| Network security groups | `nsg-<prefix>-<purpose>` | `nsg-bte-dbx-dev-cnc-001-proxy` |
| NAT Gateway and public IP | `nat-<prefix>`, `pip-<prefix>-nat` | `nat-bte-dbx-dev-cnc-001` |
| Route tables | `rt-<prefix>-databricks`, `rt-<prefix>-default` | `rt-bte-dbx-dev-cnc-001-default` |
| VNet peerings | `peer-<prefix>-to-hub`, `peer-hub-to-<prefix>` | `peer-hub-to-bte-dbx-dev-cnc-001` |
| Databricks workspace | `dbw-<prefix>` | `dbw-bte-dbx-dev-cnc-001` |
| Access Connectors | `ac-<org>-<workload>-<env>-root-<region>-<instance>`, `...-data-...` | `ac-bte-dbx-dev-data-cnc-001` |
| Network Connectivity Configuration | `ncc-<prefix>` | `ncc-bte-dbx-dev-cnc-001` |
| Databricks network policy | `np-<prefix>` | `np-bte-dbx-dev-cnc-001` |
| HAProxy VMs | `vm-<prefix>-proxy-01`, `vm-<prefix>-proxy-02` | `vm-bte-dbx-dev-cnc-001-proxy-01` |
| Load balancer | `lb-<prefix>-proxy` | `lb-bte-dbx-dev-cnc-001-proxy` |
| Private Link Services | `pls-<prefix>-<destination>` | `pls-bte-dbx-dev-cnc-001-sql6` |
| Storage private endpoints | `pe-<storage account>-blob`, `pe-<storage account>-dfs` | `pe-stbtedbxdevcnc001-dfs` |
| Log Analytics and action group | `log-<prefix>`, `ag-<prefix>` | `log-bte-dbx-dev-cnc-001` |

Storage account names are globally unique and set directly: `data_storage_account_name`,
`workspace_root_storage_account_name`, and `storage_account_name` in the bootstrap root.

## Tags

Every resource that supports tags receives:

| Tag | Value |
| --- | --- |
| `Application` | `AzureDatabricks` |
| `BusinessUnit` | `BI` |
| `Environment` | The environment name, capitalised |
| `ManagedBy` | `Terraform` |
| `Owner` | `owner` |
| `CostCentre` | `cost_centre` |
| `DataClassification` | `data_classification` |
| `Project` | `Baytex Terraform Foundations` |

`additional_tags` are merged over these.

## Platform inputs

Inputs of `environments/<env>`, in the order of `variables.tf`. An input without a default must be set.

### Subscription and Databricks account

| Variable | Default | Description |
| --- | --- | --- |
| `tenant_id` | required | Microsoft Entra tenant ID that holds the subscription and the Databricks account. |
| `subscription_id` | required | Azure subscription this environment deploys into. |
| `databricks_account_id` | required | Azure Databricks account ID, shown in the account console. |
| `existing_metastore_id` | required | ID of the existing regional Unity Catalog metastore. It is reported in the `unity_catalog_handoff` output; Baytex BI owns the metastore assignment. |

### Naming

| Variable | Default | Description |
| --- | --- | --- |
| `location` | `"canadacentral"` | Azure region for every resource. |
| `organization` | `"bte"` | Organisation code used in every resource name. |
| `workload` | `"dbx"` | Workload code used in every resource name. |
| `environment` | `"dev"` | Environment code used in resource names and tags. |
| `region_short` | `"cnc"` | Short region code used in every resource name. |
| `instance` | `"001"` | Three-digit instance number used in every resource name. |

### Tags

| Variable | Default | Description |
| --- | --- | --- |
| `owner` | `"Baytex Infrastructure"` | Value of the Owner tag. |
| `cost_centre` | `"TO-BE-CONFIRMED"` | Value of the CostCentre tag. |
| `data_classification` | `"Internal"` | Value of the DataClassification tag. |
| `additional_tags` | `{}` | Extra tags merged over the standard tags. |

### Spoke network

| Variable | Default | Description |
| --- | --- | --- |
| `vnet_cidr` | required | Address space of the spoke VNet. |
| `databricks_host_subnet_cidr` | required | Address prefix of the Databricks host (public) subnet. Must be inside `vnet_cidr`. |
| `databricks_container_subnet_cidr` | required | Address prefix of the Databricks container (private) subnet. Must be inside `vnet_cidr`. |
| `private_endpoint_subnet_cidr` | required | Address prefix of the private endpoint subnet. Must be inside `vnet_cidr`. |
| `proxy_subnet_cidr` | required | Address prefix of the proxy subnet, which holds the HAProxy VMs, load balancer frontends and Private Link Service NAT IPs. Must be inside `vnet_cidr`. |
| `dns_servers` | required | DNS servers, in preference order, assigned to the VNet and used by the HAProxy resolver. |

### Hub peering and routing

| Variable | Default | Description |
| --- | --- | --- |
| `hub_vnet_id` | `null` | Resource ID of the hub VNet. Required when either peering flag is `true`. The hub subscription, resource group and VNet name are read from it. |
| `create_spoke_to_hub_peering` | `false` | Create the spoke-side peering, from the spoke VNet to the hub VNet. When the hub is in another subscription, the deployment identity needs Network Contributor on the hub VNet. |
| `create_hub_to_spoke_peering` | `false` | Create the hub-side peering, from the hub VNet to the spoke VNet, in the hub subscription. The deployment identity needs Network Contributor on the hub VNet. |
| `cisco_firewall_private_ip` | required | Private IP of the hub firewall, used as the next hop by both route tables. |
| `firewall_routes` | required | Prefixes the Databricks subnets send to the firewall, keyed by route name. One aggregate prefix normally covers every Azure spoke, so spoke-to-spoke traffic reaches the firewall without a route per spoke. The proxy and private endpoint subnets send all traffic to the firewall regardless of this map. |

### Network security group rules

A network security group matches addresses, CIDR ranges and service tags, never domain names. A destination that is only
known by name is allowed on the firewall, and for serverless compute in `serverless_allowed_internet_destinations`.

| Variable | Default | Description |
| --- | --- | --- |
| `databricks_nsg_rules` | `{}` | Rules added to both Databricks subnet NSGs, keyed by rule name. Azure Databricks maintains its own rules on these NSGs, so these priorities start at 1000. |
| `proxy_nsg_rules` | `{}` | Rules added to the proxy NSG, keyed by rule name, alongside the health probe, Private Link Service and SSH rules the platform creates. |

Each entry sets `priority` and `description`, and takes defaults for the rest:

| Field | Default | Notes |
| --- | --- | --- |
| `priority` | required | Between 1000 and 4096, unique within its direction |
| `description` | required | Shown on the rule in Azure |
| `direction` | `"Outbound"` | `Inbound` or `Outbound` |
| `access` | `"Allow"` | `Allow` or `Deny` |
| `protocol` | `"Tcp"` | `Tcp`, `Udp`, `Icmp`, `Esp`, `Ah` or `*` |
| `source_address_prefix` | `"VirtualNetwork"` | An address, CIDR range or service tag |
| `source_address_prefixes` | unset | A list of them, which replaces `source_address_prefix` |
| `source_port_ranges` | `["*"]` | |
| `destination_address_prefix` | unset | Exactly one destination form must be set |
| `destination_address_prefixes` | unset | A list, which replaces `destination_address_prefix` |
| `destination_port_ranges` | `["443"]` | |

Allow rules record the approved destinations without restricting anything on their own, because the Databricks subnets
already reach the internet through the NAT Gateway. Restricting them takes a Deny rule at a higher priority number than
every Allow rule.

### Data foundation

| Variable | Default | Description |
| --- | --- | --- |
| `data_storage_account_name` | required | Globally unique name of the ADLS Gen2 data storage account. |
| `data_containers` | `["managed", "external", "landing", "checkpoints"]` | Containers created in the data storage account. |
| `blob_private_dns_zone_ids` | `[]` | Resource IDs of `privatelink.blob.core.windows.net` zones the blob private endpoint registers in. Leave empty to create no DNS zone group. Zones in another subscription need Private DNS Zone Contributor for the deployment identity. |
| `dfs_private_dns_zone_ids` | `[]` | Resource IDs of `privatelink.dfs.core.windows.net` zones the dfs private endpoint registers in. Leave empty to create no DNS zone group. Zones in another subscription need Private DNS Zone Contributor for the deployment identity. |
| `blob_private_endpoint_ip` | `null` | Static private IP of the blob private endpoint. Setting it keeps the address stable when the environment is rebuilt, so the DNS records and firewall rules that point at it stay valid. |
| `dfs_private_endpoint_ip` | `null` | Static private IP of the dfs private endpoint, on the same terms. |

### HAProxy tier

| Variable | Default | Description |
| --- | --- | --- |
| `admin_ssh_source_cidrs` | `[]` | CIDRs allowed to SSH to the HAProxy VMs. An empty list creates no SSH rule, and the VMs remain reachable through `az vm run-command`. |
| `ssh_public_key` | required | SSH public key for the `azureadmin` user on the HAProxy VMs. Password authentication is disabled. |
| `proxy_vm_size` | `"Standard_D4s_v6"` | Azure VM size of both HAProxy VMs. |
| `proxy_vm_private_ips` | required | Static private IPs of the two HAProxy VMs, in zone 1 and zone 2 order. Both must be inside `proxy_subnet_cidr`. |
| `on_prem_endpoints` | required | On-premises destinations, keyed by a short name. Each gets a load balancer frontend on `frontend_ip`, a Private Link Service with its NAT IP on `pls_nat_ip`, and an HAProxy listener on `listen_port` that forwards to `target_fqdn:target_port`. `domain_name` is the name serverless compute uses to reach the destination. |

### Private Link Service access

| Variable | Default | Description |
| --- | --- | --- |
| `allow_all_subscriptions_pls_visibility` | `false` | Allow any subscription that knows a Private Link Service alias to request a connection. Requests still require approval unless auto-approved. Explicit `pls_visibility_subscription_ids` are preferred. |
| `pls_visibility_subscription_ids` | `[]` | Subscriptions allowed to discover the Private Link Services. Required unless `allow_all_subscriptions_pls_visibility` is `true`. |
| `pls_auto_approval_subscription_ids` | `[]` | Subscriptions whose private endpoint connections to the Private Link Services are approved automatically. Must be a subset of `pls_visibility_subscription_ids`. An empty list means every connection is approved manually. |

### Databricks workspace

| Variable | Default | Description |
| --- | --- | --- |
| `workspace_root_storage_account_name` | required | Globally unique name of the root (DBFS) storage account Databricks creates in the managed resource group. Set when the workspace is created. |
| `workspace_public_network_access_enabled` | `true` | Allow users, Power BI and GitHub to reach the workspace front end from public networks. Classic compute has no public IPs either way. |
| `workspace_default_storage_firewall_enabled` | `false` | Firewall the Databricks-managed root storage account. When `true`, the root Access Connector is attached to the workspace. The connector itself is created either way, because Azure refuses to delete a connector a workspace still refers to. |
| `workspace_infrastructure_encryption_enabled` | `true` | Enable a second layer of infrastructure encryption on the root storage account. Set when the workspace is created. |

### Serverless egress

The Databricks network policy is the only place an outbound allow list can be expressed by domain name. It governs
serverless compute; classic compute leaves through the NAT Gateway and is governed by the route tables, the network
security group rules and the firewall.

| Variable | Default | Description |
| --- | --- | --- |
| `create_serverless_network_policy` | `true` | Create the network policy for this environment and attach it to the workspace. Leave it `false` to keep the account default policy. |
| `serverless_egress_restriction_mode` | `"RESTRICTED_ACCESS"` | `FULL_ACCESS` lets serverless compute reach any internet destination. `RESTRICTED_ACCESS` limits it to the list below. |
| `serverless_egress_enforcement_mode` | `"ENFORCED"` | `ENFORCED` blocks destinations outside the list. `DRY_RUN` allows them and records them instead, so the list can be validated before it is enforced. |
| `serverless_allowed_internet_destinations` | `[]` | Domain names serverless compute may reach on the internet. The data storage account and the on-premises destinations are reached through the NCC private endpoint rules and need no entry. |

The policy matches the domain name only, never a port or a path, so a destination on a non-standard port is listed once
here and its port is allowed on the firewall.

### Operations

| Variable | Default | Description |
| --- | --- | --- |
| `log_analytics_retention_days` | `90` | Retention period of the Log Analytics workspace, in days. |
| `enable_diagnostics` | `true` | Send diagnostic logs and metrics from the workspace, data storage account, load balancer and NAT Gateway to Log Analytics. |
| `alert_email_receivers` | `{}` | Email receivers on the platform action group, as a map of receiver name to email address. An empty map creates no action group. |

### Settings fixed at creation

Changing any of these after the first deploy replaces the resource that uses it, so confirm them before the first apply:

- `workspace_root_storage_account_name` and `workspace_infrastructure_encryption_enabled`, and the naming inputs, VNet
  and subnets the workspace uses — the workspace is replaced
- `on_prem_endpoints` and `dns_servers` — the HAProxy VMs are replaced, because their cloud-init configuration changes
- `data_storage_account_name` — the data storage account is replaced
- `blob_private_endpoint_ip` and `dfs_private_endpoint_ip` — the matching private endpoint is replaced, and it returns
  with the new address

## Platform outputs

### Spoke network

| Output | Description |
| --- | --- |
| `vnet_id` | Resource ID of the spoke VNet. |
| `vnet_cidr` | Address space of the spoke VNet. |
| `nat_public_ip` | Public IP address the Databricks subnets use for internet egress. |
| `spoke_to_hub_peering_id` | Resource ID of the spoke-side peering, or `null` when `create_spoke_to_hub_peering` is `false`. |
| `hub_to_spoke_peering_id` | Resource ID of the hub-side peering, or `null` when `create_hub_to_spoke_peering` is `false`. |
| `hub_side_peering_command` | Azure CLI command that creates the hub-side peering, or `null` when Terraform manages it or `hub_vnet_id` is not set. |
| `network_security_group_names` | Names of the network security groups on the Databricks and proxy subnets. |

### Databricks workspace

| Output | Description |
| --- | --- |
| `databricks_workspace_arm_id` | Azure resource ID of the Databricks workspace. |
| `databricks_workspace_id` | Numeric Databricks workspace ID. |
| `databricks_workspace_url` | Workspace URL. |
| `root_access_connector_id` | Resource ID of the root Access Connector. It is attached to the workspace only while the default storage firewall is on. |
| `root_access_connector_principal_id` | Principal ID of the root Access Connector's managed identity. |

### Serverless connectivity

| Output | Description |
| --- | --- |
| `ncc_id` | ID of the Network Connectivity Configuration. |
| `ncc_private_endpoint_rules` | Rule ID, private endpoint name and connection state of every NCC private endpoint rule. Approve only connections whose private endpoint name appears here. |
| `private_link_service_ids` | Resource IDs of the Private Link Services, keyed by destination name. |

### Data foundation

| Output | Description |
| --- | --- |
| `data_storage_account_id` | Resource ID of the data storage account. |
| `data_storage_account_name` | Name of the data storage account. |
| `data_access_connector_id` | Resource ID of the data Access Connector, used for the Unity Catalog storage credential. |
| `data_access_connector_principal_id` | Principal ID of the data Access Connector. |
| `data_private_endpoint_ips` | Private IP addresses of the blob and dfs private endpoints. |
| `container_urls` | `abfss://` URL of each data container, keyed by container name. |

### Serverless egress

| Output | Description |
| --- | --- |
| `serverless_network_policy_id` | ID of the network policy attached to the workspace, or `null` when `create_serverless_network_policy` is `false`. |
| `serverless_egress_allowed_destinations` | Domain names serverless compute may reach on the internet, or `null` when `create_serverless_network_policy` is `false`. |

### Handoffs

| Output | Description |
| --- | --- |
| `firewall_handoff` | Source subnets, routes, next hop and destination matrix for the firewall and on-premises routing changes. |
| `unity_catalog_handoff` | Workspace, metastore, data Access Connector and storage details for the Baytex BI Unity Catalog configuration. |

## State backend inputs and outputs

Inputs of `bootstrap/<env>`:

| Variable | Default | Description |
| --- | --- | --- |
| `tenant_id` | required | Microsoft Entra tenant ID. |
| `subscription_id` | required | Azure subscription that holds this environment's Terraform state. |
| `location` | `"canadacentral"` | Azure region of the resource group and storage account. |
| `resource_group_name` | required | Resource group for the Terraform state account. Must match `TF_STATE_RESOURCE_GROUP` on the same GitHub Environment. |
| `storage_account_name` | required | Globally unique storage account name. Must match `TF_STATE_STORAGE_ACCOUNT` on the same GitHub Environment. |
| `container_name` | `"tfstate"` | Blob container holding the state files. Must match `TF_STATE_CONTAINER` on the same GitHub Environment. |
| `tags` | `Application` and `ManagedBy` | Tags applied to the resource group and storage account. |
| `state_blob_data_contributor_principal_ids` | `[]` | Object IDs, not application IDs, granted Storage Blob Data Contributor on the state account. Leave empty unless an operator needs direct state access. |

Outputs: `resource_group_name`, `storage_account_name`, `storage_account_id`, `container_name`, and `backend_hcl`, the
backend settings for the platform root.
