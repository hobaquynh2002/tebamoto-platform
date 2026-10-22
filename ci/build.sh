#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
spcred(){ js=$(curl -sS "$PROD/$1?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
 cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or "")')
 sc=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or "")')
 curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sc" --data-urlencode "scope=$2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
RARM=$(spcred reporting-service-principal https://management.azure.com/.default)
echo "### role assignments @ rg-tbl-reporting-prod-eus"
curl -sS "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" -H "Authorization: Bearer $RARM" | python3 -c '
import sys,json
M={"8e3af657-a8ff-443c-a75c-2fe8c4bcb635":"Owner","b24988ac-6180-42a0-ab88-20f7382dd24c":"Contributor","acdd72a7-3385-48ef-bd42-f606fba81ae7":"Reader","18d7d88d-d35e-4fb5-a5c3-7773c20a72d9":"UAA","00482a5a-887f-4fb3-b363-3b7fe8e74483":"KV-Admin","b86a8fe4-44ce-4948-aee5-eccb2c155cd7":"KV-SecretsOfficer","4633458b-17de-408a-b874-0445c86b69e6":"KV-SecretsUser","ba92f5b4-2d11-453d-a403-e96b0029c9fe":"BlobDataContributor","2a2b9908-6ea1-4ae2-8e65-a410df84e7d1":"BlobDataReader","17d1049b-9a84-46fb-8f53-869881c3d3ab":"StorageAcctContrib"}
d=json.load(sys.stdin)
if "value" not in d: print("  ERR",d.get("error",{}).get("code")); sys.exit()
for ra in d["value"]:
 p=ra["properties"]; rid=p.get("roleDefinitionId","").split("/")[-1]
 print("  ",p.get("principalId"),"|",M.get(rid,rid[:8]),"|",p.get("principalType"),"|",".../"+p.get("scope","").split("/")[-1])'
export G=$(spcred directory-audit-principal https://graph.microsoft.com/.default)
python3 - <<'PYEOF'
import json,urllib.request,urllib.parse,urllib.error,os
G=os.environ["G"]
def get(u):
    try: return json.load(urllib.request.urlopen(urllib.request.Request(u,headers={"Authorization":"Bearer "+G})))
    except urllib.error.HTTPError as e: return {"error":e.code}
gsp=get("https://graph.microsoft.com/v1.0/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?$select=appRoles")
roles={r["id"]:r["value"] for r in gsp.get("appRoles",[])} if "appRoles" in gsp else {}
for nm in ["tbl-cicd-deployer","tbl-directory-sync","tbl-reporting-insights","tbl-legacy-admin"]:
    sp=get("https://graph.microsoft.com/v1.0/servicePrincipals?$filter="+urllib.parse.quote("displayName eq '%s'"%nm)+"&$select=id,appId")
    for s in sp.get("value",[]):
        oid=s["id"]; print("==",nm,"appId",s.get("appId"))
        ara=get("https://graph.microsoft.com/v1.0/servicePrincipals/%s/appRoleAssignments"%oid)
        for a in ara.get("value",[]): print("   perm:",roles.get(a.get("appRoleId"),a.get("appRoleId")),"on",a.get("resourceDisplayName"))
PYEOF
echo END
