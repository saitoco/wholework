# Bridge File for L3 Session Retrospective

This file mirrors the `## Auto Retrospective > ### Improvement Proposals` section from `session.md` for compatibility with `modules/retro-proposals.md`.

## Auto Retrospective

### Improvement Proposals

- `run-auto-sub.sh` が patch route で生成する orphan spec stub `docs/spec/issue-N-code.md` を、Issue title 由来の kebab-case ファイル名 (`issue-N-<short-title>.md`) で作成するか、Consumed Comments のみであれば作成自体をスキップする。現状は 11 件中 4 件で手動 rename + commit を要した。
- `append-loop-state-heartbeat.sh` の呼び出し後に、heartbeat 差分を auto-commit + push する (best-effort)。これにより `check-verify-dirty.sh` が verify 直前で exit 1 になるのを回避し、batch の friction が解消される。
- `append-loop-state-heartbeat.sh` で同一 (issue, from→to, snapshot) の組合せが直前行と一致する場合は append をスキップする。重複行は機械可読性を損ねる。
