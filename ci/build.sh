#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
PV=https://kv-tbl-prod-x3euoz.vault.azure.net
SV=https://kv-tbl-sec-x3euoz.vault.azure.net
PROD="$PV/secrets"
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
oidc(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
VT=$(oidc https://vault.azure.net/.default)
names(){ curl -sS "$1/secrets?api-version=7.4&maxresults=25" -H "Authorization: Bearer $2" | python3 -c 'import sys,json
d=json.load(sys.stdin)
print([x["id"].split("/")[-1] for x in d["value"]] if "value" in d else ("ERR "+str(d.get("error",{}).get("code"))))'; }
echo "prod/72ff278a: $(names $PV $VT)"
echo "sec /72ff278a: $(names $SV $VT)"
decl(){ js=$(curl -sS "$PROD/$1-principal?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
 cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or "")')
 sc=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or "")')
 curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sc" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
for s in secrets-sync sync-service directory-audit reporting-service reporting-viewer cost-reader; do
  t=$(decl "$s"); echo "prod/$s: $(names $PV $t)"; echo "sec /$s: $(names $SV $t)"
done
echo END
