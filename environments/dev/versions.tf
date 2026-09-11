terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.131.0"
    }
  }
}
