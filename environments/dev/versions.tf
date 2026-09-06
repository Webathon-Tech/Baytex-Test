terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.130.0"
    }
  }
}
