# Databricks notebook source
# ----------------------------------------------------------------------------------------------------------------------
# Baytex Azure Databricks connectivity check
#
# Run the whole notebook once on serverless compute and once on a classic cluster in the workspace.
# It reports what each kind of compute can reach, and which network path the traffic took.
#
# The two kinds of compute leave the platform differently, so the expected results differ:
#
#   On-premises destinations  serverless goes through the NCC private endpoint, the Private Link Service, the load
#                             balancer and HAProxy, so the destination sees the proxy subnet as the source.
#                             Classic compute routes straight out of its own subnet to the firewall, so the destination
#                             sees the Databricks subnet as the source.
#   Internet destinations     serverless is limited to the account network policy's allow list, so anything outside it
#                             fails. Classic compute leaves through the NAT Gateway, and the network security group
#                             rules record the approved destinations without restricting anything, so everything
#                             succeeds.
#
# Nothing outside the Python standard library is used, and nothing is written anywhere.
# ----------------------------------------------------------------------------------------------------------------------

import socket
import ssl
import sys
import time

# ----------------------------------------------------------------------------------------------------------------------
# Configuration
# Replace this block for a different environment; everything below it is generic.
# ----------------------------------------------------------------------------------------------------------------------

STORAGE_ACCOUNT = "stvkpdbxdevcnc001"

# The approved on-premises destinations, by the name serverless compute uses to reach them.
ON_PREM = [
    ("sqlbidb01yyc", "sqlbidb01yyc.baytexenergy.com", 1433),
    ("sqlbidb01yyc_t", "sqlbidb01yyc-t.baytexenergy.com", 1433),
    ("sql14yyc", "sql14yyc.baytexenergy.com", 1433),
    ("sql6", "sql6.baytexenergy.com", 1433),
    ("ora33yyc", "ora33yyc.baytexenergy.com", 1521),
    ("ora33yyc_t", "ora33yyc-t.baytexenergy.com", 1521),
    ("trimble_sql", "btx-sql01.trimble.vpn", 1433),
]

# The destinations the serverless network policy allows. Every one of these should succeed on serverless.
ALLOWED_INTERNET = [
    "baytex.prodman.ca",
    "platformv2api.peloton.com",
    "baytex-bi.database.windows.net",
    "api.ca.samsara.com",
    "api.samsara.com",
    "api.eu.samsara.com",
    "baytex.whitson.com",
    "whitson.eu.auth0.com",
    "app1.envirosoft.com",
    "apps.envirosoft.com",
    "gdcdata1.geologic.com",
    "api.alberta.ca",
]

# Destinations deliberately absent from the allow list.
# Serverless should fail to reach these, which is what proves the policy is enforced rather than only recorded.
BLOCKED_INTERNET = ["example.com", "www.wikipedia.org"]

TIMEOUT = 8

# The run labels itself from the Spark configuration. Set this to "serverless" or "classic" if that lookup is
# unavailable and the summary reports the compute as unknown.
COMPUTE_KIND_OVERRIDE = ""

# ----------------------------------------------------------------------------------------------------------------------
# Probes
# ----------------------------------------------------------------------------------------------------------------------


def resolve(host):
    """Returns the first address the name resolves to, or the reason it did not resolve."""
    try:
        return socket.gethostbyname(host), None
    except OSError as error:
        return None, type(error).__name__


def tcp_probe(host, port, read_banner=False):
    """Opens a TCP connection and optionally reads whatever the destination sends first."""
    started = time.time()
    try:
        with socket.create_connection((host, port), timeout=TIMEOUT) as connection:
            banner = ""
            if read_banner:
                connection.settimeout(3)
                try:
                    banner = connection.recv(200).decode("utf-8", "replace").strip()
                except OSError:
                    banner = ""
            return True, banner, time.time() - started, None
    except Exception as error:  # noqa: BLE001 - every failure mode is reported rather than raised
        return False, "", time.time() - started, type(error).__name__


def tls_probe(host, port=443):
    """Completes a TLS handshake, which shows the destination is reachable and is the host it claims to be."""
    started = time.time()
    context = ssl.create_default_context()
    try:
        with socket.create_connection((host, port), timeout=TIMEOUT) as raw:
            with context.wrap_socket(raw, server_hostname=host):
                return True, time.time() - started, None
    except Exception as error:  # noqa: BLE001
        return False, time.time() - started, type(error).__name__


def local_addresses():
    """Best effort view of the address this compute uses, which differs between serverless and classic."""
    found = []
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("168.63.129.16", 80))
            found.append(probe.getsockname()[0])
    except OSError:
        pass
    try:
        found.append(socket.gethostbyname(socket.gethostname()))
    except OSError:
        pass
    return sorted(set(found))


