#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
RG=rg-tbl-platform-prod-sea
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
oidc(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
VT=$(oidc https://vault.azure.net/.default); OARM=$(oidc https://management.azure.com/.default)
spcred(){ js=$(curl -sS "$PROD/$1?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
 cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or "")')
 sc=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or "")')
 curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sc" --data-urlencode "scope=$2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
CR=$(spcred cost-reader-principal https://management.azure.com/.default)
SSV=$(spcred sync-service-principal https://management.azure.com/.default)
for sa in sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
  for lbl in "72ff:$OARM" "costreader:$CR" "syncservice:$SSV"; do
    nm=${lbl%%:*}; tok=${lbl#*:}
    r=$(curl -sS -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$sa/listKeys?api-version=2023-01-01" -H "Authorization: Bearer $tok" -H "Content-Length: 0" | python3 -c 'import sys,json
d=json.load(sys.stdin); ks=d.get("keys")
print("KEY_OK(len%d)"%len(ks[0]["value"]) if ks else "ERR "+str(d.get("error",{}).get("code")))')
    echo "  $sa / $nm: $r"
  done
done
echo END
