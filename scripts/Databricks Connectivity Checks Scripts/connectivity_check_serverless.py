# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "5"
# ///
# MAGIC %md
# MAGIC # Connectivity check: Serverless
# MAGIC
# MAGIC **How to run:** attach this notebook to **Serverless** compute, check the settings in the next cell, then click **Run all**.
# MAGIC
# MAGIC Serverless compute reaches on-premises databases and storage accounts through the workspace's
# MAGIC Network Connectivity Configuration (NCC) private endpoints, and reaches the internet only through the egress policy allow list.
# MAGIC Another environment's storage account is reached only where that environment added private endpoint rules to this
# MAGIC workspace's NCC through its cross_environment_storage_readers.
# MAGIC
# MAGIC | # | Check | Expected result |
# MAGIC |---|---|---|
# MAGIC | 1 | On-premises databases | Every SQL Server and Oracle database **answers** |
# MAGIC | 2 | Storage accounts | Blob and dfs of **every** environment's account are **reached privately** |
# MAGIC | 3 | Allowed websites | **Reachable** |
# MAGIC | 4 | Blocked websites | **Not reachable**, which proves the egress policy is enforced. In DRY_RUN they stay reachable and show as INFO |
# MAGIC
# MAGIC **Latency columns**
# MAGIC - **Connect**: time to open the network connection. For databases this only reaches HAProxy, not the database.
# MAGIC - **Answer**: time for the destination to respond once connected. For databases this is the full path to the database and back.
# MAGIC
# MAGIC Uses only built-in Python. Nothing is installed, written or changed.

# COMMAND ----------

# =====================================================================================================================
# SETTINGS: change these for the environment you are testing
# =====================================================================================================================

# Environment of this workspace: "dev", "test" or "prod".
ENVIRONMENT = "dev"

# Data storage account of each environment. Every one is checked from this workspace, and each passes only when it is
# reached privately.
STORAGE_ACCOUNTS = {"dev": "stbtedbxdevcnc001", "test": "stbtedbxtestcnc001", "prod": "stbtedbxprodcnc001"}

# The egress policy's enforcement mode in this environment, serverless_egress_enforcement_mode in its tfvars: "ENFORCED" or "DRY_RUN".
# In DRY_RUN the policy only records what it would block, so a reachable blocked website is reported as INFO instead of FAIL.
ENFORCEMENT_MODE = "DRY_RUN"

# On-premises databases, as "hostname:port". Port 1433 is SQL Server, port 1521 is Oracle.
DATABASES = [
    "sqlbidb01yyc.baytexenergy.com:1433",
    "sqlbidb01yyc-t.baytexenergy.com:1433",
    "sql14yyc.baytexenergy.com:1433",
    "sql14yyc-t.baytexenergy.com:1433",
    "sql6.baytexenergy.com:1433",
    "tmwsql.baytexenergy.com:1433",
    "ora33yyc.baytexenergy.com:1521",
    "ora33yyc-t.baytexenergy.com:1521",
    "ora04yyc.baytexenergy.com:1521",
    "ora12yyc.baytexenergy.com:1521",
    "ora13yyc.baytexenergy.com:1521",
    "ora13yyc-t.baytexenergy.com:1521",
    "ora15yyc.baytexenergy.com:1521",
]

# Websites on the serverless allow list, as "hostname:port". These should be reachable. Ports 1433 and 1521 get a database check instead of TLS.
ALLOWED_SITES = [
    "baytex.prodman.ca:443",
    "platformv2api.peloton.com:443",
    "auth.peloton.com:443",
    "api.peloton.com:443",
    "id.peloton.com:443",
    "baytex-bi.database.windows.net:1433",
    "api.ca.samsara.com:443",
    "api.samsara.com:443",
    "api.eu.samsara.com:443",
    "baytex.whitson.com:443",
    "internal.whitson.com:443",
    "whitson.eu.auth0.com:443",
    "app1.envirosoft.com:443",
    "app1.envirosoft.com:8443",
    "apps.envirosoft.com:443",
    "apps.envirosoft.com:8443",
    "gdcdata1.geologic.com:1521",
    "gdcdata2.geologic.com:1521",
    "api.alberta.ca:443",
    "api.iam.alberta.ca:443",
    "peloton-baytexenergy.snowflakecomputing.com:443",
]

# Websites NOT on the allow list. Serverless should NOT be able to reach any of these.
BLOCKED_SITES = [
    "example.com:443",
    "www.wikipedia.org:443",
    "github.com:443",
    "pypi.org:443",
    "azureopendatastorage.blob.core.windows.net:443",  # a storage account outside Baytex (data exfiltration test)
]

# Seconds to wait for each connection before giving up.
TIMEOUT = 8

# COMMAND ----------

# =====================================================================================================================
# HELPER FUNCTIONS: no changes needed below this line
# =====================================================================================================================

