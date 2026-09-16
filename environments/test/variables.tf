# ----------------------------------------------------------------------------------------------------------------------
# Input variables
# Sections follow the order of main.tf, and every terraform.tfvars.example lists its values in the same order.
# ----------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# Subscription and Databricks account
# ----------------------------------------------------------------------------------------------------------------------

variable "tenant_id" {
  description = "Microsoft Entra tenant ID that holds the subscription and the Databricks account."
  type        = string

  validation {
    condition     = can(regex("(?i)^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "subscription_id" {
  description = "Azure subscription this environment deploys into."
  type        = string

  validation {
    condition     = can(regex("(?i)^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "databricks_account_id" {
  description = "Azure Databricks account ID, shown in the account console."
  type        = string

  validation {
    condition     = can(regex("(?i)^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", var.databricks_account_id))
    error_message = "databricks_account_id must be a GUID."
  }
}

variable "existing_metastore_id" {
  description = "ID of the existing regional Unity Catalog metastore. It is reported in the unity_catalog_handoff output; Baytex BI owns the metastore assignment."
  type        = string

  validation {
    condition     = can(regex("(?i)^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", var.existing_metastore_id))
    error_message = "existing_metastore_id must be a GUID."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Naming
# Resource names are composed as <type>-<organization>-<workload>-<environment>-<purpose>-<region_short>-<instance>.
# ----------------------------------------------------------------------------------------------------------------------

variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "canadacentral"
}

variable "organization" {
  description = "Organisation code used in every resource name."
  type        = string
  default     = "bte"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.organization))
    error_message = "organization must contain only lowercase letters and digits."
  }
}

variable "workload" {
  description = "Workload code used in every resource name."
  type        = string
  default     = "dbx"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.workload))
    error_message = "workload must contain only lowercase letters and digits."
  }
}

variable "environment" {
  description = "Environment code used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "environment must contain only lowercase letters and digits."
  }
}

variable "region_short" {
  description = "Short region code used in every resource name."
  type        = string
  default     = "cnc"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.region_short))
    error_message = "region_short must contain only lowercase letters and digits."
  }
}

variable "instance" {
  description = "Three-digit instance number used in every resource name."
  type        = string
  default     = "001"

  validation {
    condition     = can(regex("^[0-9]{3}$", var.instance))
    error_message = "instance must be three digits, for example 001."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Tags
# ----------------------------------------------------------------------------------------------------------------------

variable "owner" {
  description = "Value of the Owner tag."
  type        = string
  default     = "Baytex Infrastructure"
}

variable "cost_centre" {
  description = "Value of the CostCentre tag."
  type        = string
  default     = "TO-BE-CONFIRMED"
}

variable "data_classification" {
  description = "Value of the DataClassification tag."
  type        = string
  default     = "Internal"
}

variable "additional_tags" {
  description = "Extra tags merged over the standard tags."
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------------------------------------------------------------
# Spoke network
# ----------------------------------------------------------------------------------------------------------------------

variable "vnet_cidr" {
  description = "Address space of the spoke VNet."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.vnet_cidr)) && can(cidrhost(var.vnet_cidr, 0))
    error_message = "vnet_cidr must be an IPv4 CIDR, for example 10.40.144.0/20."
  }
}

variable "databricks_host_subnet_cidr" {
  description = "Address prefix of the Databricks host (public) subnet. Must be inside vnet_cidr."
  type        = string

  validation {
    condition     = try(tonumber(split("/", var.databricks_host_subnet_cidr)[1]) >= tonumber(split("/", var.vnet_cidr)[1]) && cidrhost("${cidrhost(var.databricks_host_subnet_cidr, 0)}/${split("/", var.vnet_cidr)[1]}", 0) == cidrhost(var.vnet_cidr, 0), false)
    error_message = "databricks_host_subnet_cidr must be an IPv4 CIDR inside vnet_cidr."
  }
}

variable "databricks_container_subnet_cidr" {
  description = "Address prefix of the Databricks container (private) subnet. Must be inside vnet_cidr."
  type        = string

  validation {
    condition     = try(tonumber(split("/", var.databricks_container_subnet_cidr)[1]) >= tonumber(split("/", var.vnet_cidr)[1]) && cidrhost("${cidrhost(var.databricks_container_subnet_cidr, 0)}/${split("/", var.vnet_cidr)[1]}", 0) == cidrhost(var.vnet_cidr, 0), false)
    error_message = "databricks_container_subnet_cidr must be an IPv4 CIDR inside vnet_cidr."
  }
}

