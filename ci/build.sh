#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
RG=rg-tbl-reporting-prod-eus
APP=app-tbl-reporting-prod
MIID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tbl-reporting-writer"
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"

J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
sp_tok() {
  js=$(curl -sS "$PROD/$1?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
  cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or d.get("clientId") or d.get("client_id",""))' 2>/dev/null)
  sc=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or d.get("client_secret") or d.get("password",""))' 2>/dev/null)
  curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sc" --data-urlencode "scope=$2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'
}
RARM=$(sp_tok reporting-service-principal https://management.azure.com/.default)

echo "### MI id-tbl-reporting-writer (expect principalId=d2cdf247...)"
curl -sS "https://management.azure.com$MIID?api-version=2023-01-31" -H "Authorization: Bearer $RARM" | python3 -c 'import sys,json;d=json.load(sys.stdin);p=d.get("properties",{});print("principalId=",p.get("principalId")," clientId=",p.get("clientId"))' 2>/dev/null

echo "### publishing-creds access to $APP, per SP"
for s in reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal cost-reader-principal directory-audit-principal; do
  a=$(sp_tok "$s" https://management.azure.com/.default)
  pub=$(curl -sS -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/$APP/config/publishingcredentials/list?api-version=2023-01-01" -H "Authorization: Bearer $a" -H "Content-Type: application/json" -d '{}')
  u=$(printf '%s' "$pub" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("properties",{}).get("publishingUserName",""))' 2>/dev/null)
  echo "-- $s: creds=$([ -n "$u" ] && echo PRESENT || echo no) | $(printf '%s' "$pub" | tr -d '\n' | head -c 110)"
done
echo END
