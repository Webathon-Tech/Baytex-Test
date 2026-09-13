# ----------------------------------------------------------------------------------------------------------------------
# Azure: this environment's subscription
# ----------------------------------------------------------------------------------------------------------------------

provider "azurerm" {
  features {}

  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

  # "extended" registers the resource providers this platform needs and skips any that are already registered.
  # It covers Databricks, Insights, KeyVault and OperationalInsights, as well as the core Compute, Network, Storage, ManagedIdentity, Authorization and Resources providers.
  # Microsoft.Insights, for example, must be registered before diagnostic settings and action groups can be created.
  resource_provider_registrations = "extended"

  # Storage data-plane calls authenticate with Microsoft Entra ID rather than an account key, so the platform works with storage accounts that have shared key access disabled.
  storage_use_azuread = true
}

provider "azapi" {
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

# ----------------------------------------------------------------------------------------------------------------------
# Databricks account
# ----------------------------------------------------------------------------------------------------------------------

# Account-level provider for the Network Connectivity Configuration, authenticated through the signed-in Azure CLI session.
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
  auth_type  = "azure-cli"

  # The Azure CLI token is requested for this tenant.
  # Without it the provider uses the multi-tenant "common" endpoint, which cannot issue a token without an interactive sign-in.
  azure_tenant_id = var.tenant_id
}
