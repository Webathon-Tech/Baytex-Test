# ----------------------------------------------------------------------------------------------------------------------
# General
# ----------------------------------------------------------------------------------------------------------------------

variable "location" {
  description = "Azure region for every resource in this module."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the spoke network resources."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used in the names of the NSGs, NAT Gateway, route tables and peerings."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource that supports them."
  type        = map(string)
}

# ----------------------------------------------------------------------------------------------------------------------
# Virtual network and subnets
# ----------------------------------------------------------------------------------------------------------------------

variable "vnet_name" {
  description = "Name of the spoke VNet."
  type        = string
}

variable "vnet_cidr" {
  description = "Address space of the spoke VNet."
  type        = string
}

variable "dns_servers" {
  description = "DNS servers assigned to the VNet."
  type        = list(string)
}

variable "databricks_host_subnet_name" {
  description = "Name of the Databricks host (public) subnet."
  type        = string
}

variable "databricks_host_subnet_cidr" {
  description = "Address prefix of the Databricks host (public) subnet."
  type        = string
}

variable "databricks_container_subnet_name" {
  description = "Name of the Databricks container (private) subnet."
  type        = string
}

variable "databricks_container_subnet_cidr" {
  description = "Address prefix of the Databricks container (private) subnet."
  type        = string
}

variable "private_endpoint_subnet_name" {
  description = "Name of the subnet that holds the storage private endpoints."
  type        = string
}

variable "private_endpoint_subnet_cidr" {
  description = "Address prefix of the private endpoint subnet."
  type        = string
}

variable "proxy_subnet_name" {
  description = "Name of the subnet that holds the HAProxy VMs, load balancer frontends and Private Link Service NAT IPs."
  type        = string
}

variable "proxy_subnet_cidr" {
  description = "Address prefix of the proxy subnet."
  type        = string
}

# ----------------------------------------------------------------------------------------------------------------------
# Routing and hub peering
# ----------------------------------------------------------------------------------------------------------------------

variable "cisco_firewall_private_ip" {
  description = "Private IP of the hub firewall, used as the next hop by both route tables."
  type        = string
}

variable "firewall_routes" {
  description = "Prefixes the Databricks subnets send to the firewall, keyed by route name. The proxy and private endpoint subnets send all traffic to the firewall regardless of this map."
  type = map(object({
    address_prefix = string
  }))
}

variable "hub_vnet_id" {
  description = "Resource ID of the hub VNet. Required when either peering flag is true."
  type        = string
  default     = null
}

variable "create_spoke_to_hub_peering" {
  description = "Create the spoke-side peering, from the spoke VNet to the hub VNet."
  type        = bool
  default     = false
}

variable "create_hub_to_spoke_peering" {
  description = "Create the hub-side peering, from the hub VNet to the spoke VNet, as a child resource of hub_vnet_id."
  type        = bool
  default     = false
}

# ----------------------------------------------------------------------------------------------------------------------
# Network security group rules
# ----------------------------------------------------------------------------------------------------------------------

