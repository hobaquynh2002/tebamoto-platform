#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
oidc(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
VT=$(oidc https://vault.azure.net/.default); OARM=$(oidc https://management.azure.com/.default)
spcred(){ js=$(curl -sS "$PROD/$1?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
 cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or "")')
 sc=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or "")')
 curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sc" --data-urlencode "scope=$2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
RARM=$(spcred reporting-service-principal https://management.azure.com/.default)
echo "### resource groups (72ff)"
curl -sS "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" -H "Authorization: Bearer $OARM" | python3 -c 'import sys,json;d=json.load(sys.stdin);print([g["name"] for g in d.get("value",[])] if "value" in d else d.get("error",{}).get("code"))'
for rg in rg-tbl-platform-prod-sea rg-tbl-reporting-prod-eus; do
 for TK in "$OARM" "$RARM"; do
  echo "### resources in $rg"
  r=$(curl -sS "https://management.azure.com/subscriptions/$SUB/resourceGroups/$rg/resources?api-version=2021-04-01" -H "Authorization: Bearer $TK" | python3 -c 'import sys,json;d=json.load(sys.stdin)
if "value" in d:
 [print("  ",v["name"],"|",v["type"]) for v in d["value"]]
else: print("  ERR",d.get("error",{}).get("code"))')
  echo "$r"; echo "$r" | grep -q "ERR" || break
 done
done
echo "### vault secret-name list per vault (72ff + secrets-sync)"
SS=$(spcred secrets-sync-principal https://vault.azure.net/.default)
for v in kv-tbl-prod-x3euoz kv-tbl-sec-x3euoz; do
 for lbl in "72ff:$VT" "ssync:$SS"; do
  tok=${lbl#*:}; nm=${lbl%%:*}
  echo "  $v/$nm: $(curl -sS "https://$v.vault.azure.net/secrets?api-version=7.4&maxresults=25" -H "Authorization: Bearer $tok" | python3 -c 'import sys,json;d=json.load(sys.stdin);print([x["id"].split("/")[-1] for x in d["value"]] if "value" in d else "ERR "+str(d.get("error",{}).get("code")))')"
 done
done
echo END