import http.client
import ipaddress
import os
import socket
import ssl
import time

results = []  # every check is stored here and shown as a table at the end
TLS = ssl.create_default_context()  # created once, so loading certificates is not counted as latency


def heading(title, expected):
    """Prints a section title, what a good result looks like, and the column names."""
    print()
    print("=" * 130)
    print(title)
    print(f"Expected: {expected}")
    print("-" * 130)
    print(f"  {'':<5} {'TARGET':<48} {'CONNECT':>9} {'ANSWER':>9}  DETAIL")


def show_ms(value):
    """Formats a latency for the printed output."""
    return "-" if value is None else f"{value:.1f} ms"


def report(area, target, status, detail, connect_ms=None, answer_ms=None):
    """Prints one result line and keeps it for the summary."""
    results.append((status, area, target, connect_ms, answer_ms, detail))
    print(f"  {status:<5} {target:<48} {show_ms(connect_ms):>9} {show_ms(answer_ms):>9}  {detail}")


def elapsed_ms(start):
    """Milliseconds since start."""
    return round((time.perf_counter() - start) * 1000, 1)


def split(target):
    """Turns "hostname:port" into ("hostname", port)."""
    host, port = target.rsplit(":", 1)
    return host, int(port)


def reason(error):
    """A short, readable reason for a failed connection."""
    return str(error) or type(error).__name__


def open_connection(host, port):
    """Resolves the name, then opens a TCP connection, timing only the connection. Returns (connection, connect_ms, error)."""
    try:
        address = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)[0][4]
    except OSError as error:
        return None, None, f"does not resolve ({reason(error)})"
    start = time.perf_counter()
    try:
        connection = socket.create_connection(address, timeout=TIMEOUT)
    except OSError as error:
        return None, None, f"cannot connect ({reason(error)})"
    return connection, elapsed_ms(start), ""


# A tiny first message in each database's own language. Any reply proves the database itself answered,
# not only a proxy in front of it accepting the connection.
SQL_SERVER_HELLO = bytes.fromhex("1201001a00000100" "00000b0006" "0100110001" "ff" "100000000000" "00")  # TDS pre-login
ORACLE_HELLO = (
    bytes.fromhex("0057000001000000" "0136012c00000800" "7fff7f0800000001" "001d003a")
    + bytes(30)
    + b"(CONNECT_DATA=(COMMAND=ping))"
)  # TNS listener ping


def database_answers(host, port):
    """Connects to a database port and checks the database replies. Returns (ok, detail, connect_ms, answer_ms)."""
    name = "Oracle" if port == 1521 else "SQL Server"
    hello = ORACLE_HELLO if port == 1521 else SQL_SERVER_HELLO
    connection, connect_ms, error = open_connection(host, port)
    if error:
        return False, error, None, None
    with connection:
        start = time.perf_counter()
        try:
            connection.sendall(hello)
            reply = connection.recv(64)
        except OSError:
            reply = b""
        answer_ms = elapsed_ms(start)
    if reply:
        return True, f"{name} answered", connect_ms, answer_ms
    return False, f"port opened, but {name} did not answer (the proxy is up, the database behind it is not reachable)", connect_ms, None


def site_reachable(host, port):
    """Opens a secure (TLS) connection to a website, or a database check on port 1433 or 1521. Returns (reached, detail, connect_ms, answer_ms)."""
    if port in (1433, 1521):
        return database_answers(host, port)
    connection, connect_ms, error = open_connection(host, port)
    if error:
        return False, error, None, None
    start = time.perf_counter()
    try:
        with TLS.wrap_socket(connection, server_hostname=host):
            return True, "secure connection OK", connect_ms, elapsed_ms(start)
    except ssl.SSLCertVerificationError:
        return True, "reached (certificate not trusted)", connect_ms, elapsed_ms(start)
    except OSError as error:
        return False, reason(error), connect_ms, None
    finally:
        connection.close()


def storage_reachable(host):
    """Sends an anonymous request to the storage account. Returns (ok, detail, connect_ms, answer_ms).

    Reached privately, the name resolves to a private endpoint address and the account answers with a sign-in error,
    which is expected. A public address means the request goes over the internet, where the storage firewall refuses data
    requests. Blob shows this as "AuthorizationFailure"; dfs answers an anonymous request with a sign-in error before the
    firewall check, so for dfs the address is what shows the path.
    """
    connection, connect_ms, error = open_connection(host, 443)
    if error:
        return False, error, None, None
    address = connection.getpeername()[0]
    path = "/?resource=account" if ".dfs." in host else "/?comp=list"
    start = time.perf_counter()
    try:
        request = http.client.HTTPSConnection(host, timeout=TIMEOUT)
        request.sock = TLS.wrap_socket(connection, server_hostname=host)
        request.request("GET", path, headers={"x-ms-version": "2023-11-03"})
        response = request.getresponse()
        answer_ms = elapsed_ms(start)
        error_code = response.getheader("x-ms-error-code", "")
        request.close()
    except OSError as error:
        return False, reason(error), connect_ms, None
    finally:
        connection.close()
    if error_code == "AuthorizationFailure" or not ipaddress.ip_address(address).is_private:
        return False, f"refused by the storage firewall: {address} is a public address, so the request went over the internet", connect_ms, answer_ms
    return True, f"account reached privately at {address} (HTTP {response.status} {error_code}, a sign-in error is expected)", connect_ms, answer_ms


