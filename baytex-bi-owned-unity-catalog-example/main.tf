# ----------------------------------------------------------------------------------------------------------------------
# Baytex BI Unity Catalog reference
# Attaches a platform workspace to the existing metastore and creates its storage credential, external locations, catalog, schemas, workspace bindings and grants.
# It uses its own Terraform state and is not called by the platform roots.
# ----------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# Metastore assignment
# ----------------------------------------------------------------------------------------------------------------------

resource "databricks_metastore_assignment" "dev" {
  provider = databricks.account

  metastore_id = var.metastore_id
  workspace_id = var.workspace_id
}

# ----------------------------------------------------------------------------------------------------------------------
# Storage credential and external locations
# ----------------------------------------------------------------------------------------------------------------------

# Backed by the data Access Connector the platform creates, which already holds Storage Blob Data Contributor on the data storage account.
resource "databricks_storage_credential" "dev" {
  provider = databricks.workspace

  name           = var.storage_credential_name
  owner          = var.storage_credential_owner
  comment        = "Baytex DEV storage credential using the environment Access Connector."
  isolation_mode = "ISOLATION_MODE_ISOLATED"

  azure_managed_identity {
    access_connector_id = var.access_connector_id
  }

  depends_on = [databricks_metastore_assignment.dev]
}

# Holds the managed storage of the catalog.
resource "databricks_external_location" "managed" {
  provider = databricks.workspace

  name            = var.managed_external_location_name
  url             = "abfss://${var.managed_container_name}@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.dev.name
  owner           = var.external_location_owner
  comment         = "Baytex DEV managed catalog storage location."
  isolation_mode  = "ISOLATION_MODE_ISOLATED"
  read_only       = false
  skip_validation = false
}

# General-purpose location for external tables and files.
resource "databricks_external_location" "external" {
  provider = databricks.workspace

  name            = var.external_location_name
  url             = "abfss://${var.external_container_name}@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.dev.name
  owner           = var.external_location_owner
  comment         = "Baytex DEV general-purpose external location."
  isolation_mode  = "ISOLATION_MODE_ISOLATED"
  read_only       = false
  skip_validation = false
}

# ----------------------------------------------------------------------------------------------------------------------
# Catalog and schemas
# ----------------------------------------------------------------------------------------------------------------------

# The catalog's managed storage root sits under the managed external location, as Unity Catalog requires.
resource "databricks_catalog" "dev" {
  provider = databricks.workspace

  name           = var.catalog_name
  storage_root   = "${databricks_external_location.managed.url}catalogs/${var.catalog_name}"
  owner          = var.catalog_owner
  comment        = "Baytex DEV environment-specific catalog."
  isolation_mode = "ISOLATED"
  force_destroy  = false
}

# A schema without its own owner is owned by the catalog owner.
resource "databricks_schema" "this" {
  provider = databricks.workspace
  for_each = var.schemas

  catalog_name = databricks_catalog.dev.name
  name         = each.key
  comment      = try(each.value.comment, null)
  owner        = coalesce(try(each.value.owner, null), var.catalog_owner)
}

# ----------------------------------------------------------------------------------------------------------------------
# Workspace bindings: this workspace
# ----------------------------------------------------------------------------------------------------------------------

# Isolated securables are usable only from workspaces they are bound to, so each one is bound to this workspace.
resource "databricks_workspace_binding" "catalog_current" {
  provider = databricks.workspace

  securable_name = databricks_catalog.dev.name
  securable_type = "catalog"
  workspace_id   = var.workspace_id
  binding_type   = "BINDING_TYPE_READ_WRITE"
}

resource "databricks_workspace_binding" "managed_external_location_current" {
  provider = databricks.workspace

  securable_name = databricks_external_location.managed.name
  securable_type = "external_location"
  workspace_id   = var.workspace_id
  binding_type   = "BINDING_TYPE_READ_WRITE"
}

