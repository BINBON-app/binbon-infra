#!/usr/bin/env python3
"""Quick post-migration check: list tables in binbon_analytics."""
import base64
import json
import subprocess
import sys
import urllib.request

secret_id, region, https_url = sys.argv[1], sys.argv[2], sys.argv[3]

raw = subprocess.check_output(
    ["aws", "secretsmanager", "get-secret-value", "--secret-id", secret_id,
     "--region", region, "--query", "SecretString", "--output", "text"]
)
secret = json.loads(raw)
user, password = secret["CLICKHOUSE_USER"], secret["CLICKHOUSE_PASSWORD"]

auth = base64.b64encode(f"{user}:{password}".encode()).decode()
req = urllib.request.Request(
    https_url + "/",
    data=b"SHOW TABLES FROM binbon_analytics",
    headers={"Authorization": f"Basic {auth}"},
)
with urllib.request.urlopen(req, timeout=10) as resp:
    print(resp.read().decode())
