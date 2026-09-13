# Unity Catalog Handoff

The platform creates Azure and Databricks account resources only. It creates no Unity Catalog objects: Baytex BI owns
the Unity Catalog layer for every environment.

## What the platform provides

Each environment's `unity_catalog_handoff` output contains:

| Field | Contents |
| --- | --- |
| `databricks_account_id` | The existing Databricks account |
| `existing_metastore_id` | The existing regional metastore the workspace attaches to |
| `workspace_id`, `workspace_url`, `workspace_arm_id` | The environment's workspace |
| `access_connector_id`, `access_connector_principal_id` | The data Access Connector, which holds Storage Blob Data Contributor and the file-event roles on the data storage account |
| `storage_account_id`, `storage_account_name` | The ADLS Gen2 data storage account |
| `storage_locations` | `abfss://` URLs of the `managed`, `external`, `landing` and `checkpoints` containers |
| `environment`, `owner`, `terraform_state_boundary` | Context for the handoff |

## What Baytex BI completes

1. Assign the environment's workspace to the existing Canada Central metastore.
2. Create an environment-specific storage credential backed by the data Access Connector.
3. Create separate external locations for managed catalog storage and for general-purpose use.
4. Create the environment's catalog and schemas.
5. Set the securables to isolated mode and bind them explicitly to the approved workspaces.
6. Grant privileges to account-level groups and service principals, not to individual users.
7. Decide any cross-environment bindings, and whether each is read-only or read-write.
8. Validate storage, catalog, table and volume access with a representative workload.

## Reference implementation

`baytex-bi-owned-unity-catalog-example/` demonstrates these steps as Terraform in its own state. It is not called by the
platform roots and is not deployed by the pipelines. Its [README](../baytex-bi-owned-unity-catalog-example/README.md)
explains how to run it.
