# Databricks notebook source
# STEP 1: binds the 7 old sets to the dev workspace and makes you their owner. Drops nothing. Safe to re-run.
from urllib.parse import quote
from databricks.sdk import WorkspaceClient
w = WorkspaceClient()

DEV = 7405619498714522
NAMES = [
    "dbw_bte_dbx_dev_cnc_001",
    "dbw_bte_dbx_dev_cnc_001_7405611786903039",
    "dbw_bte_dbx_dev_cnc_001_7405614274025784",
    "dbw_bte_dbx_dev_cnc_001_7405616239166243",
    "dbw_bte_dbx_dev_cnc_001_7405617969968915",
    "dbw_bte_dbx_dev_cnc_001_7405618080347676",
    "dbw_bte_dbx_dev_cnc_001_7405619884802847",
]
assert all("7405619498714522" not in n for n in NAMES), "The live dev workspace's set must not be in this list"
# The sets belong to dev, so Run all stops here in any other workspace, before the DROP cells.
assert w.get_workspace_id() == DEV, f"Run this notebook in the dev workspace ({DEV}) only"

me = w.current_user.me().user_name
KINDS = [("catalog", "catalogs", {}),
         ("external_location", "external-locations", {"skip_validation": True}),
         ("storage_credential", "storage-credentials", {"skip_validation": True})]

for n in NAMES:
    for kind, path, extra in KINDS:
        ref = quote(n, safe="")
        try:
            w.api_client.do("PATCH", f"/api/2.1/unity-catalog/bindings/{kind}/{ref}",
                            body={"add": [{"workspace_id": DEV, "binding_type": "BINDING_TYPE_READ_WRITE"}]})
            w.api_client.do("PATCH", f"/api/2.1/unity-catalog/{path}/{ref}", body={"owner": me, **extra})
            print(f"ready   {kind:18} {n}")
        except Exception as e:
            msg = str(e).splitlines()[0]
            gone = "does not exist" in msg.lower() or "not found" in msg.lower()
            print(f"{'gone   ' if gone else 'FAILED '} {kind:18} {n}: {msg[:140]}")


# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT catalog_name, catalog_owner, created
# MAGIC FROM system.information_schema.catalogs
# MAGIC WHERE catalog_name IN ('dbw_bte_dbx_dev_cnc_001','dbw_bte_dbx_dev_cnc_001_7405611786903039','dbw_bte_dbx_dev_cnc_001_7405614274025784',
# MAGIC                        'dbw_bte_dbx_dev_cnc_001_7405616239166243','dbw_bte_dbx_dev_cnc_001_7405617969968915',
# MAGIC                        'dbw_bte_dbx_dev_cnc_001_7405618080347676','dbw_bte_dbx_dev_cnc_001_7405619884802847')
# MAGIC ORDER BY catalog_name;
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT catalog_name, schema_name
# MAGIC FROM system.information_schema.schemata
# MAGIC WHERE catalog_name IN ('dbw_bte_dbx_dev_cnc_001','dbw_bte_dbx_dev_cnc_001_7405611786903039','dbw_bte_dbx_dev_cnc_001_7405614274025784',
# MAGIC                        'dbw_bte_dbx_dev_cnc_001_7405616239166243','dbw_bte_dbx_dev_cnc_001_7405617969968915',
# MAGIC                        'dbw_bte_dbx_dev_cnc_001_7405618080347676','dbw_bte_dbx_dev_cnc_001_7405619884802847')
# MAGIC ORDER BY catalog_name, schema_name;
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT table_catalog, table_schema, table_name, table_type
# MAGIC FROM system.information_schema.tables
# MAGIC WHERE table_schema <> 'information_schema'
# MAGIC   AND table_catalog IN ('dbw_bte_dbx_dev_cnc_001','dbw_bte_dbx_dev_cnc_001_7405611786903039','dbw_bte_dbx_dev_cnc_001_7405614274025784',
# MAGIC                         'dbw_bte_dbx_dev_cnc_001_7405616239166243','dbw_bte_dbx_dev_cnc_001_7405617969968915',
# MAGIC                         'dbw_bte_dbx_dev_cnc_001_7405618080347676','dbw_bte_dbx_dev_cnc_001_7405619884802847');
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT volume_catalog, volume_schema, volume_name
# MAGIC FROM system.information_schema.volumes
# MAGIC WHERE volume_catalog IN ('dbw_bte_dbx_dev_cnc_001','dbw_bte_dbx_dev_cnc_001_7405611786903039','dbw_bte_dbx_dev_cnc_001_7405614274025784',
# MAGIC                          'dbw_bte_dbx_dev_cnc_001_7405616239166243','dbw_bte_dbx_dev_cnc_001_7405617969968915',
# MAGIC                          'dbw_bte_dbx_dev_cnc_001_7405618080347676','dbw_bte_dbx_dev_cnc_001_7405619884802847');
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Catalogs
# MAGIC DROP CATALOG IF EXISTS dbw_bte_dbx_dev_cnc_001 CASCADE;
# MAGIC DROP CATALOG IF EXISTS dbw_bte_dbx_dev_cnc_001_7405611786903039 CASCADE;
# MAGIC DROP CATALOG IF EXISTS dbw_bte_dbx_dev_cnc_001_7405614274025784 CASCADE;
# MAGIC DROP CATALOG IF EXISTS dbw_bte_dbx_dev_cnc_001_7405616239166243 CASCADE;
# MAGIC DROP CATALOG IF EXISTS dbw_bte_dbx_dev_cnc_001_7405617969968915 CASCADE;
# MAGIC DROP CATALOG IF EXISTS dbw_bte_dbx_dev_cnc_001_7405618080347676 CASCADE;
# MAGIC DROP CATALOG IF EXISTS dbw_bte_dbx_dev_cnc_001_7405619884802847 CASCADE;
# MAGIC
# MAGIC -- External locations
# MAGIC DROP EXTERNAL LOCATION IF EXISTS dbw_bte_dbx_dev_cnc_001;
# MAGIC DROP EXTERNAL LOCATION IF EXISTS dbw_bte_dbx_dev_cnc_001_7405611786903039;
# MAGIC DROP EXTERNAL LOCATION IF EXISTS dbw_bte_dbx_dev_cnc_001_7405614274025784;
# MAGIC DROP EXTERNAL LOCATION IF EXISTS dbw_bte_dbx_dev_cnc_001_7405616239166243;
# MAGIC DROP EXTERNAL LOCATION IF EXISTS dbw_bte_dbx_dev_cnc_001_7405617969968915;
# MAGIC DROP EXTERNAL LOCATION IF EXISTS dbw_bte_dbx_dev_cnc_001_7405618080347676;
# MAGIC DROP EXTERNAL LOCATION IF EXISTS dbw_bte_dbx_dev_cnc_001_7405619884802847;
# MAGIC
# MAGIC -- Storage credentials
# MAGIC DROP STORAGE CREDENTIAL IF EXISTS dbw_bte_dbx_dev_cnc_001;
# MAGIC DROP STORAGE CREDENTIAL IF EXISTS dbw_bte_dbx_dev_cnc_001_7405611786903039;
# MAGIC DROP STORAGE CREDENTIAL IF EXISTS dbw_bte_dbx_dev_cnc_001_7405614274025784;
# MAGIC DROP STORAGE CREDENTIAL IF EXISTS dbw_bte_dbx_dev_cnc_001_7405616239166243;
# MAGIC DROP STORAGE CREDENTIAL IF EXISTS dbw_bte_dbx_dev_cnc_001_7405617969968915;
# MAGIC DROP STORAGE CREDENTIAL IF EXISTS dbw_bte_dbx_dev_cnc_001_7405618080347676;
# MAGIC DROP STORAGE CREDENTIAL IF EXISTS dbw_bte_dbx_dev_cnc_001_7405619884802847;
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC SHOW EXTERNAL LOCATIONS;
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC SHOW STORAGE CREDENTIALS;
# MAGIC