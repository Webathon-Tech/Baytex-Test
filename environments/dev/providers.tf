provider "azurerm" {
  features {}

  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

  # "extended" registers the resource providers this platform needs and skips any already registered. At "none" a
  # subscription that has never hosted these services fails part-way through apply with MissingSubscriptionRegistration
  # -- Microsoft.Insights, needed for diagnostic settings and action groups, is the one that surfaces first. The set
  # covers Databricks, Insights, KeyVault and OperationalInsights on top of the core Compute, Network, Storage,
  # ManagedIdentity, Authorization and Resources.
  resource_provider_registrations = "extended"

  # Routes storage data-plane calls through Entra rather than an account key, so the platform works against storage
  # accounts that have shared key access disabled.
  storage_use_azuread = true
}

provider "azapi" {
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

provider "databricks" {
  alias      = "account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
  auth_type  = "azure-cli"

  # Without this the provider falls back to azure_tenant_id = "common" and asks the Azure CLI for a token against the
  # common endpoint, which cannot be issued silently. The apply then fails with "cannot get access token:
  # Status_InteractionRequired". Pinning the real tenant matches the signed-in context, as azurerm and azapi do above.
  azure_tenant_id = var.tenant_id
}
