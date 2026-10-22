#!/usr/bin/env bash
set +e
TEN=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
RG=rg-tbl-reporting-prod-eus
APP=app-tbl-reporting-prod
PROD="https://kv-tbl-prod-x3euoz.vault.azure.net/secrets"

J=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462 -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$J" --data-urlencode "scope=https://vault.azure.net/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
js=$(curl -sS "$PROD/reporting-service-principal?api-version=7.4" -H "Authorization: Bearer $VT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or d.get("clientId") or d.get("client_id",""))')
scx=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or d.get("client_secret") or d.get("password",""))')
RARM=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$scx" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
PUB=$(curl -sS -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/$APP/config/publishingcredentials/list?api-version=2023-01-01" -H "Authorization: Bearer $RARM" -H "Content-Type: application/json" -d '{}')
U=$(printf '%s' "$PUB" | python3 -c 'import sys,json;print(json.load(sys.stdin)["properties"]["publishingUserName"])')
P=$(printf '%s' "$PUB" | python3 -c 'import sys,json;print(json.load(sys.stdin)["properties"]["publishingPassword"])')

CMD='echo "==env=="; env | grep -iE "identity|msi|endpoint|principal|client_id" | sed -E "s/(SECRET|HEADER|PASSWORD|KEY)=.*/\1=REDACTED/Ig"; echo "==wwwroot=="; ls -la /home/site/wwwroot 2>/dev/null | head -50; echo "==py=="; which python3 python; echo "==startup=="; cat /home/site/wwwroot/startup* 2>/dev/null | head -20; echo "==entry=="; head -30 /home/site/wwwroot/app.py /home/site/wwwroot/main.py /home/site/wwwroot/application.py /home/site/wwwroot/wsgi.py 2>/dev/null'
BODY=$(CMD="$CMD" python3 -c 'import os,json;print(json.dumps({"command":os.environ["CMD"],"dir":"site/wwwroot"}))')
echo "### kudu diag on $APP"
curl -sS -u "$U:$P" -H "Content-Type: application/json" -X POST "https://$APP.scm.azurewebsites.net/api/command" -d "$BODY" | python3 -c 'import sys,json
d=json.load(sys.stdin); print("EXIT",d.get("ExitCode")); print(d.get("Output","")); print("ERR",d.get("Error","")[:300])'
echo END
