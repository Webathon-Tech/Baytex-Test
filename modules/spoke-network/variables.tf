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

variable "on_prem_routes" {
  description = "Prefixes the Databricks subnets send to the firewall. The proxy and private endpoint subnets send all traffic to the firewall regardless of this map."
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
