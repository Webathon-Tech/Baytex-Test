# Deliberately empty: the bootstrap root creates the very storage account it
# later stores its own state in, so on the FIRST run there is no backend to
# point at. The pipeline runs it with local state, applies, then re-runs
# `terraform init -migrate-state` with these values supplied by -backend-config.
# Every subsequent run inits straight against the remote backend.
terraform {
  backend "azurerm" {}
}
