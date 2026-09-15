# ----------------------------------------------------------------------------------------------------------------------
# Workspace
# ----------------------------------------------------------------------------------------------------------------------

variable "workspace_id" {
  description = "Numeric ID of the Databricks workspace the network policy is attached to."
  type        = number
}

variable "account_id" {
  description = "Azure Databricks account that owns the network policy."
  type        = string
}

variable "network_policy_id" {
  description = "Identifier of the network policy, unique within the Databricks account. It is chosen rather than generated, so the policy keeps the same identifier when it is recreated."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$", var.network_policy_id))
    error_message = "network_policy_id must be 3 to 64 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Egress policy
# ----------------------------------------------------------------------------------------------------------------------

variable "restriction_mode" {
  description = "FULL_ACCESS lets serverless compute reach any internet destination. RESTRICTED_ACCESS limits it to allowed_internet_destinations."
  type        = string
  default     = "RESTRICTED_ACCESS"

  validation {
    condition     = contains(["FULL_ACCESS", "RESTRICTED_ACCESS"], var.restriction_mode)
    error_message = "restriction_mode must be FULL_ACCESS or RESTRICTED_ACCESS."
  }
}

variable "enforcement_mode" {
  description = "ENFORCED blocks destinations outside the allow list. DRY_RUN allows them and records them instead, so the list can be validated before it is enforced."
  type        = string
  default     = "ENFORCED"

  validation {
    condition     = contains(["ENFORCED", "DRY_RUN"], var.enforcement_mode)
    error_message = "enforcement_mode must be ENFORCED or DRY_RUN."
  }
}

variable "allowed_internet_destinations" {
  description = "Fully qualified domain names serverless compute may reach on the internet. Applies only when restriction_mode is RESTRICTED_ACCESS."
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
    condition     = var.restriction_mode == "FULL_ACCESS" || length(var.allowed_internet_destinations) > 0
    error_message = "allowed_internet_destinations must list at least one domain name when restriction_mode is RESTRICTED_ACCESS."
  }
}
