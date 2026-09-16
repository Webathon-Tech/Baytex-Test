# ----------------------------------------------------------------------------------------------------------------------
# General
# ----------------------------------------------------------------------------------------------------------------------

variable "location" {
  description = "Azure region for every resource in this module."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the HAProxy VMs, load balancer and Private Link Services."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used in the names of every resource in this module."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource that supports them."
  type        = map(string)
}

# ----------------------------------------------------------------------------------------------------------------------
# Virtual machines
# ----------------------------------------------------------------------------------------------------------------------

variable "proxy_subnet_id" {
  description = "Resource ID of the proxy subnet that holds the VMs, load balancer frontends and Private Link Service NAT IPs."
  type        = string
}

variable "proxy_vm_size" {
  description = "Azure VM size of both HAProxy VMs."
  type        = string
}

variable "proxy_vm_private_ips" {
  description = "Static private IPs of the two HAProxy VMs, in zone 1 and zone 2 order."
  type        = list(string)
}

variable "admin_username" {
  description = "Local administrator user name on the HAProxy VMs."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the administrator user. Password authentication is disabled."
  type        = string
}

variable "dns_servers" {
  description = "DNS servers the HAProxy resolver uses to look up each target_fqdn."
  type        = list(string)
}

# ----------------------------------------------------------------------------------------------------------------------
# Destinations
# ----------------------------------------------------------------------------------------------------------------------

variable "endpoints" {
  description = "One load balancer frontend and one Private Link Service per approved on-premises destination, keyed by a short destination name."
  type = map(object({
    frontend_ip = string
    pls_nat_ip  = string
    listen_port = number
    target_fqdn = string
    target_port = number
    domain_name = string
  }))
}

# ----------------------------------------------------------------------------------------------------------------------
# Private Link Service access
# ----------------------------------------------------------------------------------------------------------------------

variable "allow_all_subscriptions_visibility" {
  description = "Allow any subscription that knows a Private Link Service alias to request a connection. Requests still require approval unless auto-approved."
  type        = bool
  default     = false
}

variable "visibility_subscription_ids" {
  description = "Subscriptions that can discover the Private Link Services. Must be non-empty unless allow_all_subscriptions_visibility is true."
  type        = list(string)
  default     = []
}

variable "auto_approval_subscription_ids" {
  description = "Subscriptions whose private endpoint connections are approved automatically. Must be a subset of visibility_subscription_ids."
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------------------------------------------------------
# Monitoring
# ----------------------------------------------------------------------------------------------------------------------

variable "enable_health_probe_alert" {
  description = "Create a metric alert that is raised while fewer than all HAProxy VMs answer the load balancer health probe."
  type        = bool
  default     = false
}

variable "alert_action_group_ids" {
  description = "Action groups the health probe alert notifies. An empty list raises the alert in Azure Monitor without notifying anyone."
  type        = list(string)
  default     = []
}