variable "private_endpoint_subnet_cidr" {
  description = "Address prefix of the private endpoint subnet. Must be inside vnet_cidr."
  type        = string

  validation {
    condition     = try(tonumber(split("/", var.private_endpoint_subnet_cidr)[1]) >= tonumber(split("/", var.vnet_cidr)[1]) && cidrhost("${cidrhost(var.private_endpoint_subnet_cidr, 0)}/${split("/", var.vnet_cidr)[1]}", 0) == cidrhost(var.vnet_cidr, 0), false)
    error_message = "private_endpoint_subnet_cidr must be an IPv4 CIDR inside vnet_cidr."
  }
}

variable "proxy_subnet_cidr" {
  description = "Address prefix of the proxy subnet, which holds the HAProxy VMs, load balancer frontends and Private Link Service NAT IPs. Must be inside vnet_cidr."
  type        = string

  validation {
    condition     = try(tonumber(split("/", var.proxy_subnet_cidr)[1]) >= tonumber(split("/", var.vnet_cidr)[1]) && cidrhost("${cidrhost(var.proxy_subnet_cidr, 0)}/${split("/", var.vnet_cidr)[1]}", 0) == cidrhost(var.vnet_cidr, 0), false)
    error_message = "proxy_subnet_cidr must be an IPv4 CIDR inside vnet_cidr."
  }
}

variable "dns_servers" {
  description = "DNS servers, in preference order, assigned to the VNet and used by the HAProxy resolver."
  type        = list(string)

  validation {
    condition     = length(var.dns_servers) > 0 && alltrue([for ip in var.dns_servers : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) && can(cidrhost("${ip}/32", 0))])
    error_message = "dns_servers must contain at least one IPv4 address."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Hub peering and routing
# ----------------------------------------------------------------------------------------------------------------------

variable "hub_vnet_id" {
  description = "Resource ID of the hub VNet. Required when either peering flag is true. The hub subscription, resource group and VNet name are read from it."
  type        = string
  default     = null

  validation {
    condition     = var.hub_vnet_id == null || can(regex("(?i)^/subscriptions/[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", var.hub_vnet_id))
    error_message = "hub_vnet_id must be a VNet resource ID: /subscriptions/<subscription>/resourceGroups/<resource group>/providers/Microsoft.Network/virtualNetworks/<name>."
  }

  validation {
    condition     = var.hub_vnet_id != null || !(var.create_spoke_to_hub_peering || var.create_hub_to_spoke_peering)
    error_message = "hub_vnet_id is required when create_spoke_to_hub_peering or create_hub_to_spoke_peering is true."
  }
}

variable "create_spoke_to_hub_peering" {
  description = "Create the spoke-side peering, from the spoke VNet to the hub VNet. When the hub is in another subscription, the deployment identity needs Network Contributor on the hub VNet."
  type        = bool
  default     = false
}

variable "create_hub_to_spoke_peering" {
  description = "Create the hub-side peering, from the hub VNet to the spoke VNet, in the hub subscription. The deployment identity needs Network Contributor on the hub VNet."
  type        = bool
  default     = false
}

variable "cisco_firewall_private_ip" {
  description = "Private IP of the hub firewall, used as the next hop by both route tables."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.cisco_firewall_private_ip)) && can(cidrhost("${var.cisco_firewall_private_ip}/32", 0))
    error_message = "cisco_firewall_private_ip must be an IPv4 address."
  }
}

