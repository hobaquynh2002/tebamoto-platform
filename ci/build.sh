#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
OWNER=d2cdf247-9319-40cb-8324-5a005ef538da

J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
tok() { curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
ARM=$(tok https://management.azure.com/.default)
GRAPH=$(tok https://graph.microsoft.com/.default)

echo "### Graph: who is $OWNER"
curl -sS "https://graph.microsoft.com/v1.0/servicePrincipals/$OWNER?\$select=displayName,appId,servicePrincipalType,alternativeNames" -H "Authorization: Bearer $GRAPH" | head -c 700; echo

echo "### user-assigned identities"
curl -sS "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.ManagedIdentity/userAssignedIdentities?api-version=2023-01-31" -H "Authorization: Bearer $ARM" | python3 -c 'import sys,json
d=json.load(sys.stdin)
for v in d.get("value",[]):
 p=v.get("properties",{}); print(v.get("name"),"|",p.get("principalId"),"|",p.get("clientId"))' 2>/dev/null

echo "### all resources with an identity (name | type | principalId | userAssigned-ids)"
curl -sS "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01&\$expand=identity" -H "Authorization: Bearer $ARM" | python3 -c 'import sys,json
d=json.load(sys.stdin)
for v in d.get("value",[]):
 idd=v.get("identity") or {}
 pid=idd.get("principalId"); ua=list((idd.get("userAssignedIdentities") or {}).keys())
 if pid or ua: print(v.get("name"),"|",v.get("type"),"|",pid,"|",ua)' 2>/dev/null

echo "### MATCH for $OWNER ^ (grep above)"
echo END
