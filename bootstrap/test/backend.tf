# ----------------------------------------------------------------------------------------------------------------------
# State backend
# Left empty because this root creates the storage account that later holds its own state.
# On the first run the workflow applies with local state, then runs "terraform init -migrate-state" with -backend-config values that point at the new account.
# Every later run initialises directly against that remote backend.
# ----------------------------------------------------------------------------------------------------------------------

terraform {
  backend "azurerm" {}
}
