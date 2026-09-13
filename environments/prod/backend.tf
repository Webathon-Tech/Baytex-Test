# ----------------------------------------------------------------------------------------------------------------------
# State backend
# The settings are supplied at init time with -backend-config: the pipelines read them from the TF_STATE_* variables on the GitHub Environment.
# State is stored in the storage account created by bootstrap/<env>, and access uses Microsoft Entra ID rather than an account key.
# ----------------------------------------------------------------------------------------------------------------------

terraform {
  backend "azurerm" {}
}
