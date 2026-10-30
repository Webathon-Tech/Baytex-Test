# Databricks notebook source
# DBTITLE 1,Notebook title and description
# MAGIC %md
# MAGIC # Connectivity Checks
# MAGIC
# MAGIC Validates network connectivity from the Databricks compute environment to internal and external endpoints. Covers DNS resolution across multiple servers, TCP socket connectivity (classic compute), and hostname-based connectivity (serverless compute).

# COMMAND ----------

# DBTITLE 1,Install dependency
# Install the dnspython library for programmatic DNS resolution queries
%pip install dnspython

# COMMAND ----------

# DBTITLE 1,Settings
# Environment of this workspace: "dev", "test" or "prod". The storage account and its private endpoint IPs are derived from it.
ENVIRONMENT = "dev"

# Instance number at the end of each environment's resource names.
INSTANCE = {"dev": "001", "test": "002", "prod": "001"}.get(ENVIRONMENT)

STORAGE_ACCOUNT = f"stbtedbx{ENVIRONMENT}cnc{INSTANCE}"

# The blob and dfs private endpoints use the .4 and .5 addresses of the environment's private endpoint subnet.
PRIVATE_ENDPOINT_SUBNET = {"dev": "10.40.146", "test": "10.40.194", "prod": "10.40.178"}[ENVIRONMENT]
STORAGE_ENDPOINTS = [
    (f"{STORAGE_ACCOUNT}.blob.core.windows.net", f"{PRIVATE_ENDPOINT_SUBNET}.4", 443),
    (f"{STORAGE_ACCOUNT}.dfs.core.windows.net",  f"{PRIVATE_ENDPOINT_SUBNET}.5", 443),
]

# COMMAND ----------

# DBTITLE 1,DNS connectivity checks (Classic Compute)
import dns.resolver
import pandas as pd

# Target hostnames — SQL Server, Oracle, and Azure Storage endpoints
hosts_to_check = [
    "sql14yyc.baytexenergy.com",
    "sql14yyc-t.baytexenergy.com",
    "sql6.baytexenergy.com",
    "sqlbidb01yyc.baytexenergy.com",
    "sqlbidb01yyc-t.baytexenergy.com",
    "tmwsql.baytexenergy.com",
    "ora33yyc.baytexenergy.com",
    "ora33yyc-t.baytexenergy.com",
    "ora04yyc.baytexenergy.com",
    "ora12yyc.baytexenergy.com",
    "ora13yyc.baytexenergy.com",
    "ora13yyc-t.baytexenergy.com",
    "ora15yyc.baytexenergy.com",
] + [name for name, _, _ in STORAGE_ENDPOINTS]

# DNS servers — on-prem, private resolver, and VNet DNS endpoints
dns_servers = [
    "10.40.128.5",
    "10.40.128.6",
    "10.40.240.132",  # Private DNS Resolver Inbound Endpoint
    "172.19.65.2",
    "172.19.65.39",
    "172.19.65.3",
    "172.19.96.124",
]

# Resolve each hostname against each DNS server and capture the result
results = []

for h in hosts_to_check:
    for dns_server in dns_servers:
        resolver = dns.resolver.Resolver(configure=False)
        resolver.nameservers = [dns_server]
        resolver.timeout = 3
        resolver.lifetime = 3
        try:
            answer = resolver.resolve(h, "A")
            value = ", ".join(sorted(set(r.address for r in answer)))
        except dns.resolver.NXDOMAIN:
            value = "FAIL (NXDOMAIN)"
        except dns.exception.Timeout:
            value = "FAIL (Timeout)"
        except Exception as e:
            value = f"FAIL ({type(e).__name__})"
        results.append({"Hostname": h, "DnsServer": dns_server, "Result": value})

dns_detail_df = pd.DataFrame(results)

# Pivot into a hostname × DNS-server matrix for easy comparison
dns_matrix_df = (
    dns_detail_df.pivot(index="Hostname", columns="DnsServer", values="Result")
      .reindex(index=hosts_to_check, columns=dns_servers)
      .reset_index()
)
dns_matrix_df.columns.name = None

display(dns_matrix_df)

# COMMAND ----------

# DBTITLE 1,TCP connectivity checks (classic compute)
import socket
import time
import pandas as pd

# Destinations: (friendly name, IP, port)
# SQL Server = 1433, Oracle = 1521, Azure Storage HTTPS = 443
destinations = [
    ("sql14yyc.baytexenergy.com",       "172.19.77.94",   1433),
    ("sql14yyc-t.baytexenergy.com",     "172.19.96.137",  1433),
    ("sql6.baytexenergy.com",           "172.19.77.123",  1433),
    ("sqlbidb01yyc.baytexenergy.com",   "172.19.77.45",   1433),
    ("sqlbidb01yyc-t.baytexenergy.com", "172.19.96.44",   1433),
    ("tmwsql.baytexenergy.com",         "172.23.178.197", 1433),
    ("ora33yyc.baytexenergy.com",       "172.19.77.88",   1521),
    ("ora33yyc-t.baytexenergy.com",     "172.19.96.112",  1521),
    ("ora04yyc.baytexenergy.com",       "172.19.77.95",   1521),
    ("ora12yyc.baytexenergy.com",       "172.19.77.90",   1521),
    ("ora13yyc.baytexenergy.com",       "172.19.77.99",   1521),
    ("ora13yyc-t.baytexenergy.com",     "172.19.96.110",  1521),
    ("ora15yyc.baytexenergy.com",       "172.19.77.91",   1521),
] + STORAGE_ENDPOINTS

