variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "vnet_name" { type = string }
variable "vnet_cidr" { type = string }
variable "dns_servers" { type = list(string) }
variable "databricks_host_subnet_name" { type = string }
variable "databricks_host_subnet_cidr" { type = string }
variable "databricks_container_subnet_name" { type = string }
variable "databricks_container_subnet_cidr" { type = string }
variable "private_endpoint_subnet_name" { type = string }
variable "private_endpoint_subnet_cidr" { type = string }
variable "proxy_subnet_name" { type = string }
variable "proxy_subnet_cidr" { type = string }
variable "cisco_firewall_private_ip" { type = string }

variable "on_prem_routes" {
  description = "Prefixes the Databricks subnets route to the Cisco firewall; the other subnets route everything there."
  type = map(object({
    address_prefix = string
  }))
}

variable "hub_vnet_id" {
  description = "Existing hub VNet resource ID. Only the spoke-to-hub peering is optionally created."
  type        = string
}

variable "create_spoke_to_hub_peering" {
  type        = bool
  default     = true
  description = "Create the local/spoke side of the peering. The hub side remains a Baytex-owned change."
}

variable "admin_ssh_source_cidrs" {
  description = "Approved CIDRs that may SSH to the HAProxy VMs. Leave empty until Baytex confirms Bastion/jump-host access."
  type        = list(string)
  default     = []
}

variable "proxy_listener_ports" {
  description = "TCP listener ports exposed by the internal load balancer/HAProxy tier."
  type        = set(number)
}

variable "tags" {
  type = map(string)
}
