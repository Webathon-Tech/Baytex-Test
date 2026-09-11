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

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # "extended" registers the resource providers this platform needs, skipping any already registered. At "none" a
  # subscription that has never hosted these services fails mid-apply with MissingSubscriptionRegistration.
  resource_provider_registrations = "extended"

  # Required, because the storage account this root creates sets shared_access_key_enabled = false. To manage a storage
  # account's data-plane settings the provider builds a data-plane client, and by default it does that by calling
  # ListKeys, which returns 403 KeyBasedAuthenticationNotPermitted on a keyless account. This routes those calls through
  # Entra instead, using the service principal's Storage Blob Data Contributor role.
  storage_use_azuread = true
}
