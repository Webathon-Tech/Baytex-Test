# ----------------------------------------------------------------------------------------------------------------------
# Terraform and provider versions
# Provider lock files are not committed, so every run installs the newest release these constraints allow.
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

# ----------------------------------------------------------------------------------------------------------------------
# Providers
# ----------------------------------------------------------------------------------------------------------------------

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # "extended" registers the resource providers this root needs and skips any that are already registered.
  resource_provider_registrations = "extended"

  # Required because the state storage account has shared key access disabled.
  # The provider manages data-plane settings, such as blob versioning, through Microsoft Entra ID with the Storage Blob Data Contributor role instead of an account key.
  storage_use_azuread = true
}
