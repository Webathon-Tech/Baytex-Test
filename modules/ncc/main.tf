# ----------------------------------------------------------------------------------------------------------------------
# Network Connectivity Configuration module
# Gives Databricks serverless compute private access to the data storage account and to each on-premises destination behind a Private Link Service, and limits which internet destinations it may reach.
# Also registers the data storage account with Unity Catalog, through a storage credential and an external location, so catalogs can keep their managed storage there rather than in the workspace's default storage.
# The NCC and the network policy are Databricks account-level resources and use the account-level provider, the module's default.
# The storage credential and external location are Unity Catalog objects and use the databricks.workspace provider.
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

# ----------------------------------------------------------------------------------------------------------------------
# Unity Catalog storage credential and external location
# No catalog is created here: Baytex BI creates the catalogs and can place their managed storage in this location.
# ----------------------------------------------------------------------------------------------------------------------

# Everything in this section is created through the workspace, so the workspace must exist first.
# The resources need no depends_on for that: they use the databricks.workspace provider, whose host comes from the workspace, so Terraform creates them after the workspace and destroys them before it.
# A data source is different: Terraform reads it while planning, so a read through a workspace that does not exist yet fails the plan unless something defers it.

locals {
  # The last segment of the storage account resource ID.
  storage_account_name = element(split("/", var.storage_account_id), 8)
}

# The metastore the workspace is assigned to, read through the workspace.
# The read depends on the NCC binding, which exists only once the workspace does: while the workspace is new or being replaced, the binding is still to be created, so the read waits for the apply instead of failing the plan.
data "databricks_current_metastore" "this" {
  count    = var.create_unity_catalog_external_location ? 1 : 0
  provider = databricks.workspace

  depends_on = [databricks_mws_ncc_binding.workspace]
}

# Every environment's workspace is assigned to the same metastore, so both objects are isolated: they can be used only from workspaces they are bound to.
# The provider binds the workspace it calls, which is this environment's, when it sets the isolation mode.
resource "databricks_storage_credential" "data" {
  count    = var.create_unity_catalog_external_location ? 1 : 0
  provider = databricks.workspace

  name           = var.storage_credential_name
  comment        = "Backed by the data Access Connector of storage account ${local.storage_account_name}. Managed by the platform Terraform."
  isolation_mode = "ISOLATION_MODE_ISOLATED"

  azure_managed_identity {
    access_connector_id = var.access_connector_id
  }

  lifecycle {
    # Azure Databricks assigns a new workspace to the regional metastore as it creates it.
    # This confirms the assignment happened, to the expected metastore, before anything is created in it.
    # While the read waits for the apply its metastore_info block is empty, so try() falls back to the id, which is unknown until then, and the check waits too.
    precondition {
      condition     = lower(try(data.databricks_current_metastore.this[0].metastore_info[0].metastore_id, data.databricks_current_metastore.this[0].id)) == lower(var.metastore_id)
      error_message = "Workspace ${var.workspace_id} is assigned to metastore ${try(data.databricks_current_metastore.this[0].metastore_info[0].metastore_id, "(none)")}, not to ${var.metastore_id} (existing_metastore_id). The storage credential and external location are created only in the expected metastore."
    }
  }
}

# Validation is skipped when the location is saved.
# Public network access to the storage account is disabled, so Databricks reaches it through the storage private endpoint rules above, which the deploy pipeline approves only after the apply.
# On a new environment those endpoints, and the Access Connector's new role assignments, may not be ready in time, and a failed check would stop the first apply.
# Access is confirmed after the deployment instead, with Test connection on the location in Catalog Explorer.
#
# File events are turned off.
# They need Databricks to create an Event Grid subscription and a storage queue on the account, and the queue is not reachable while public network access is disabled.
resource "databricks_external_location" "data" {
  count    = var.create_unity_catalog_external_location ? 1 : 0
  provider = databricks.workspace

  name               = var.external_location_name
  url                = var.external_location_url
  credential_name    = databricks_storage_credential.data[0].name
  comment            = "Managed storage for catalogs and schemas, and external tables and volumes, in storage account ${local.storage_account_name}. Managed by the platform Terraform."
  isolation_mode     = "ISOLATION_MODE_ISOLATED"
  read_only          = false
  enable_file_events = false
  skip_validation    = true

  # A location that still holds a catalog's or a table's storage is not deleted with it.
  force_destroy = false
}

# One grant per principal. Each is authoritative for its principal only: a listed principal's privileges are exactly those in the map, and principals not listed, including those Baytex BI grants directly, are left alone.
resource "databricks_grant" "external_location" {
  provider = databricks.workspace
  for_each = var.create_unity_catalog_external_location ? var.external_location_grants : {}

  external_location = databricks_external_location.data[0].name
  principal         = each.key
  privileges        = each.value
}
