#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
dump(){ curl -sS "$1" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json
d=json.load(sys.stdin)
if "value" in d: print([ (x.get("id") or x.get("kid","")).split("/")[-1] for x in d["value"]])
else: print("ERR",d.get("error",{}).get("code"))'; }
for v in kv-tbl-prod-x3euoz kv-tbl-sec-x3euoz; do
  B="https://$v.vault.azure.net"
  echo "$v /keys:        $(dump "$B/keys?api-version=7.4")"
  echo "$v /certificates:$(dump "$B/certificates?api-version=7.4")"
  echo "$v /deletedsecrets: $(dump "$B/deletedsecrets?api-version=7.4")"
  echo "$v /deletedkeys: $(dump "$B/deletedkeys?api-version=7.4")"
done
echo "### full secret JSON (tags?) for the 6 in prod"
for n in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  echo "-- $n tags/attrs: $(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$n?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("tags=",d.get("tags"),"ctype=",d.get("contentType"))')"
done
echo END
