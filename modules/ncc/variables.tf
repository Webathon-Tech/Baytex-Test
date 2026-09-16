# ----------------------------------------------------------------------------------------------------------------------
# NCC
# ----------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Name of the Network Connectivity Configuration."
  type        = string
}

variable "region" {
  description = "Azure region of the NCC. Must match the workspace region."
  type        = string
}

variable "workspace_id" {
  description = "Numeric ID of the Databricks workspace the NCC is bound to."
  type        = number
}

# ----------------------------------------------------------------------------------------------------------------------
# Private endpoint rule targets
# ----------------------------------------------------------------------------------------------------------------------

variable "storage_account_id" {
  description = "Resource ID of the data storage account that receives the blob and dfs rules."
  type        = string
}

variable "private_link_services" {
  description = "Private Link Service ID and domain names of each on-premises destination, keyed by destination name."
  type = map(object({
    id           = string
    domain_names = list(string)
  }))
}

# ----------------------------------------------------------------------------------------------------------------------
# Serverless egress policy
# The network policy is an account-level Databricks resource attached to the same workspace as the NCC, so it lives here.
# ----------------------------------------------------------------------------------------------------------------------

variable "account_id" {
  description = "Azure Databricks account that owns the network policy."
  type        = string
}

variable "create_network_policy" {
  description = "Create the network policy for this environment. Leave it false to keep the account default policy."
  type        = bool
  default     = true
}

variable "attach_network_policy" {
  description = "Point the workspace at this environment's network policy. False moves it to the account default policy, which is how the policy is released before it can be deleted."
  type        = bool
  default     = true

  # Removing the policy while the workspace still points at it cannot succeed, so the combination is rejected rather than
  # attempted: Azure Databricks refuses to delete a policy a running workspace refers to, and Terraform does not
  # reliably detach it before deleting it.
  validation {
    condition     = var.create_network_policy || !var.attach_network_policy
    error_message = "Detach the workspace first: apply with attach_network_policy = false, and only then remove the policy with create_network_policy = false."
  }
}

variable "network_policy_id" {
  description = "Identifier of the network policy, unique within the Databricks account. It is chosen rather than generated, so the policy keeps the same identifier when it is recreated."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$", var.network_policy_id))
    error_message = "network_policy_id must be 3 to 64 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "account_default_network_policy_id" {
  description = "Policy the workspace is moved to when create_network_policy is false. Every Databricks account has one, named default-policy, which applies no restriction."
  type        = string
  default     = "default-policy"
}

variable "egress_restriction_mode" {
  description = "FULL_ACCESS lets serverless compute reach any internet destination. RESTRICTED_ACCESS limits it to allowed_internet_destinations."
  type        = string
  default     = "RESTRICTED_ACCESS"

  validation {
    condition     = contains(["FULL_ACCESS", "RESTRICTED_ACCESS"], var.egress_restriction_mode)
    error_message = "egress_restriction_mode must be FULL_ACCESS or RESTRICTED_ACCESS."
  }
}

variable "egress_enforcement_mode" {
  description = "ENFORCED blocks destinations outside the allow list. DRY_RUN allows them and records them instead, so the list can be validated before it is enforced."
  type        = string
  default     = "ENFORCED"

  validation {
    condition     = contains(["ENFORCED", "DRY_RUN"], var.egress_enforcement_mode)
    error_message = "egress_enforcement_mode must be ENFORCED or DRY_RUN."
  }
}

variable "allowed_internet_destinations" {
  description = "Domain names serverless compute may reach on the internet. The data storage account and the on-premises destinations are reached through the private endpoint rules above and need no entry here."
  type        = set(string)
  default     = []

  # A destination is a bare domain name: the policy matches on the name alone, so a scheme, port or path would never match.
  validation {
    condition = alltrue([
      for destination in var.allowed_internet_destinations :
      can(regex("^[a-z0-9.*-]+$", lower(destination))) && strcontains(destination, ".") && !strcontains(destination, "//")
    ])
    error_message = "Every allowed_internet_destinations entry must be a domain name such as api.example.com or *.example.com, with no scheme, port or path."
  }

  validation {
    condition     = !var.create_network_policy || var.egress_restriction_mode == "FULL_ACCESS" || length(var.allowed_internet_destinations) > 0
    error_message = "allowed_internet_destinations must list at least one domain name when egress_restriction_mode is RESTRICTED_ACCESS."
  }
}
