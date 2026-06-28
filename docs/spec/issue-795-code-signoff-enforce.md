# Issue #795: code: /code skill が生成する全 commit に Signed-off-by を自動付与

## Overview

`/code` skill が生成する全 commit への `Signed-off-by` 自動付与。
Issue #783 で SKILL.md ガイダンスのみでは不十分と判明したため、2 層で対策する:

1. **SKILL.md ガイダンス強化** — Step 8 (実装ステップ) に全 commit への `-s` 必須を明示追記 (Step 11/12 だけでなく Step 8 の中間 commit も対象)
2. **run-code.sh bash チェック追加** — `claude -p` 完了後に新規 commit の `Signed-off-by` 欠落を bash レベルで検出し警告出力

## Changed Files

- `skills/code/SKILL.md`: Step 8 "Implement" セクションに DCO compliance bullet 追加 ("全 commit に `git commit -s` を使用" を明示)
- `scripts/run-code.sh`: (a) `claude -p` 実行前に `_PRE_HEAD` 記録、(b) EXIT_CODE=0 後に `Signed-off-by` 欠落検出チェック追加 — bash 3.2+ 互換
- `tests/run-code.bats`: Signed-off-by 検出ロジック用テスト 2 件追加

## Implementation Steps

1. `skills/code/SKILL.md` の Step 8 "Implement" セクション内、"Commit after each step completes" 行の直前に以下 bullet を挿入 (→ AC1, AC5):
   ```
   - **DCO: always use `git commit -s` (--signoff)** — applies to all commits throughout this skill: Step 8 intermediate commits, Step 11 final commit, and Step 12 retrospective commit
   ```
   挿入位置: `- Use TaskCreate/TaskUpdate to manage tasks while working` の次行、`- Commit after each step completes` の前。

2. `scripts/run-code.sh` — 2 箇所の変更 (→ AC3):
   - (a) `SECONDS=0` 行の直前に `_PRE_HEAD=$(git rev-parse HEAD 2>/dev/null || true)` を追加
   - (b) `append-loop-state-heartbeat.sh` ブロック後に Signed-off-by 検出チェックを追加:
     ```bash
     # bash-level post-execution Signed-off-by detection (safety net for DCO compliance)
     if [[ $EXIT_CODE -eq 0 && -n "${_PRE_HEAD:-}" ]]; then
       _new_commits=$(git log "${_PRE_HEAD}..HEAD" --format='%H' 2>/dev/null || true)
       if [[ -n "$_new_commits" ]]; then
         _missing_sob=""
         while IFS= read -r _h; do
           if ! git log -1 --format='%B' "$_h" 2>/dev/null | grep -q "^Signed-off-by:"; then
             _missing_sob="${_missing_sob}${_missing_sob:+ }${_h}"
           fi
         done <<< "$_new_commits"
         if [[ -n "$_missing_sob" ]]; then
           echo "Warning: Signed-off-by missing in commits — DCO check may fail: ${_missing_sob}" >&2
         fi
       fi
     fi
     ```

3. `tests/run-code.bats` — 以下 2 テストをファイル末尾に追加 (→ AC7):

   テスト (a): `signoff check: warning emitted when new commit missing Signed-off-by after code phase`
   - mock git: `rev-parse HEAD` → `"aaaa000..."`, `log "aaaa000...HEAD" --format=%H` → `"bbbb111..."`, `log -1 --format=%B "bbbb111..."` → Signed-off-by なしのコミットメッセージ
   - `run bash "$SCRIPT" 123`
   - `[ "$status" -eq 0 ]`
   - `[[ "$output" == *"Warning:"*"Signed-off-by"* ]]`

   テスト (b): `signoff check: no warning when all new commits have Signed-off-by`
   - mock git: `log -1 --format=%B` で `Signed-off-by: User <user@example.com>` を返す
   - `run bash "$SCRIPT" 123`
   - `[ "$status" -eq 0 ]`
   - `[[ "$output" != *"Warning:"*"Signed-off-by"* ]]`

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md の全 git commit 生成箇所で -s (--signoff) が必ず使われる仕組みが skill ガイダンスとして明示されており、かつ scripts/run-code.sh に claude -p 完了後の Signed-off-by 欠落を bash レベルで検出するチェックが追加されている (skill ガイダンス + script 実装の両層)" --> code skill が全 commit に -s を付与し、run-code.sh が後段でも bash レベルで検証する
- <!-- verify: file_contains "skills/code/SKILL.md" "git commit -s" --> SKILL.md に `git commit -s` が含まれる (rubric 補完チェック)
- <!-- verify: grep "Signed-off-by" "scripts/run-code.sh" --> run-code.sh に Signed-off-by 検証チェックが追加されている (rubric 補完チェック)
- <!-- verify: grep "commit.*-s|--signoff" "skills/code/SKILL.md" --> code SKILL.md に -s/--signoff 言及がある
- <!-- verify: rubric "Spec で個別に -s を指示することなく、code skill 経由の全 commit に Signed-off-by が付与される" --> Spec 側での明示記述なしに DCO compliance が保証される
- <!-- verify: file_contains "skills/code/SKILL.md" "Signed-off-by:" --> SKILL.md に sign-off 検証アサーションが含まれる (rubric 補完チェック)
- <!-- verify: command "bats tests/run-code.bats" --> run-code.bats テストが全 PASS (sign-off 検証ロジックを含む)
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/code/SKILL.md" --> SKILL.md の構文検証 pass
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) 全 job pass (patch route)

### Post-merge

- 次回 `/code` 実行で生成される全 commit に Signed-off-by が付くことを git log で確認 <!-- verify-type: opportunistic -->

## Notes

- **既存状態**: `skills/code/SKILL.md` の Step 11 (line 417) と Step 12 (line 547) はすでに `git commit -s` パターンを含み、sign-off 検証アサーションも存在する。AC2, AC4, AC6 はすでに満たされている。主要な gap は Step 8 の中間 commit への明示指示と `run-code.sh` の bash チェック欠如。
- **run-code.sh チェックのスコープ**: patch route のみ有効 (`git log PRE_HEAD..HEAD` は main ブランチへのマージ後 commit を対象)。PR route では HEAD が変わらないため新規 commit を検出しない — PR route の DCO チェックは CI (dco.yml) が担保。
- **bash 3.2+ 互換**: herestring `<<<` は bash 2.0+ から利用可能。`IFS= read -r` も 3.2+ 互換。`mapfile` は使用しない。
- **Issue Retrospective 引き継ぎ (auto-resolved)**:
  - `run-code.sh` のスコープ: 直接 `git commit` を生成しないため「bash 実装層」= `claude -p` 完了後のポストチェックと判断
  - verify コマンド `-E` フラグ: ripgrep (ERE デフォルト) のため不要
  - post-merge verify-type: `event=code-run` は未定義イベントのため `opportunistic` に修正済み

## Consumed Comments

- saito (MEMBER, first-class) — Issue Retrospective: auto-resolved ambiguity points (run-code.sh scope, verify command -E flag, post-merge verify-type) + AC 更新内容を記載。本 Spec 設計に全面反映。
  URL: https://github.com/saitoco/wholework/issues/795#issuecomment-4824207568
