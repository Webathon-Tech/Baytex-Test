# ----------------------------------------------------------------------------------------------------------------------
# Baytex BI Unity Catalog reference
# Creates an environment catalog whose managed storage sits in the platform's external location, with its schemas, workspace bindings and grants.
# The platform creates the storage credential and external location, and Azure Databricks assigns the workspace to the metastore when the workspace is created.
# It uses its own Terraform state and is not called by the platform roots.
# ----------------------------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------------------------
# Catalog and schemas
# ----------------------------------------------------------------------------------------------------------------------

# The catalog's managed storage is its own folder under the platform's external location.
resource "databricks_catalog" "dev" {
  provider = databricks.workspace

  name           = var.catalog_name
  storage_root   = "${trimsuffix(var.external_location_url, "/")}/${var.catalog_name}"
  owner          = var.catalog_owner
  comment        = "Environment catalog owned by ${var.catalog_owner}, with managed storage in the platform's external location."
  isolation_mode = "ISOLATED"
  force_destroy  = false
}

# A schema without its own comment gets a default one, and a schema without its own owner is owned by the catalog owner.
resource "databricks_schema" "this" {
  provider = databricks.workspace
  for_each = var.schemas

  catalog_name = databricks_catalog.dev.name
  name         = each.key
  comment      = coalesce(try(each.value.comment, null), "Schema ${each.key} in the ${var.catalog_name} catalog.")
  owner        = coalesce(try(each.value.owner, null), var.catalog_owner)
}

# ----------------------------------------------------------------------------------------------------------------------
# Workspace bindings
# ----------------------------------------------------------------------------------------------------------------------

# An isolated catalog is usable only from workspaces it is bound to, so it is bound to this workspace.
resource "databricks_workspace_binding" "catalog_current" {
  provider = databricks.workspace

  securable_name = databricks_catalog.dev.name
  securable_type = "catalog"
  workspace_id   = var.workspace_id
  binding_type   = "BINDING_TYPE_READ_WRITE"
}

resource "databricks_workspace_binding" "catalog_additional" {
  provider = databricks.workspace
  for_each = var.additional_catalog_workspace_bindings

  securable_name = databricks_catalog.dev.name
  securable_type = "catalog"
  workspace_id   = each.value.workspace_id
  binding_type   = each.value.binding_type
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
