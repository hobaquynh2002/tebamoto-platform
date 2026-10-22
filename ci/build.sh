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
echo "G_len=${#G}"
python3 - <<'PYEOF'
import json,urllib.request,urllib.error,os
G=os.environ["G"]
def get(u):
    try: return json.load(urllib.request.urlopen(urllib.request.Request(u,headers={"Authorization":"Bearer "+G})))
    except urllib.error.HTTPError as e: return {"error":e.code,"body":e.read().decode()[:160]}
PR={"72ff278a":"63e87ab1-6bd2-4e80-92be-943450b20e4f","cost-reader":"1fe7a412-82e9-4135-ab4b-72a0be429adb","directory-audit":"696cace1-fb1c-4ef3-a9b1-e9abe1681513","reporting-service":"732dfdbc-e325-4e9f-9ca9-359af1197807","reporting-viewer":"eca94ded-76e6-4bb7-b435-40543a8c6b5f","secrets-sync":"c15570ad-5fd2-430c-97bb-a49e9a08d95c","sync-service":"70a07660-06bb-4396-b754-59fbad0b143e"}
gsp=get("https://graph.microsoft.com/v1.0/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?$select=appRoles")
roles={r["id"]:r["value"] for r in gsp.get("appRoles",[])} if isinstance(gsp,dict) and "appRoles" in gsp else {}
for name,oid in PR.items():
    print("==",name)
    ara=get("https://graph.microsoft.com/v1.0/servicePrincipals/%s/appRoleAssignments"%oid)
    if "value" in ara:
        for a in ara["value"]: print("   perm:",roles.get(a.get("appRoleId"),a.get("appRoleId")),"on",a.get("resourceDisplayName"))
    else: print("   appRoles:",ara)
    mem=get("https://graph.microsoft.com/v1.0/servicePrincipals/%s/transitiveMemberOf?$select=id,displayName"%oid)
    if "value" in mem:
        for m in mem["value"]: print("   memberOf:",m.get("displayName"),m.get("@odata.type","").split(".")[-1])
PYEOF
echo END
