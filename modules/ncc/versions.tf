terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.130.0"
    }
  }
}
