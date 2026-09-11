terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.131.0"
    }
  }
}