def compute_kind():
    """Labels the run. Serverless exposes no cluster id, so its absence is the signal."""
    if COMPUTE_KIND_OVERRIDE:
        return COMPUTE_KIND_OVERRIDE
    try:
        spark_session = spark  # noqa: F821 - provided by the notebook
        cluster_id = spark_session.conf.get("spark.databricks.clusterUsageTags.clusterId", "")
        return "classic" if cluster_id else "serverless"
    except Exception:  # noqa: BLE001
        return "unknown"


# ----------------------------------------------------------------------------------------------------------------------
# Run
# ----------------------------------------------------------------------------------------------------------------------

kind = compute_kind()
print("=" * 108)
print("Baytex Databricks connectivity check")
print(f"compute      : {kind}")
print(f"addresses    : {', '.join(local_addresses()) or 'not visible'}")
print(f"python       : {sys.version.split()[0]}")
print("=" * 108)

results = {"pass": 0, "fail": 0, "unexpected": 0}


def record(ok, expected_ok):
    if ok == expected_ok:
        results["pass"] += 1
        return "OK"
    results["fail"] += 1
    results["unexpected"] += 1
    return "UNEXPECTED"


# --- On-premises destinations -----------------------------------------------------------------------------------------
# The listeners in the sandbox answer with the address they were reached on and the address they saw the call come from,
# which is what identifies the path. A real SQL Server or Oracle sends nothing until the client speaks, so an empty
# banner against a real destination is still a pass.
print("\nON-PREMISES DESTINATIONS  (expected: reachable from both serverless and classic)")
print("-" * 108)
print(f"{'name':16} {'destination':34} {'port':>5}  {'resolved':16} {'result':10} {'seen by destination'}")
for name, host, port in ON_PREM:
    address, dns_error = resolve(host)
    if address is None:
        record(False, True)
        print(f"{name:16} {host:34} {port:>5}  {'-':16} {'DNS FAIL':10} {dns_error}")
        continue
    ok, banner, seconds, error = tcp_probe(host, port, read_banner=True)
    verdict = record(ok, True)
    detail = banner if banner else (error or f"{seconds:.2f}s")
    print(f"{name:16} {host:34} {port:>5}  {address:16} {verdict:10} {detail}")

# --- Data storage -----------------------------------------------------------------------------------------------------
# Serverless reaches the account through its NCC private endpoint rules and classic compute through the private
# endpoints in the spoke, so both resolve to a private address and both connect.
print("\nDATA STORAGE  (expected: reachable privately from both)")
print("-" * 108)
for suffix in ("dfs", "blob"):
    host = f"{STORAGE_ACCOUNT}.{suffix}.core.windows.net"
    address, dns_error = resolve(host)
    if address is None:
        record(False, True)
        print(f"{suffix:6} {host:52} DNS FAIL   {dns_error}")
        continue
    private = address.startswith(("10.", "172.", "192.168."))
    ok, seconds, error = tls_probe(host)
    verdict = record(ok, True)
    print(f"{suffix:6} {host:52} {verdict:10} {address} ({'private' if private else 'PUBLIC'}) {error or f'{seconds:.2f}s'}")

# --- Approved internet destinations -----------------------------------------------------------------------------------
print("\nAPPROVED INTERNET DESTINATIONS  (expected: reachable from both)")
print("-" * 108)
for host in ALLOWED_INTERNET:
    ok, seconds, error = tls_probe(host)
    verdict = record(ok, True)
    print(f"{host:44} {verdict:10} {error or f'{seconds:.2f}s'}")

# --- Destinations outside the allow list ------------------------------------------------------------------------------
# This is the section that tells the two kinds of compute apart.
expect_reachable = kind != "serverless"
print("\nDESTINATIONS OUTSIDE THE ALLOW LIST")
print(f"  expected on serverless : blocked, because the network policy is enforced")
print(f"  expected on classic    : reachable, because the rules record destinations without restricting them")
print("-" * 108)
for host in BLOCKED_INTERNET:
    ok, seconds, error = tls_probe(host)
    verdict = record(ok, expect_reachable)
    state = "reachable" if ok else f"blocked ({error})"
    print(f"{host:44} {verdict:10} {state}")

# --- Summary ----------------------------------------------------------------------------------------------------------
print("\n" + "=" * 108)
print(f"checks passed: {results['pass']}    unexpected: {results['unexpected']}")
if results["unexpected"] == 0:
    print(f"RESULT: every check matched what is expected on {kind} compute.")
else:
    print(f"RESULT: {results['unexpected']} check(s) did not match what is expected on {kind} compute. See the rows marked UNEXPECTED.")
print("=" * 108)