variable "firewall_routes" {
  description = "Prefixes the Databricks subnets send to the firewall, keyed by route name. One aggregate prefix normally covers every Azure spoke, so spoke-to-spoke traffic reaches the firewall without a route per spoke. The proxy and private endpoint subnets send all traffic to the firewall regardless of this map."
  type = map(object({
    address_prefix = string
  }))

  validation {
    condition     = length(var.firewall_routes) > 0
    error_message = "firewall_routes must contain at least one prefix."
  }

  validation {
    condition     = alltrue([for name in keys(var.firewall_routes) : can(regex("^[a-z0-9-]+$", name))])
    error_message = "firewall_routes keys must contain only lowercase letters, digits and hyphens."
  }

  validation {
    condition     = alltrue([for route in values(var.firewall_routes) : can(regex("^([0-9]{1,3}[.]){3}[0-9]{1,3}/[0-9]{1,2}$", route.address_prefix)) && can(cidrhost(route.address_prefix, 0))])
    error_message = "Every firewall_routes address_prefix must be an IPv4 CIDR."
  }

  validation {
    condition     = length(distinct([for route in values(var.firewall_routes) : route.address_prefix])) == length(var.firewall_routes)
    error_message = "Every firewall_routes address_prefix must be unique; Azure rejects a route table with the same prefix twice."
  }

  validation {
    condition     = !contains([for route in values(var.firewall_routes) : route.address_prefix], "0.0.0.0/0")
    error_message = "firewall_routes must not contain 0.0.0.0/0, because the Databricks subnets reach the internet through the NAT Gateway."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Network security group rules
# Network security groups match addresses, CIDR ranges and service tags, never domain names.
# A destination that is only known by name is allowed on the firewall, and for serverless compute in serverless_allowed_internet_destinations below.
# ----------------------------------------------------------------------------------------------------------------------

variable "databricks_nsg_rules" {
  description = "Rules added to both Databricks subnet NSGs, keyed by rule name. Azure Databricks maintains its own rules on these NSGs, so these priorities start at 1000. Adding Allow rules alone records the approved destinations without restricting anything, because the Databricks subnets already reach the internet through the NAT Gateway; add a Deny rule at a higher priority number to restrict them."
  type = map(object({
    priority                     = number
    direction                    = optional(string, "Outbound")
    access                       = optional(string, "Allow")
    protocol                     = optional(string, "Tcp")
    source_address_prefix        = optional(string, "VirtualNetwork")
    source_address_prefixes      = optional(list(string))
    source_port_ranges           = optional(list(string), ["*"])
    destination_address_prefix   = optional(string)
    destination_address_prefixes = optional(list(string))
    destination_port_ranges      = optional(list(string), ["443"])
    description                  = string
  }))
  default = {}
}

variable "proxy_deny_other_vnet_inbound" {
  description = "Close the proxy subnet to everything arriving from the virtual network that is not explicitly allowed. Azure's own default rule otherwise admits any address in the VNet, the hub and the networks reached through it, on every port. The load balancer health probe, Private Link Service traffic on the listener ports and any approved administrative SSH are allowed before it."
  type        = bool
  default     = true
}

variable "proxy_nsg_rules" {
  description = "Rules added to the proxy NSG, keyed by rule name, alongside the health probe, Private Link Service and SSH rules the platform creates. Priorities run from 1000 to 4095; 4096 is reserved for the rule that denies everything else from the virtual network."
  type = map(object({
    priority                     = number
    direction                    = optional(string, "Outbound")
    access                       = optional(string, "Allow")
    protocol                     = optional(string, "Tcp")
    source_address_prefix        = optional(string, "VirtualNetwork")
    source_address_prefixes      = optional(list(string))
    source_port_ranges           = optional(list(string), ["*"])
    destination_address_prefix   = optional(string)
    destination_address_prefixes = optional(list(string))
    destination_port_ranges      = optional(list(string), ["443"])
    description                  = string
  }))
  default = {}
}

# ----------------------------------------------------------------------------------------------------------------------
# Data foundation
# ----------------------------------------------------------------------------------------------------------------------

variable "data_storage_account_name" {
  description = "Globally unique name of the ADLS Gen2 data storage account."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.data_storage_account_name))
    error_message = "data_storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "data_containers" {
  description = "Containers created in the data storage account."
  type        = set(string)
  default     = ["managed", "external", "landing", "checkpoints"]

  validation {
    condition     = alltrue([for name in var.data_containers : can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$", name)) && !strcontains(name, "--")])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }
}

variable "blob_private_dns_zone_ids" {
  description = "Resource IDs of privatelink.blob.core.windows.net zones the blob private endpoint registers in. Leave empty to create no DNS zone group. Zones in another subscription need Private DNS Zone Contributor for the deployment identity."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.blob_private_dns_zone_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/privatelink\\.blob\\.core\\.windows\\.net$", id))])
    error_message = "Every blob_private_dns_zone_ids entry must be the resource ID of a privatelink.blob.core.windows.net Private DNS zone."
  }
}

variable "dfs_private_dns_zone_ids" {
  description = "Resource IDs of privatelink.dfs.core.windows.net zones the dfs private endpoint registers in. Leave empty to create no DNS zone group. Zones in another subscription need Private DNS Zone Contributor for the deployment identity."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.dfs_private_dns_zone_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/privatelink\\.dfs\\.core\\.windows\\.net$", id))])
    error_message = "Every dfs_private_dns_zone_ids entry must be the resource ID of a privatelink.dfs.core.windows.net Private DNS zone."
  }
}

variable "blob_private_endpoint_ip" {
  description = "Static private IP of the blob private endpoint. Setting it keeps the address stable when the environment is rebuilt, so the DNS records and firewall rules that point at it stay valid. Null lets Azure allocate one dynamically."
  type        = string
  default     = null

  validation {
    condition = var.blob_private_endpoint_ip == null || try(
      can(regex("^([0-9]{1,3}[.]){3}[0-9]{1,3}$", var.blob_private_endpoint_ip)) &&
      cidrhost("${var.blob_private_endpoint_ip}/${split("/", var.private_endpoint_subnet_cidr)[1]}", 0) == cidrhost(var.private_endpoint_subnet_cidr, 0) &&
      !contains([for index in range(4) : cidrhost(var.private_endpoint_subnet_cidr, index)], var.blob_private_endpoint_ip),
    false)
    error_message = "blob_private_endpoint_ip must be an IPv4 address inside private_endpoint_subnet_cidr, above the four addresses Azure reserves at the start of every subnet."
  }
}

variable "dfs_private_endpoint_ip" {
  description = "Static private IP of the dfs private endpoint. Setting it keeps the address stable when the environment is rebuilt, so the DNS records and firewall rules that point at it stay valid. Null lets Azure allocate one dynamically."
  type        = string
  default     = null

  validation {
    condition = var.dfs_private_endpoint_ip == null || try(
      can(regex("^([0-9]{1,3}[.]){3}[0-9]{1,3}$", var.dfs_private_endpoint_ip)) &&
      cidrhost("${var.dfs_private_endpoint_ip}/${split("/", var.private_endpoint_subnet_cidr)[1]}", 0) == cidrhost(var.private_endpoint_subnet_cidr, 0) &&
      !contains([for index in range(4) : cidrhost(var.private_endpoint_subnet_cidr, index)], var.dfs_private_endpoint_ip),
    false)
    error_message = "dfs_private_endpoint_ip must be an IPv4 address inside private_endpoint_subnet_cidr, above the four addresses Azure reserves at the start of every subnet."
  }

  validation {
    condition     = var.dfs_private_endpoint_ip == null || var.dfs_private_endpoint_ip != var.blob_private_endpoint_ip
    error_message = "dfs_private_endpoint_ip must differ from blob_private_endpoint_ip."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# HAProxy tier
# ----------------------------------------------------------------------------------------------------------------------

variable "admin_ssh_source_cidrs" {
  description = "CIDRs allowed to SSH to the HAProxy VMs. An empty list creates no SSH rule, and the VMs remain reachable through az vm run-command."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.admin_ssh_source_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr)) && can(cidrhost(cidr, 0))])
    error_message = "Every admin_ssh_source_cidrs entry must be an IPv4 CIDR."
  }
}

