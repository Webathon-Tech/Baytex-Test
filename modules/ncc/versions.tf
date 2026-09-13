# ----------------------------------------------------------------------------------------------------------------------
# Provider requirements
# The calling root passes the account-level databricks provider as this module's default databricks provider.
# Every pipeline job sets DATABRICKS_TF_ENABLED_PF_RESOURCES=databricks_mws_ncc_private_endpoint_rule, so the private endpoint rules run on the provider's plugin framework implementation.
# ----------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.131.0"
    }
  }
}
