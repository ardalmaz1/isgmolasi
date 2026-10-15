#!/bin/sh
# Fails when the repository contains an API key, secret token or a hosted AI model endpoint.
# Relive's editorial intelligence is on-device only (docs/EDITORIAL_INTELLIGENCE.md).
set -u
cd "$(dirname "$0")/.."
PATTERNS='sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{10,}|AIza[0-9A-Za-z_-]{35}|ghp_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|api\.openai\.com|api\.anthropic\.com|generativelanguage\.googleapis\.com|firebasevertexai|aiplatform\.googleapis\.com|OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY'
FOUND="$(grep -rInE "$PATTERNS" --exclude-dir=.git --exclude-dir=build --exclude='check-no-secrets.sh' --exclude='*.md' . || true)"
if [ -n "$FOUND" ]; then
  echo "Possible secret or remote model endpoint:"
  echo "$FOUND" | cut -d: -f1,2
  exit 1
fi
echo "No secrets or remote model endpoints found."
