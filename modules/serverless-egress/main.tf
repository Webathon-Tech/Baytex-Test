# ----------------------------------------------------------------------------------------------------------------------
# Serverless egress module
# Controls which internet destinations Databricks serverless compute may reach, and attaches that policy to the workspace.
# These are Databricks account-level resources, so the module uses the account-level databricks provider.
# ----------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# Network policy
# ----------------------------------------------------------------------------------------------------------------------

# The policy governs internet egress from serverless compute only.
# It does not apply to classic compute, which leaves through the NAT Gateway and the route tables in the spoke network module.
# It also does not apply to the data storage account or the on-premises destinations, which serverless compute reaches through the private endpoint rules of the Network Connectivity Configuration rather than the internet.
#
# The allow list holds domain names, because that is what the policy matches on.
# Destinations that are only reachable by address, and destinations for classic compute, are allowed on the firewall and in the network security group rules instead.
# The account is set rather than left for the provider to fill in.
# It is a value the policy cannot be changed without replacing, and a policy that is still attached to a workspace cannot be deleted, so leaving it unset would make the allow list impossible to edit after the first apply.
resource "databricks_account_network_policy" "this" {
  account_id        = var.account_id
  network_policy_id = var.network_policy_id

  egress = {
    network_access = {
      restriction_mode = var.restriction_mode

      # DNS_NAME is the only destination type the policy supports; address ranges are not accepted here.
      allowed_internet_destinations = [
        for destination in sort(tolist(var.allowed_internet_destinations)) : {
          destination               = destination
          internet_destination_type = "DNS_NAME"
        }
      ]

      policy_enforcement = {
        enforcement_mode = var.enforcement_mode
      }
    }
  }
}

# ----------------------------------------------------------------------------------------------------------------------
# Workspace attachment
# ----------------------------------------------------------------------------------------------------------------------

# A workspace uses one network policy, so each environment attaches its own.
resource "databricks_workspace_network_option" "this" {
  workspace_id      = var.workspace_id
  network_policy_id = databricks_account_network_policy.this.network_policy_id
}