resource "databricks_workspace_binding" "external_location_current" {
  provider = databricks.workspace

  securable_name = databricks_external_location.external.name
  securable_type = "external_location"
  workspace_id   = var.workspace_id
  binding_type   = "BINDING_TYPE_READ_WRITE"
}

resource "databricks_workspace_binding" "storage_credential_current" {
  provider = databricks.workspace

  securable_name = databricks_storage_credential.dev.name
  securable_type = "storage_credential"
  workspace_id   = var.workspace_id
  binding_type   = "BINDING_TYPE_READ_WRITE"
}

# ----------------------------------------------------------------------------------------------------------------------
# Workspace bindings: additional approved workspaces
# ----------------------------------------------------------------------------------------------------------------------

# Read-only bindings are supported only for catalogs; storage credentials and external locations are always bound read-write.
resource "databricks_workspace_binding" "catalog_additional" {
  provider = databricks.workspace
  for_each = var.additional_catalog_workspace_bindings

  securable_name = databricks_catalog.dev.name
  securable_type = "catalog"
  workspace_id   = each.value.workspace_id
  binding_type   = each.value.binding_type
}

resource "databricks_workspace_binding" "managed_external_location_additional" {
  provider = databricks.workspace
  for_each = var.additional_external_location_workspace_bindings

  securable_name = databricks_external_location.managed.name
  securable_type = "external_location"
  workspace_id   = each.value.workspace_id
  binding_type   = "BINDING_TYPE_READ_WRITE"
}

resource "databricks_workspace_binding" "external_location_additional" {
  provider = databricks.workspace
  for_each = var.additional_external_location_workspace_bindings

  securable_name = databricks_external_location.external.name
  securable_type = "external_location"
  workspace_id   = each.value.workspace_id
  binding_type   = "BINDING_TYPE_READ_WRITE"
}

resource "databricks_workspace_binding" "storage_credential_additional" {
  provider = databricks.workspace
  for_each = var.additional_storage_credential_workspace_bindings

  securable_name = databricks_storage_credential.dev.name
  securable_type = "storage_credential"
  workspace_id   = each.value.workspace_id
  binding_type   = "BINDING_TYPE_READ_WRITE"
}

# ----------------------------------------------------------------------------------------------------------------------
# Grants
# ----------------------------------------------------------------------------------------------------------------------

resource "databricks_grant" "catalog" {
  provider = databricks.workspace
  for_each = var.catalog_grants

  catalog    = databricks_catalog.dev.name
  principal  = each.key
  privileges = each.value
}

locals {
  # One entry per schema and principal pair, keyed "<schema>|<principal>".
  flattened_schema_grants = {
    for item in flatten([
      for schema_name, principals in var.schema_grants : [
        for principal, privileges in principals : {
          schema_name = schema_name
          principal   = principal
          privileges  = privileges
        }
      ]
    ]) : "${item.schema_name}|${item.principal}" => item
  }
}

resource "databricks_grant" "schema" {
  provider = databricks.workspace
  for_each = local.flattened_schema_grants

  schema     = "${databricks_catalog.dev.name}.${each.value.schema_name}"
  principal  = each.value.principal
  privileges = each.value.privileges

  depends_on = [databricks_schema.this]
}

resource "databricks_grant" "managed_external_location" {
  provider = databricks.workspace
  for_each = var.managed_external_location_grants

  external_location = databricks_external_location.managed.name
  principal         = each.key
  privileges        = each.value
}

resource "databricks_grant" "external_location" {
  provider = databricks.workspace
  for_each = var.external_location_grants

  external_location = databricks_external_location.external.name
  principal         = each.key
  privileges        = each.value
}

resource "databricks_grant" "storage_credential" {
  provider = databricks.workspace
  for_each = var.storage_credential_grants

  storage_credential = databricks_storage_credential.dev.name
  principal          = each.key
  privileges         = each.value
}
