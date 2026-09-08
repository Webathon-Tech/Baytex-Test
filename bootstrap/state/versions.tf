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
  }
}

provider "azurerm" {
  features {}

  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"

  # Required, because the storage account this root manages has
  # shared_access_key_enabled = false.
  #
  # To manage a storage account's data-plane settings the provider builds a
  # data-plane client, and by default it does that by calling ListKeys. On an
  # account with keys disabled that returns:
  #   403 Key based authentication is not permitted on this storage account.
  #     (KeyBasedAuthenticationNotPermitted)
  # which surfaces as "encoding Storage Account (...)" during plan and apply.
  #
  # storage_use_azuread makes the provider authenticate to the data plane with
  # the signed-in Entra identity instead, using the service principal's Storage
  # Blob Data Contributor role. The environment roots set this for the same
  # reason.
  storage_use_azuread = true
}
