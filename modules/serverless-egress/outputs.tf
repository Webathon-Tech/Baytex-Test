# ----------------------------------------------------------------------------------------------------------------------
# Network policy
# ----------------------------------------------------------------------------------------------------------------------

output "network_policy_id" {
  description = "ID of the network policy attached to the workspace."
  value       = databricks_account_network_policy.this.network_policy_id
}

output "restriction_mode" {
  description = "Restriction mode the policy applies to serverless internet egress."
  value       = var.restriction_mode
}

output "enforcement_mode" {
  description = "Whether the policy blocks destinations outside the allow list or only records them."
  value       = var.enforcement_mode
}

output "allowed_internet_destinations" {
  description = "Domain names serverless compute may reach on the internet, sorted."
  value       = sort(tolist(var.allowed_internet_destinations))
}