# Connection timeout in seconds
TIMEOUT = 5

# Attempt a TCP connection to each destination and record status + latency
results = []

for name, ip, port in destinations:
    start = time.time()
    try:
        with socket.create_connection((ip, port), timeout=TIMEOUT):
            status, detail = "OK", "Connected"
    except socket.timeout:
        status, detail = "FAIL", "Timeout (no route or dropped)"
    except ConnectionRefusedError:
        status, detail = "FAIL", "Refused (reachable, port closed/rejected)"
    except OSError as e:
        status, detail = "FAIL", e.strerror or type(e).__name__
    latency = round((time.time() - start) * 1000, 1)

    results.append({
        "Destination": name,
        "IP": ip,
        "Port": port,
        "Status": status,
        "Detail": detail,
        "LatencyMs": latency if status == "OK" else None,
    })

display(pd.DataFrame(results))

# COMMAND ----------

# DBTITLE 1,TCP connectivity checks (serverless compute)
# For serverless compute — uses hostnames instead of IPs
# so DNS resolution is also validated in the same check
import socket

# Target endpoints: (hostname, expected IP, port)
targets = {
    ("sql14yyc.baytexenergy.com",       "172.19.77.94",   1433),
    ("sql14yyc-t.baytexenergy.com",     "172.19.96.137",  1433),
    ("sql6.baytexenergy.com",           "172.19.77.123",  1433),
    ("sqlbidb01yyc.baytexenergy.com",   "172.19.77.45",   1433),
    ("sqlbidb01yyc-t.baytexenergy.com", "172.19.96.44",   1433),
    ("tmwsql.baytexenergy.com",         "172.23.178.197", 1433),
    ("ora33yyc.baytexenergy.com",       "172.19.77.88",   1521),
    ("ora33yyc-t.baytexenergy.com",     "172.19.96.112",  1521),
    ("ora04yyc.baytexenergy.com",       "172.19.77.95",   1521),
    ("ora12yyc.baytexenergy.com",       "172.19.77.90",   1521),
    ("ora13yyc.baytexenergy.com",       "172.19.77.99",   1521),
    ("ora13yyc-t.baytexenergy.com",     "172.19.96.110",  1521),
    ("ora15yyc.baytexenergy.com",       "172.19.77.91",   1521),
} | set(STORAGE_ENDPOINTS)

# Attempt TCP connection to each target and print result
for host,ip, port in targets:
    try:
        with socket.create_connection((host, port), timeout=5):
            print(f"CONNECTED  {host}:{port}")
    except Exception as e:
        print(f"FAILED     {host}:{port}  ({type(e).__name__})")

# COMMAND ----------

# DBTITLE 1,Serverless egress Policy check
# MAGIC %md
# MAGIC # Serverless Egress Allowlist Validation
# MAGIC Run on **serverless compute** in a workspace bound to the network policy.
# MAGIC
# MAGIC For each destination, the notebook checks DNS, TCP, and (for 443) a TLS handshake with hostname verification.
# MAGIC A verified TLS handshake means the traffic reached the real server, not a proxy/deny page.
# MAGIC
# MAGIC - **ALLOWED** destinations should be reachable.
# MAGIC - **NOT_ALLOWED** destinations should be blocked.
# MAGIC
# MAGIC If the policy is in **dry-run / log-only** mode, everything will be reachable; check the denial log in the last cell instead.

# COMMAND ----------

import socket
import ssl
import time
from concurrent.futures import ThreadPoolExecutor

import pandas as pd
import requests

TIMEOUT = 8  # seconds per check

# Destinations in the policy allowlist: (host, port)
ALLOWED = [
    ("baytex.prodman.ca", 443),
    ("platformv2api.peloton.com", 443),
    ("auth.peloton.com", 443),
    ("api.peloton.com", 443),
    ("id.peloton.com", 443),
    ("baytex-bi.database.windows.net", 1433),
    ("api.ca.samsara.com", 443),
    ("api.samsara.com", 443),
    ("api.eu.samsara.com", 443),
    ("baytex.whitson.com", 443),
    ("internal.whitson.com", 443),
    ("whitson.eu.auth0.com", 443),
    ("app1.envirosoft.com", 443),
    ("apps.envirosoft.com", 443),
    ("gdcdata1.geologic.com", 1521),  # Oracle, not HTTPS
    ("gdcdata2.geologic.com", 1521),  # Oracle, not HTTPS
    ("api.alberta.ca", 443),
    ("api.iam.alberta.ca", 443),
    ("peloton-baytexenergy.snowflakecomputing.com", 443),
]

