import json
import os
import urllib.error
import urllib.request
import uuid

BASE_URL = "https://kfzfzarslqdqmrazohej.supabase.co"
KEY = os.environ.get("OI_SUPABASE_PUBLISHABLE_KEY", "")
if not KEY or KEY.startswith("sb_secret_"):
    raise SystemExit("Set OI_SUPABASE_PUBLISHABLE_KEY to the project's public client key")


def request(path, method="GET", body=None, content_type="application/json"):
    headers = {"apikey": KEY, "Content-Type": content_type}
    if KEY.startswith("ey"):
        headers["Authorization"] = "Bearer " + KEY
    query = urllib.request.Request(BASE_URL + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(query, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


for table in ["oi_stories", "oi_profiles", "oi_regions", "oi_schools", "oi_story_media"]:
    status, raw = request("/rest/v1/" + table + "?select=*&limit=10")
    assert status == 200, (table, status)
    rows = json.loads(raw)
    assert isinstance(rows, list)
    if table == "oi_stories":
        assert all(row["status"] == "published" for row in rows)
    if table == "oi_profiles":
        assert all(not ({"phone", "email", "contact_email", "full_name"} & row.keys()) for row in rows)
    print("PASS: anonymous authorized read", table)

for table in ["users", "oi_evidence_requests", "oi_writing_grants", "oi_collections", "oi_favorites", "oi_evidence_history"]:
    status, _ = request("/rest/v1/" + table + "?select=*&limit=1")
    assert status in (401, 403), (table, status)
    print("PASS: anonymous private table denied", table)

status, raw = request("/rest/v1/rpc/oi_mutate", "POST", json.dumps({
    "p_action": "start_evidence", "p_payload": {"id": str(uuid.uuid4())}
}).encode())
assert status in (401, 403), ("anonymous RPC", status)
print("PASS: anonymous mutation denied")

status, raw = request("/rest/v1/rpc/oi_collection_metrics?limit=10", "POST", b"{}")
assert status == 200 and isinstance(json.loads(raw), list)
print("PASS: public aggregate endpoint")

status, raw = request("/auth/v1/settings")
assert status == 200 and json.loads(raw)["external"]["google"] is True
print("PASS: existing Google provider enabled")
