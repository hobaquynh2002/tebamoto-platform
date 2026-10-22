#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
ARM=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
js=$(curl -sS "$PROD/directory-audit-principal?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or "")')
sc=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or "")')
export G=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$sc" --data-urlencode "scope=https://graph.microsoft.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
export ARM VT SUB
python3 - <<'PYEOF'
import json,urllib.request,urllib.parse,urllib.error,os
G=os.environ["G"]; ARM=os.environ["ARM"]; SUB=os.environ["SUB"]
def q(u,tok):
    try: return json.load(urllib.request.urlopen(urllib.request.Request(u,headers={"Authorization":"Bearer "+tok})))
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:160]}
for nm in ["tbl-legacy-admin","tbl-platform-automation"]:
    print("==",nm)
    sp=q("https://graph.microsoft.com/v1.0/servicePrincipals?$filter="+urllib.parse.quote("displayName eq '%s'"%nm)+"&$select=id,appId,displayName",G)
    for s in sp.get("value",[]):
        oid=s["id"]; print("   SP oid=",oid," appId=",s.get("appId"))
        for scope in ["subscriptions/%s"%SUB]:
            ra=q("https://management.azure.com/%s/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&$filter="%scope+urllib.parse.quote("principalId eq '%s'"%oid),ARM)
            if "value" in ra:
                for r in ra["value"]: print("     role:",r["properties"].get("roleDefinitionId","").split("/")[-1],"@",r["properties"].get("scope"))
            else: print("     ra:",ra)
    if "error" in sp: print("   sp:",sp)
PYEOF
echo END