variable "ssh_public_key" {
  description = "SSH public key for the azureadmin user on the HAProxy VMs. Password authentication is disabled."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key starting with ssh-ed25519, ssh-rsa or ecdsa-sha2-nistp256/384/521."
  }
}

variable "proxy_vm_size" {
  description = "Azure VM size of every HAProxy VM."
  type        = string
  default     = "Standard_D4s_v6"

  validation {
    condition     = can(regex("^Standard_", var.proxy_vm_size))
    error_message = "proxy_vm_size must be an Azure VM size name, for example Standard_D4s_v6."
  }
}

variable "proxy_vm_private_ips" {
  description = "Static private IPs of the HAProxy VMs, two or three, in zone order: the first VM is placed in zone 1, the second in zone 2 and a third in zone 3. All must be inside proxy_subnet_cidr."
  type        = list(string)

  validation {
    condition     = length(var.proxy_vm_private_ips) >= 2 && length(var.proxy_vm_private_ips) <= 3 && length(distinct(var.proxy_vm_private_ips)) == length(var.proxy_vm_private_ips)
    error_message = "Two or three different HAProxy VM private IPs are required, one per availability zone."
  }

  validation {
    condition     = alltrue([for ip in var.proxy_vm_private_ips : try(can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) && cidrhost("${ip}/${split("/", var.proxy_subnet_cidr)[1]}", 0) == cidrhost(var.proxy_subnet_cidr, 0), false)])
    error_message = "Every proxy_vm_private_ips entry must be an IPv4 address inside proxy_subnet_cidr."
  }
}

