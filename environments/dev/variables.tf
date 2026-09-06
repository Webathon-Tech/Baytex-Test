variable "tenant_id" {
  type        = string
  description = "Baytex Microsoft Entra tenant ID."
}

variable "subscription_id" {
  type        = string
  description = "DEV Azure subscription ID."
}

variable "databricks_account_id" {
  type        = string
  description = "Existing Baytex Azure Databricks account ID."
}

variable "existing_metastore_id" {
  type        = string
  description = "Existing regional Unity Catalog metastore ID. Baytex BI owns the assignment and Unity Catalog objects."
}

variable "location" {
  type    = string
  default = "canadacentral"
}

variable "organization" {
  type    = string
  default = "bte"
}

variable "workload" {
  type    = string
  default = "dbx"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region_short" {
  type    = string
  default = "cnc"
}

variable "instance" {
  type    = string
  default = "001"
}

variable "owner" {
  type    = string
  default = "Baytex Infrastructure"
}

variable "cost_centre" {
  type    = string
  default = "TO-BE-CONFIRMED"
}

variable "data_classification" {
  type    = string
  default = "Internal"
}

variable "additional_tags" {
  type    = map(string)
  default = {}
}

variable "vnet_cidr" { type = string }
variable "databricks_host_subnet_cidr" { type = string }
variable "databricks_container_subnet_cidr" { type = string }
variable "private_endpoint_subnet_cidr" { type = string }
variable "proxy_subnet_cidr" { type = string }

variable "dns_servers" {
  type        = list(string)
  description = "Corporate DNS servers used by the DEV VNet and HAProxy resolver."
}

variable "hub_subscription_id" { type = string }
variable "hub_resource_group_name" { type = string }
variable "hub_vnet_name" { type = string }
variable "hub_vnet_id" { type = string }
variable "cisco_firewall_private_ip" { type = string }

variable "create_spoke_to_hub_peering" {
  type        = bool
  default     = true
  description = "Create only the DEV spoke-to-existing-hub peering. The hub-side peering remains Baytex-owned."
}

variable "on_prem_routes" {
  type = map(object({
    address_prefix = string
  }))
  description = "Approved on-premises CIDRs routed to the Cisco firewall."
}

variable "admin_ssh_source_cidrs" {
  type    = list(string)
  default = []
}

variable "ssh_public_key" {
  type        = string
  description = "Approved SSH public key for the HAProxy VMs."
}

variable "proxy_vm_size" {
  type    = string
  default = "Standard_D4s_v3"
}

variable "proxy_vm_private_ips" {
  type = list(string)

  validation {
    condition     = length(var.proxy_vm_private_ips) == 2
    error_message = "Exactly two HAProxy VM private IPs are required."
  }
}

variable "on_prem_endpoints" {
  type = map(object({
    frontend_ip = string
    pls_nat_ip  = string
    listen_port = number
    target_fqdn = string
    target_port = number
    domain_name = string
  }))

  validation {
    condition = alltrue([
      for endpoint in values(var.on_prem_endpoints) :
      endpoint.listen_port >= 1 && endpoint.listen_port <= 65535 &&
      endpoint.target_port >= 1 && endpoint.target_port <= 65535
    ])
    error_message = "All endpoint ports must be between 1 and 65535."
  }
}

variable "allow_all_subscriptions_pls_visibility" {
  type        = bool
  default     = false
  description = "Explicit exception that allows any subscription with the PLS alias to request a connection. Requests still require approval unless auto-approved. Prefer explicit visibility_subscription_ids."
}

variable "pls_visibility_subscription_ids" {
  type        = list(string)
  default     = []
  description = "Subscription IDs allowed to discover each DEV Private Link Service. Required unless allow_all_subscriptions_pls_visibility is true."
}

variable "pls_auto_approval_subscription_ids" {
  type        = list(string)
  default     = []
  description = "Subset of visibility_subscription_ids whose Private Endpoint requests are automatically approved. Manual approval is safer for initial deployment."

  validation {
    condition = length(setsubtract(
      toset(var.pls_auto_approval_subscription_ids),
      toset(var.pls_visibility_subscription_ids)
    )) == 0 || var.allow_all_subscriptions_pls_visibility
    error_message = "Auto-approval subscriptions must be contained in the visibility list unless all-subscription visibility is explicitly enabled."
  }
}

variable "data_storage_account_name" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.data_storage_account_name))
    error_message = "data_storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "workspace_root_storage_account_name" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.workspace_root_storage_account_name))
    error_message = "workspace_root_storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "data_containers" {
  type    = set(string)
  default = ["managed", "external", "landing", "checkpoints"]
}

variable "blob_private_dns_zone_ids" {
  type    = set(string)
  default = []
}

variable "dfs_private_dns_zone_ids" {
  type    = set(string)
  default = []
}

variable "workspace_public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Initial compatibility setting for user/Power BI/GitHub access. Tighten only after private front-end connectivity is designed and tested."
}

variable "workspace_default_storage_firewall_enabled" {
  type        = bool
  default     = true
  description = "Disallow public access to the Databricks-managed default storage account. Uses the environment Access Connector."
}

variable "workspace_infrastructure_encryption_enabled" {
  type        = bool
  default     = true
  description = "Enable the second layer of infrastructure encryption on the Databricks-managed storage account. Creation-time setting."
}

variable "default_catalog_initial_name" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional creation-time default catalog name. Baytex BI still owns metastore assignment, catalogs, bindings, groups, and grants."
}

variable "log_analytics_retention_days" {
  type    = number
  default = 90
}

variable "enable_diagnostics" {
  type    = bool
  default = true
}

variable "alert_email_receivers" {
  type        = map(string)
  default     = {}
  description = "Map of receiver name to email address."
}
