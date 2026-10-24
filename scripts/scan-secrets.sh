#!/usr/bin/env bash
# Looks for secret-like strings in a file, usually meeting minutes, before anyone shares or commits them.
#
#   scan-secrets.sh <file>
#
# Prints one line per hit (line number and the kind of secret, never the value).
# Exit 0 when nothing is found, 1 when something is. Pattern-based: it catches common formats, not all secrets.
set -euo pipefail

file=${1:?file}
hits=0
check() {
  local kind=$1 pattern=$2 n
  while IFS= read -r n; do
    echo "SECRET? line $n: $kind"; hits=$((hits + 1))
  done < <(grep -nE -- "$pattern" "$file" | cut -d: -f1 || true)
}

check "private key"            '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
check "AWS access key"         'AKIA[0-9A-Z]{16}'
check "OpenAI/Anthropic key"   'sk-(ant-|proj-)?[A-Za-z0-9_-]{20,}'
check "GitHub token"           '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}'
check "Slack token"            'xox[abprs]-[A-Za-z0-9-]{10,}'
check "Google API key"         'AIza[0-9A-Za-z_-]{35}'
check "Stripe key"             '(sk|rk)_live_[0-9A-Za-z]{20,}'
check "JWT"                    'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
check "credential in URL"      '[a-z]+://[^/[:space:]:@]+:[^/[:space:]@]+@'
check "assigned secret"        '(api[_-]?key|secret|token|password|passwd)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]]{12,}["'"'"']'

echo "secret scan: $hits possible secrets"
[ "$hits" -eq 0 ]