variable "on_prem_endpoints" {
  description = "On-premises destinations, keyed by a short name. Each gets a load balancer frontend on frontend_ip, a Private Link Service with its NAT IP on pls_nat_ip, and an HAProxy listener on listen_port that forwards to target_fqdn:target_port. domain_name is the name serverless compute uses to reach the destination."
  type = map(object({
    frontend_ip = string
    pls_nat_ip  = string
    listen_port = number
    target_fqdn = string
    target_port = number
    domain_name = string
  }))

  validation {
    condition     = alltrue([for key in keys(var.on_prem_endpoints) : can(regex("^[a-z0-9_-]+$", key))])
    error_message = "on_prem_endpoints keys must contain only lowercase letters, digits, hyphens and underscores."
  }

  validation {
    condition = alltrue([
      for endpoint in values(var.on_prem_endpoints) :
      endpoint.listen_port >= 1 && endpoint.listen_port <= 65535 &&
      endpoint.target_port >= 1 && endpoint.target_port <= 65535
    ])
    error_message = "All endpoint ports must be between 1 and 65535."
  }

  validation {
    condition = alltrue(flatten([
      for endpoint in values(var.on_prem_endpoints) : [
        for ip in [endpoint.frontend_ip, endpoint.pls_nat_ip] :
        try(can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) && cidrhost("${ip}/${split("/", var.proxy_subnet_cidr)[1]}", 0) == cidrhost(var.proxy_subnet_cidr, 0), false)
      ]
    ]))
    error_message = "Every frontend_ip and pls_nat_ip must be an IPv4 address inside proxy_subnet_cidr."
  }

  validation {
    condition = length(distinct(concat(
      var.proxy_vm_private_ips,
      flatten([for endpoint in values(var.on_prem_endpoints) : [endpoint.frontend_ip, endpoint.pls_nat_ip]])
    ))) == length(var.proxy_vm_private_ips) + 2 * length(var.on_prem_endpoints)
    error_message = "Every frontend_ip, pls_nat_ip and proxy_vm_private_ips address must be different."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Private Link Service access
# ----------------------------------------------------------------------------------------------------------------------

variable "allow_all_subscriptions_pls_visibility" {
  description = "Allow any subscription that knows a Private Link Service alias to request a connection. Requests still require approval unless auto-approved. Explicit pls_visibility_subscription_ids are preferred."
  type        = bool
  default     = false
}

variable "pls_visibility_subscription_ids" {
  description = "Subscriptions allowed to discover the Private Link Services. Required unless allow_all_subscriptions_pls_visibility is true."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.pls_visibility_subscription_ids : can(regex("(?i)^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$", id))])
    error_message = "Every pls_visibility_subscription_ids entry must be a subscription GUID."
  }
}

variable "pls_auto_approval_subscription_ids" {
  description = "Subscriptions whose private endpoint connections to the Private Link Services are approved automatically. Must be a subset of pls_visibility_subscription_ids. An empty list means every connection is approved manually."
  type        = list(string)
  default     = []

  validation {
    condition = length(setsubtract(
      toset(var.pls_auto_approval_subscription_ids),
      toset(var.pls_visibility_subscription_ids)
    )) == 0 || var.allow_all_subscriptions_pls_visibility
    error_message = "Auto-approval subscriptions must be contained in the visibility list unless all-subscription visibility is explicitly enabled."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Databricks workspace
# ----------------------------------------------------------------------------------------------------------------------

variable "workspace_root_storage_account_name" {
  description = "Globally unique name of the root (DBFS) storage account Databricks creates in the managed resource group. Set when the workspace is created."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.workspace_root_storage_account_name))
    error_message = "workspace_root_storage_account_name must be 3-24 lowercase alphanumeric characters."
  }

  validation {
    condition     = var.workspace_root_storage_account_name != var.data_storage_account_name
    error_message = "workspace_root_storage_account_name must differ from data_storage_account_name."
  }
}

