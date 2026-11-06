#!/usr/bin/env bash
# wave-sec-scan.sh — WAVE's OWN security lint (the internal Aikido). One script, every pattern:
#   P1 raw PANs near stripe calls        (the stripe-tokenization-only law — handled by the raw-PAN gate)
#   P2 hardcoded secret assignments
#   P3 secrets in query strings          (move to headers)
#   P5 non-timing-safe secret compares   (advisory)
# Fail-closed with the exit classified; the file-level context = the same as the PAN gate.
set -uo pipefail
FAIL=0
HARD=$(grep -rIEn "(sk_(live|test)_[A-Za-z0-9]{16,}[[:space:]]*=[[:space:]]*['\"]|password[[:space:]]*=[[:space:]]*['\"][^'\"]{8,}|api_secret[[:space:]]*=[[:space:]]*['\"][A-Za-z0-9]{16,})" \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' --include='*.py' \
  --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=staging --exclude-dir=docs \
  . 2>/dev/null | grep -viE 'test|spec|fixture|mock|example' | head -20)
if [ -n "$HARD" ]; then echo "::error::wave-sec P2: hardcoded secret assignments:"; echo "$HARD"; FAIL=1; fi
QS=$(grep -rIEn "https?://[^'\"]*(token|api_key|apikey|secret|password)=[A-Za-z0-9]{8,}" \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' --include='*.py' \
  --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=staging --exclude-dir=docs \
  . 2>/dev/null | grep -viE 'test|spec|fixture|mock|example' | head -20)
if [ -n "$QS" ]; then echo "::error::wave-sec P3: secrets in query strings (move to headers):"; echo "$QS"; FAIL=1; fi
EQ=$(grep -rIEn "(token|secret|apikey|api_key|signature)[[:space:]]*===?[[:space:]]*[a-zA-Z_]" \
  --include='*.ts' --include='*.js' --include='*.mjs' \
  --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=staging --exclude-dir=docs \
  . 2>/dev/null | grep -viE 'test|spec|fixture|mock|=== null|=== undefined' | head -20)
if [ -n "$EQ" ]; then echo "::warning::wave-sec P5 (advisory): possible non-timing-safe secret compares (use a constant-time compare):"; echo "$EQ"; fi
if [ "$FAIL" -eq 1 ]; then echo "::error::wave-sec-scan FAILED — fix the patterns above (the tokenization-plane laws)."; exit 1; fi
echo "wave-sec-scan clean (P1 = the raw-PAN gate; P4 = the E3 signing gate, pending)"
