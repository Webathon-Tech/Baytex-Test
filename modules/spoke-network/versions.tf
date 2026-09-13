# ----------------------------------------------------------------------------------------------------------------------
# Provider requirements
# azapi creates the hub-side peering by its full resource ID, so the module needs no provider configured for the hub subscription.
# ----------------------------------------------------------------------------------------------------------------------

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
  }
}
