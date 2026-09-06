variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "name_prefix" { type = string }
variable "proxy_subnet_id" { type = string }
variable "proxy_vm_size" { type = string }
variable "proxy_vm_private_ips" { type = list(string) }
variable "admin_username" { type = string }
variable "ssh_public_key" { type = string }
variable "dns_servers" { type = list(string) }

variable "endpoints" {
  description = "One load-balancer frontend and Private Link Service per approved on-premises destination."
  type = map(object({
    frontend_ip = string
    pls_nat_ip  = string
    listen_port = number
    target_fqdn = string
    target_port = number
    domain_name = string
  }))
}

variable "allow_all_subscriptions_visibility" {
  type        = bool
  default     = false
  description = "Allow anyone with the PLS alias to request a connection. Requests still require approval unless auto-approved. Use only as an explicit exception."
}

variable "visibility_subscription_ids" {
  description = "Subscriptions that can discover the Private Link Services. Must be non-empty unless all-subscription visibility is explicitly enabled."
  type        = list(string)
  default     = []
}

variable "auto_approval_subscription_ids" {
  description = "Subscriptions whose requests are automatically approved. Prefer manual approval for the first deployment."
  type        = list(string)
  default     = []
}

variable "tags" { type = map(string) }
