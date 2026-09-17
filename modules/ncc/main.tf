# ----------------------------------------------------------------------------------------------------------------------
# Network Connectivity Configuration module
# Gives Databricks serverless compute private access to the data storage account and to each on-premises destination behind a Private Link Service, and limits which internet destinations it may reach.
# These are Databricks account-level resources, so the module uses the account-level databricks provider.
# ----------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# NCC and workspace binding
# ----------------------------------------------------------------------------------------------------------------------

# One NCC per environment, because a workspace can be bound to only one NCC.
resource "databricks_mws_network_connectivity_config" "this" {
  name   = var.name
  region = var.region
}

resource "databricks_mws_ncc_binding" "workspace" {
  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  workspace_id                   = var.workspace_id
}

# ----------------------------------------------------------------------------------------------------------------------
# Private endpoint rules
# ----------------------------------------------------------------------------------------------------------------------

# Each rule makes Databricks create a private endpoint from its serverless network to the target resource.
# The endpoint connection arrives as Pending on the target and must be approved before serverless compute can use it.

# Data storage account: one rule for blob and one for dfs.
resource "databricks_mws_ncc_private_endpoint_rule" "storage_blob" {
  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  resource_id                    = var.storage_account_id
  group_id                       = "blob"
}

resource "databricks_mws_ncc_private_endpoint_rule" "storage_dfs" {
  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  resource_id                    = var.storage_account_id
  group_id                       = "dfs"
}

# On-premises destinations: one rule per Private Link Service.
# domain_names makes serverless compute resolve each destination's FQDN to its private endpoint.
resource "databricks_mws_ncc_private_endpoint_rule" "on_prem" {
  for_each = var.private_link_services

  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  resource_id                    = each.value.id
  domain_names                   = each.value.domain_names
}

# ----------------------------------------------------------------------------------------------------------------------
# Serverless egress policy
# ----------------------------------------------------------------------------------------------------------------------

# The policy governs internet egress from serverless compute only.
# It does not apply to classic compute, which leaves through the NAT Gateway and the route tables in the spoke network module.
# It also does not apply to the data storage account or the on-premises destinations, which serverless compute reaches through the private endpoint rules above rather than over the internet.
#
# The allow list holds domain names, because that is what the policy matches on.
# Destinations that are only reachable by address, and destinations for classic compute, are allowed on the firewall and in the network security group rules instead.
#
# The account is set rather than left for the provider to fill in.
# It is a value the policy cannot be changed without replacing, and a policy that is still attached to a workspace cannot be deleted, so leaving it unset would make the allow list impossible to edit after the first apply.
resource "databricks_account_network_policy" "this" {
  count = var.create_network_policy ? 1 : 0

  account_id        = var.account_id
  network_policy_id = var.network_policy_id

  egress = {
    network_access = {
      restriction_mode = var.egress_restriction_mode

      # DNS_NAME is the only destination type the policy supports; address ranges are not accepted here.
      allowed_internet_destinations = [
        for destination in sort(tolist(var.allowed_internet_destinations)) : {
          destination               = destination
          internet_destination_type = "DNS_NAME"
        }
      ]

      policy_enforcement = {
        enforcement_mode = var.egress_enforcement_mode
      }
    }
  }
}

# A workspace uses one network policy, so each environment attaches its own.
# The attachment always exists and is repointed rather than removed, because deleting it leaves the workspace on the
# policy it already had. Azure Databricks refuses to delete a policy that a running workspace still refers to, so the
# workspace is moved to the account's own policy first, which frees this one to be deleted.
resource "databricks_workspace_network_option" "this" {
  workspace_id      = var.workspace_id
  network_policy_id = var.attach_network_policy ? databricks_account_network_policy.this[0].network_policy_id : var.account_default_network_policy_id
}

# State that holds the attachment at the indexed address is carried over to the unindexed one, so the attachment is kept rather than replaced.
moved {
  from = databricks_workspace_network_option.this[0]
  to   = databricks_workspace_network_option.this
}
