#!/bin/bash
# handle-permission-mode-failure.sh
# Diagnose likely permission-mode auto failures and suggest remediation.
# Args: exit_code elapsed
# Always exits 0; prints diagnostic to stderr on heuristic match only.
# Heuristic: exit_code!=0 AND elapsed<=30

exit_code="${1:-0}"
elapsed="${2:-0}"

if [ "$exit_code" != "0" ] && [ "$elapsed" -le 30 ]; then
  cat >&2 <<'EOF'
Note: /auto exited early, possibly due to a permission-mode auto classifier block.
Apply the recommended allow rules template (docs/guide/auto-mode-template.json) to
.claude/settings.local.json and restart Claude Code. See SECURITY.md for details.
EOF
fi

exit 0
