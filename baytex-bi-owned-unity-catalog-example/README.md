# Baytex BI Unity Catalog Reference

A reference implementation of the Unity Catalog layer for one platform environment. It is owned by Baytex BI, uses its
own Terraform state, and is not called by the platform roots or deployed by the pipelines. The handoff it implements is
described in [docs/unity-catalog-handoff.md](../docs/unity-catalog-handoff.md).

## What it creates

- The assignment of the environment's workspace to the **existing regional metastore**
- An environment-specific storage credential backed by the platform's data Access Connector
- Separate external locations for managed catalog storage and for general-purpose use
- An environment-specific catalog and schemas
- Workspace bindings that isolate the catalog, external locations and storage credential to approved workspaces
- Grants to existing account-level groups and service principals

Baytex BI owns the final naming, catalog structure, groups, grants, workspace bindings and cross-environment access
decisions.

## Inputs

Take the workspace and storage values from the platform's outputs:

| Input | Platform output |
| --- | --- |
| `workspace_id` | `databricks_workspace_id` |
| `workspace_url` | `databricks_workspace_url` |
| `access_connector_id` | `data_access_connector_id` |
| `storage_account_name` | `data_storage_account_name` |
| `metastore_id` | `existing_metastore_id` in `unity_catalog_handoff` |

`terraform.tfvars.example` lists every input in the section order of `variables.tf`, with comments.

## Run

Sign in with the Azure CLI as an identity that is a metastore administrator and a workspace administrator, configure a
separate backend for this state, then:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out uc.tfplan
terraform apply uc.tfplan
```

## Notes

- The workspace must be in the same Azure region as the metastore.
- Grant privileges to groups, not to individual users.
- The catalog's managed storage root sits under a registered external location, as Unity Catalog requires.
- A workspace binding changes a securable from all-workspace access to explicitly bound workspaces only.
- Read-only bindings are supported only for catalogs; storage credentials and external locations use read-write
  bindings.
