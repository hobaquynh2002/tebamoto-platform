#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
js=$(curl -sS "$PROD/directory-audit-principal?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or "")')
sc=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or "")')
export G=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sc" --data-urlencode "scope=https://graph.microsoft.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
python3 - <<'PYEOF'
import json,urllib.request,urllib.error,os
G=os.environ["G"]
def get(u):
    try: return json.load(urllib.request.urlopen(urllib.request.Request(u,headers={"Authorization":"Bearer "+G})))
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:120]}
r=get("https://graph.microsoft.com/v1.0/directoryRoles")
if "value" not in r: print("roles err",r)
for role in r.get("value",[]):
    m=get("https://graph.microsoft.com/v1.0/directoryRoles/%s/members?$select=id,displayName,appId"%role["id"])
    mem=[(x.get("displayName"),x.get("appId") or x.get("id"),x.get("@odata.type","").split(".")[-1]) for x in m.get("value",[])]
    if mem: print("==",role.get("displayName")); [print("   ",x) for x in mem]
# also: app role assignments granting admin on Graph for all tbl apps
print("== unified role assignments (RoleManagement.Read may be needed) ==")
ra=get("https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$expand=principal")
if "value" in ra:
    for a in ra["value"][:50]:
        p=a.get("principal",{}); print("   role",a.get("roleDefinitionId"),"->",p.get("displayName"),p.get("@odata.type","").split(".")[-1])
else: print("   ",ra)
PYEOF
echo END