# Destinations NOT in the allowlist - these should be blocked
NOT_ALLOWED = [
    ("www.google.com", 443),          # generic internet
    ("github.com", 443),              # common exfil / code host
    ("raw.githubusercontent.com", 443),
    ("api.openai.com", 443),          # external API
    ("api.ipify.org", 443),           # would reveal egress IP if reachable
    ("example.com", 443),
    ("prodman.ca", 443),              # parent domain of an allowed FQDN
    ("www.alberta.ca", 443),          # sibling of allowed api.alberta.ca
    ("samsara.com", 443),             # parent domain of allowed api.samsara.com
    ("1.1.1.1", 443),                 # direct IP, bypassing DNS
]

# COMMAND ----------

def check_destination(host, port, expected):
    result = {
        "host": host,
        "port": port,
        "expected": expected,
        "dns": None,
        "resolved_ips": "",
        "tcp": None,
        "tls": None,
        "http_status": None,
        "latency_ms": None,
        "error": "",
    }
    start = time.time()

    # 1. DNS
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
        result["dns"] = True
        result["resolved_ips"] = ", ".join(sorted({i[4][0] for i in infos}))
    except Exception as e:
        result["dns"] = False
        result["error"] = f"DNS: {type(e).__name__}: {e}"

    # 2. TCP connect
    try:
        sock = socket.create_connection((host, port), timeout=TIMEOUT)
        result["tcp"] = True

        # 3. TLS handshake with hostname verification (HTTPS only)
        if port == 443:
            try:
                ctx = ssl.create_default_context()
                with ctx.wrap_socket(sock, server_hostname=host) as tls:
                    tls.getpeercert()
                result["tls"] = True
            except Exception as e:
                result["tls"] = False
                result["error"] += f" TLS: {type(e).__name__}: {e}"
        else:
            sock.close()
    except Exception as e:
        result["tcp"] = False
        result["error"] += f" TCP: {type(e).__name__}: {e}"

    # 4. HTTP request (informational - any status code means it was reachable)
    if port == 443 and result["tls"]:
        try:
            r = requests.get(f"https://{host}", timeout=TIMEOUT, allow_redirects=False)
            result["http_status"] = r.status_code
        except Exception as e:
            result["error"] += f" HTTP: {type(e).__name__}: {e}"

    result["latency_ms"] = int((time.time() - start) * 1000)

    reachable = bool(result["tcp"]) and (port != 443 or bool(result["tls"]))
    result["reachable"] = reachable
    result["verdict"] = (
        "PASS" if (expected == "ALLOW") == reachable else "FAIL"
    )
    result["error"] = result["error"].strip()[:300]
    return result


tests = [(h, p, "ALLOW") for h, p in ALLOWED] + [(h, p, "BLOCK") for h, p in NOT_ALLOWED]

with ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(lambda t: check_destination(*t), tests))

df = pd.DataFrame(results)[
    ["verdict", "expected", "reachable", "host", "port", "dns", "tcp", "tls",
     "http_status", "latency_ms", "resolved_ips", "error"]
].sort_values(["expected", "verdict", "host"])

display(df)

# COMMAND ----------

# Summary
fails = df[df["verdict"] == "FAIL"]
print(f"Total: {len(df)} | PASS: {(df['verdict'] == 'PASS').sum()} | FAIL: {len(fails)}")

allowed_unreachable = fails[fails["expected"] == "ALLOW"]
blocked_reachable = fails[fails["expected"] == "BLOCK"]

if not allowed_unreachable.empty:
    print("\nAllowed destinations that are NOT reachable (check policy entry, vendor-side firewall, or typo):")
    for _, r in allowed_unreachable.iterrows():
        print(f"  - {r['host']}:{r['port']}  -> {r['error']}")

if not blocked_reachable.empty:
    print("\nNon-allowlisted destinations that ARE reachable (policy not enforced, dry-run mode, or wrong policy bound):")
    for _, r in blocked_reachable.iterrows():
        print(f"  - {r['host']}:{r['port']}  (HTTP {r['http_status']})")

if fails.empty:
    print("\nEgress policy behaves as expected.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Denial log
# MAGIC Blocked attempts are recorded in `system.access.outbound_network` (can take several minutes to appear).
# MAGIC Blocked test hosts above should show up here; allowlisted hosts should not.

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT *
# MAGIC FROM system.access.outbound_network
# MAGIC WHERE event_time >= current_timestamp() - INTERVAL 2 HOURS
# MAGIC ORDER BY event_time DESC
# MAGIC LIMIT 200

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT event_time, access_type, destination, network_source_type, workspace_id
# MAGIC FROM system.access.outbound_network
# MAGIC WHERE event_time >= CURRENT_TIMESTAMP() - INTERVAL 2 HOUR
# MAGIC ORDER BY event_time DESC;