# Databricks notebook source
# DBTITLE 1,Settings
# Environment of this workspace: "dev", "test" or "prod". The external location and storage account are derived from it.
ENVIRONMENT = "dev"

# The last cell drops the test catalog. Set to False to keep it.
DESTROY = True

# Instance number at the end of each environment's resource names.
INSTANCE = {"dev": "001", "test": "002", "prod": "001"}.get(ENVIRONMENT)

LOCATION = f"el_bte_dbx_{ENVIRONMENT}_data_cnc_{INSTANCE}"
CATALOG = "test_vedant_catalog"
CATALOG_URL = f"abfss://unity-catalog@stbtedbx{ENVIRONMENT}cnc{INSTANCE}.dfs.core.windows.net/{CATALOG}"

if ENVIRONMENT not in ("dev", "test", "prod"):
    raise ValueError('ENVIRONMENT must be "dev", "test" or "prod".')

# COMMAND ----------

# DBTITLE 1,Check your access to the location (read-only)
display(spark.sql(f"SHOW GRANTS ON EXTERNAL LOCATION {LOCATION}"))

# COMMAND ----------

# DBTITLE 1,Create the catalog in its own folder
spark.sql(f"CREATE CATALOG IF NOT EXISTS {CATALOG} MANAGED LOCATION '{CATALOG_URL}' COMMENT 'Test catalog on external location {LOCATION}'")
display(spark.sql(f"DESCRIBE CATALOG EXTENDED {CATALOG}"))

# COMMAND ----------

# DBTITLE 1,Schema and managed table, with one row added per run
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.smoke")
spark.sql(f"CREATE TABLE IF NOT EXISTS {CATALOG}.smoke.check_table (run_at TIMESTAMP, written_by STRING)")
spark.sql(f"INSERT INTO {CATALOG}.smoke.check_table VALUES (current_timestamp(), current_user())")
display(spark.sql(f"SELECT * FROM {CATALOG}.smoke.check_table ORDER BY run_at DESC"))

# COMMAND ----------

# DBTITLE 1,Confirm where the table's files are
display(spark.sql(f"DESCRIBE DETAIL {CATALOG}.smoke.check_table"))

# COMMAND ----------

# DBTITLE 1,Volume, with a file written and listed
spark.sql(f"CREATE VOLUME IF NOT EXISTS {CATALOG}.smoke.files")
dbutils.fs.put(f"/Volumes/{CATALOG}/smoke/files/hello.txt", f"hello from {LOCATION}", True)
display(spark.sql(f"LIST '/Volumes/{CATALOG}/smoke/files/'"))

# COMMAND ----------

# DBTITLE 1,Remove the test catalog (does nothing unless DESTROY is True)
if DESTROY:
    spark.sql(f"DROP CATALOG IF EXISTS {CATALOG} CASCADE")
    print(f"Dropped {CATALOG}")
else:
    print("DESTROY is False: nothing was dropped")
