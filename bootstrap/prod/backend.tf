# Deliberately empty. This root creates the very storage account it later stores its own state in, so on a first run
# there is no backend to point at. The workflow runs it with local state, applies, then re-runs
# "terraform init -migrate-state" with these values supplied through -backend-config. Every later run inits straight
# against the remote backend.
terraform {
  backend "azurerm" {}
}