variable "workspace_public_network_access_enabled" {
  description = "Allow users, Power BI and GitHub to reach the workspace front end from public networks. Classic compute has no public IPs either way."
  type        = bool
  default     = true
}

variable "workspace_default_storage_firewall_enabled" {
  description = "Firewall the Databricks-managed root storage account. When true, the root Access Connector is created and attached to the workspace."
  type        = bool
  default     = false
}

variable "workspace_infrastructure_encryption_enabled" {
  description = "Enable a second layer of infrastructure encryption on the root storage account. Set when the workspace is created."
  type        = bool
  default     = true
}

# ----------------------------------------------------------------------------------------------------------------------
# Serverless egress
# The Databricks network policy is the only place an outbound allow list can be expressed by domain name.
# It covers serverless compute; classic compute leaves through the NAT Gateway and is governed by the route tables, the NSG rules and the firewall.
# ----------------------------------------------------------------------------------------------------------------------

variable "create_serverless_network_policy" {
  description = "Create the Databricks network policy for this environment and attach it to the workspace. Leave it false to keep the account default policy."
  type        = bool
  default     = true
}

variable "attach_serverless_network_policy" {
  description = "Point the workspace at this environment's network policy. Set it to false, and apply, before removing the policy or destroying the environment: Azure Databricks refuses to delete a policy a running workspace still refers to."
  type        = bool
  default     = true
}

variable "serverless_egress_restriction_mode" {
  description = "FULL_ACCESS lets serverless compute reach any internet destination. RESTRICTED_ACCESS limits it to serverless_allowed_internet_destinations."
  type        = string
  default     = "RESTRICTED_ACCESS"

  validation {
    condition     = contains(["FULL_ACCESS", "RESTRICTED_ACCESS"], var.serverless_egress_restriction_mode)
    error_message = "serverless_egress_restriction_mode must be FULL_ACCESS or RESTRICTED_ACCESS."
  }
}

variable "serverless_egress_enforcement_mode" {
  description = "ENFORCED blocks destinations outside the allow list. DRY_RUN allows them and records them instead, so the list can be validated before it is enforced."
  type        = string
  default     = "ENFORCED"

  validation {
    condition     = contains(["ENFORCED", "DRY_RUN"], var.serverless_egress_enforcement_mode)
    error_message = "serverless_egress_enforcement_mode must be ENFORCED or DRY_RUN."
  }
}

variable "serverless_allowed_internet_destinations" {
  description = "Domain names serverless compute may reach on the internet. The data storage account and the on-premises destinations are reached through the private endpoint rules of the Network Connectivity Configuration and need no entry here."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for destination in var.serverless_allowed_internet_destinations :
      can(regex("^[a-z0-9.*-]+$", lower(destination))) && strcontains(destination, ".") && !strcontains(destination, "//")
    ])
    error_message = "Every serverless_allowed_internet_destinations entry must be a domain name such as api.example.com or *.example.com, with no scheme, port or path."
  }

  validation {
    condition     = !var.create_serverless_network_policy || var.serverless_egress_restriction_mode == "FULL_ACCESS" || length(var.serverless_allowed_internet_destinations) > 0
    error_message = "serverless_allowed_internet_destinations must list at least one domain name when serverless_egress_restriction_mode is RESTRICTED_ACCESS."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Operations
# ----------------------------------------------------------------------------------------------------------------------

variable "log_analytics_retention_days" {
  description = "Retention period of the Log Analytics workspace, in days."
  type        = number
  default     = 90

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "log_analytics_retention_days must be between 30 and 730."
  }
}

variable "enable_diagnostics" {
  description = "Send diagnostic logs and metrics from the workspace, data storage account, load balancer and NAT Gateway to Log Analytics."
  type        = bool
  default     = true
}

variable "enable_alerts" {
  description = "Create the platform alerts on the HAProxy tier, NAT Gateway and data storage account. Each notifies the action group when alert_email_receivers creates one."
  type        = bool
  default     = true
}

variable "alert_email_receivers" {
  description = "Email receivers on the platform action group, as a map of receiver name to email address. An empty map creates no action group."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for address in values(var.alert_email_receivers) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", address))])
    error_message = "Every alert_email_receivers value must be an email address."
  }
}
