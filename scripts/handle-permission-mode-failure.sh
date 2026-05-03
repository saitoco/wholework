#!/bin/bash
# handle-permission-mode-failure.sh
# Diagnose permission-mode auto failures and suggest remediation.
# Args: exit_code elapsed permission_mode
# Always exits 0; prints diagnostic to stderr on heuristic match only.
# Heuristic: permission_mode=auto AND exit_code!=0 AND elapsed<=30

exit_code="${1:-0}"
elapsed="${2:-0}"
permission_mode="${3:-}"

if [ "$permission_mode" = "auto" ] && [ "$exit_code" != "0" ] && [ "$elapsed" -le 30 ]; then
  cat >&2 <<'EOF'
Note: /auto failed with permission-mode: auto.
This requires Claude Max / Team / Enterprise / API plan (Pro is not supported).
If your plan does not support auto mode, switch to bypass by adding to .wholework.yml:
  permission-mode: bypass
See SECURITY.md for the security tradeoff.
EOF
fi

exit 0