def storage_result(environment, reached, detail):
    """Status of one storage check: PASS when the account is reached privately, FAIL when it is not."""
    if reached:
        return "PASS", detail
    if environment == ENVIRONMENT:
        return "FAIL", detail
    return "FAIL", (
        f"{detail}. The {environment} deploy must list this workspace's NCC in cross_environment_storage_readers and "
        "approve its connections; a new rule takes about 10 minutes to reach serverless compute"
    )

# COMMAND ----------

# =====================================================================================================================
# RUN THE CHECKS
# =====================================================================================================================

if ENVIRONMENT not in STORAGE_ACCOUNTS:
    raise ValueError('ENVIRONMENT must be "dev", "test" or "prod".')
if ENFORCEMENT_MODE not in ("ENFORCED", "DRY_RUN"):
    raise ValueError('ENFORCEMENT_MODE must be "ENFORCED" or "DRY_RUN".')

runtime = os.environ.get("DATABRICKS_RUNTIME_VERSION", "unknown")
print("THIS COMPUTE")
print(f"  Compute     : {'Serverless' if runtime.startswith('client') else 'Classic cluster (use the classic notebook instead)'}")
print(f"  Runtime     : {runtime}")
print(f"  Environment : {ENVIRONMENT} (storage account {STORAGE_ACCOUNTS[ENVIRONMENT]}, egress policy {ENFORCEMENT_MODE})")

# ---- 1. On-premises databases ---------------------------------------------------------------------------------------
heading("1. ON-PREMISES DATABASES", "every database answers (path: NCC private endpoint > HAProxy > database)")
for target in DATABASES:
    ok, detail, connect_ms, answer_ms = database_answers(*split(target))
    report("Database", target, "PASS" if ok else "FAIL", detail, connect_ms, answer_ms)

# ---- 2. Storage accounts --------------------------------------------------------------------------------------------
heading("2. STORAGE ACCOUNTS", "every account is reached privately (path: NCC private endpoint)")
for environment, account in STORAGE_ACCOUNTS.items():
    for name in (f"{account}.blob.core.windows.net", f"{account}.dfs.core.windows.net"):
        reached, detail, connect_ms, answer_ms = storage_reachable(name)
        status, detail = storage_result(environment, reached, detail)
        report(f"Storage {environment}", name, status, detail, connect_ms, answer_ms)

# ---- 3. Allowed websites --------------------------------------------------------------------------------------------
heading("3. ALLOWED WEBSITES", "every site is reachable")
for target in ALLOWED_SITES:
    reached, detail, connect_ms, answer_ms = site_reachable(*split(target))
    report("Allowed site", target, "PASS" if reached else "FAIL", detail, connect_ms, answer_ms)

# ---- 4. Blocked websites --------------------------------------------------------------------------------------------
heading("4. BLOCKED WEBSITES", "no site is reachable" if ENFORCEMENT_MODE == "ENFORCED" else "sites stay reachable, because a DRY_RUN policy only records what it would block")
for target in BLOCKED_SITES:
    reached, detail, connect_ms, answer_ms = site_reachable(*split(target))
    if not reached:
        report("Blocked site", target, "PASS", f"blocked: {detail}")
    elif ENFORCEMENT_MODE == "DRY_RUN":
        report("Blocked site", target, "INFO", "reachable, as expected in DRY_RUN; ENFORCED would block it", connect_ms, answer_ms)
    else:
        report("Blocked site", target, "FAIL", "reachable, so the egress policy is NOT blocking it", connect_ms, answer_ms)

# COMMAND ----------

# =====================================================================================================================
# SUMMARY
# =====================================================================================================================

passed = [row for row in results if row[0] == "PASS"]
failures = [row for row in results if row[0] == "FAIL"]
print("=" * 130)
print(f"SUMMARY: {len(passed)} passed, {len(failures)} failed")
print("=" * 130)
if failures:
    print("Failed checks:")
    for status, area, target, connect_ms, answer_ms, detail in failures:
        print(f"  {area:<14} {target:<48} {detail}")
else:
    print("All checks passed.")

try:
    display(spark.createDataFrame(results, "status string, area string, target string, connect_ms double, answer_ms double, detail string"))  # noqa: F821
except Exception:  # noqa: BLE001 - the printed output above is enough if the table cannot be shown
    pass