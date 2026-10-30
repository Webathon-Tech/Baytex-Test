# Unity Catalog Handoff

Azure Databricks assigns every new workspace to the existing regional metastore automatically, and gives it a workspace
catalog whose storage is the workspace's default storage account in the managed resource group. The platform leaves
both as they are and creates no catalogs or schemas. What it adds is a way to keep catalog data in the environment's
own data storage account: a storage credential and an external location over that account, ready for Baytex BI to use
when they create catalogs.

## What the platform creates

In each environment, the `ncc` module creates the objects below. `<instance>` is `001` in dev and prod and `002` in
test, so the test location is `el_bte_dbx_test_data_cnc_002` on storage account `stbtedbxtestcnc002`.

| Object | Name | Details |
| --- | --- | --- |
| Container | `unity-catalog` | In the data storage account. It is always created, whatever `data_containers` holds; `unity_catalog_container_name` changes the name |
| Storage credential | `sc_bte_dbx_<env>_data_cnc_<instance>` | Backed by the data Access Connector, which holds Storage Blob Data Contributor on the data storage account |
| External location | `el_bte_dbx_<env>_data_cnc_<instance>` | Covers `abfss://unity-catalog@stbtedbx<env>cnc<instance>.dfs.core.windows.net/` |
| Grants on the external location | From `unity_catalog_external_location_grants` | None by default |

- **Isolated to the environment's workspace.** The three workspaces share one metastore, so the credential and the
  location can be used only from their own environment's workspace. Test and prod cannot use the dev location, and so on.
- **Owned by the deployment service principal**, `app-bte-dbx-<env>-terraform-001`. Metastore admins can use it too.
  Anyone else needs a grant on the location.
- **Not validated when saved.** Databricks reaches the storage account only through the NCC private endpoints, which
  the deploy pipeline approves after the apply. Access is confirmed after the deployment instead; see step 5 below.
- **File events off.** They need a storage queue that Databricks cannot reach while the account has public network
  access disabled.
- **Not deleted while in use.** A location that still holds a catalog's or a table's storage is not removed with the
  environment. Drop those catalogs first.
- **Created only in the expected metastore.** Before creating anything, the platform confirms the workspace is assigned
  to `existing_metastore_id`.
- **Can be switched off.** `create_unity_catalog_external_location = false` removes the credential and location, for
  example before the workspace is replaced. It fails while a catalog still keeps its storage in the location.

## What the platform provides

Each environment's `unity_catalog_handoff` output contains:

| Field | Contents |
| --- | --- |
| `databricks_account_id` | The existing Databricks account |
| `existing_metastore_id` | The existing regional metastore the workspace is assigned to |
| `workspace_id`, `workspace_url`, `workspace_arm_id` | The environment's workspace |
| `access_connector_id`, `access_connector_principal_id` | The data Access Connector, which holds Storage Blob Data Contributor and the file-event roles on the data storage account |
| `storage_account_id`, `storage_account_name` | The ADLS Gen2 data storage account |
| `storage_locations` | `abfss://` URL of every container in the data storage account |
| `storage_credential_name` | The platform's storage credential |
| `external_location_name`, `external_location_url` | The platform's external location and the URL it covers |
| `environment`, `owner`, `terraform_state_boundary` | Context for the handoff |

The `unity_catalog_external_location` output repeats the location's name, URL and storage credential on its own.

## What Baytex BI completes

1. **Grant access to the location.** Principals that create catalogs need `CREATE CATALOG` on the metastore, granted
   by a metastore admin, and `CREATE_MANAGED_STORAGE` on the external location. Grant the location privileges by
   listing the group in `unity_catalog_external_location_grants` in the environment's `terraform.tfvars` and
   deploying, or have a metastore admin grant them directly. Terraform manages every privilege of a principal it lists,
   so grant a listed principal more only through the variable; principals it does not list are left alone.
2. **Create the catalogs with their managed storage in the location**, one folder per catalog:

   ```sql
   CREATE CATALOG IF NOT EXISTS <catalog>
     MANAGED LOCATION 'abfss://unity-catalog@stbtedbx<env>cnc<instance>.dfs.core.windows.net/<catalog>';
   ```

3. **Create schemas and grants.** Grant privileges to account-level groups and service principals, not to individual
   users.
4. **Decide workspace bindings.** Set each catalog's isolation mode and bind it to the approved workspaces, and decide
   any cross-environment access and whether it is read-only or read-write.
5. **Validate access.** In Catalog Explorer, open the external location and run **Test connection**, then run a
   representative workload that writes and reads a table and a volume from classic and serverless compute. A new
   external location takes about 10 minutes to reach the serverless network policy, so serverless access can be denied
   until then.

## Reference implementation

`baytex-bi-owned-unity-catalog-example/` demonstrates steps 2 to 4 as Terraform in its own state, using the platform's
external location. It is not called by the platform roots and is not deployed by the pipelines. Its
[README](../baytex-bi-owned-unity-catalog-example/README.md) explains how to run it.