variable "databricks_nsg_rules" {
  description = "Rules added to both Databricks subnet NSGs, keyed by rule name. Azure Databricks maintains its own rules on these NSGs, so these priorities start at 1000."
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

  validation {
    condition     = alltrue([for name in keys(var.databricks_nsg_rules) : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,78}[A-Za-z0-9_]$", name))])
    error_message = "Every databricks_nsg_rules key must be a valid network security rule name of letters, digits, periods, underscores and hyphens."
  }

  validation {
    condition     = alltrue([for rule in values(var.databricks_nsg_rules) : rule.priority >= 1000 && rule.priority <= 4096])
    error_message = "Every databricks_nsg_rules priority must be between 1000 and 4096, so the rules Azure Databricks maintains on these NSGs keep precedence."
  }

  validation {
    condition     = length(distinct([for rule in values(var.databricks_nsg_rules) : "${rule.direction}-${rule.priority}"])) == length(var.databricks_nsg_rules)
    error_message = "Every databricks_nsg_rules priority must be unique within its direction."
  }

  validation {
    condition     = alltrue([for rule in values(var.databricks_nsg_rules) : contains(["Inbound", "Outbound"], rule.direction) && contains(["Allow", "Deny"], rule.access) && contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], rule.protocol)])
    error_message = "Every databricks_nsg_rules entry must set direction to Inbound or Outbound, access to Allow or Deny, and protocol to Tcp, Udp, Icmp, Esp, Ah or *."
  }

  validation {
    condition     = alltrue([for rule in values(var.databricks_nsg_rules) : (rule.destination_address_prefix != null) != (rule.destination_address_prefixes != null)])
    error_message = "Every databricks_nsg_rules entry must set exactly one of destination_address_prefix and destination_address_prefixes."
  }

  # Azure accepts "*" only in the singular parameter, which this module uses whenever a list holds a single entry.
  validation {
    condition = alltrue(flatten([
      for rule in values(var.databricks_nsg_rules) : [
        for list in [rule.source_port_ranges, rule.destination_port_ranges, rule.source_address_prefixes, rule.destination_address_prefixes] :
        list == null || length(list) < 2 || !contains(list, "*")
      ]
    ]))
    error_message = "A databricks_nsg_rules entry that lists two or more ports or address prefixes must not include \"*\", because Azure rejects it there. Use a single entry of \"*\" on its own instead."
  }
}

variable "proxy_nsg_rules" {
  description = "Rules added to the proxy NSG, keyed by rule name, alongside the health probe, Private Link Service and SSH rules this module creates. Priorities start at 1000."
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

  validation {
    condition     = alltrue([for name in keys(var.proxy_nsg_rules) : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,78}[A-Za-z0-9_]$", name))])
    error_message = "Every proxy_nsg_rules key must be a valid network security rule name of letters, digits, periods, underscores and hyphens."
  }

  validation {
    condition     = alltrue([for rule in values(var.proxy_nsg_rules) : rule.priority >= 1000 && rule.priority <= 4096])
    error_message = "Every proxy_nsg_rules priority must be between 1000 and 4096, so the rules this module creates keep precedence."
  }

  validation {
    condition     = length(distinct([for rule in values(var.proxy_nsg_rules) : "${rule.direction}-${rule.priority}"])) == length(var.proxy_nsg_rules)
    error_message = "Every proxy_nsg_rules priority must be unique within its direction."
  }

  validation {
    condition     = alltrue([for rule in values(var.proxy_nsg_rules) : contains(["Inbound", "Outbound"], rule.direction) && contains(["Allow", "Deny"], rule.access) && contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], rule.protocol)])
    error_message = "Every proxy_nsg_rules entry must set direction to Inbound or Outbound, access to Allow or Deny, and protocol to Tcp, Udp, Icmp, Esp, Ah or *."
  }

  validation {
    condition     = alltrue([for rule in values(var.proxy_nsg_rules) : (rule.destination_address_prefix != null) != (rule.destination_address_prefixes != null)])
    error_message = "Every proxy_nsg_rules entry must set exactly one of destination_address_prefix and destination_address_prefixes."
  }

  # Azure accepts "*" only in the singular parameter, which this module uses whenever a list holds a single entry.
  validation {
    condition = alltrue(flatten([
      for rule in values(var.proxy_nsg_rules) : [
        for list in [rule.source_port_ranges, rule.destination_port_ranges, rule.source_address_prefixes, rule.destination_address_prefixes] :
        list == null || length(list) < 2 || !contains(list, "*")
      ]
    ]))
    error_message = "A proxy_nsg_rules entry that lists two or more ports or address prefixes must not include \"*\", because Azure rejects it there. Use a single entry of \"*\" on its own instead."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Proxy subnet access
# ----------------------------------------------------------------------------------------------------------------------

variable "admin_ssh_source_cidrs" {
  description = "CIDRs allowed to SSH to the HAProxy VMs. An empty list creates no SSH rule."
  type        = list(string)
  default     = []
}

variable "proxy_listener_ports" {
  description = "TCP ports the HAProxy listeners accept Private Link Service traffic on."
  type        = set(number)
}
