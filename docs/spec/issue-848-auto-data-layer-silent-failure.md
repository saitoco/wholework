# Issue #848: auto: data-layer.md generation の silent failure 防止

## Overview

`/auto` L3 auto-retrospective (Step 5 内) の sub-step 2 "Create session dir and generate data layer" にある `get-auto-session-report.sh` 呼び出し (`skills/auto/SKILL.md` lines 712-714) に 3 つの構造的問題があり silent failure を起こす:

1. `--no-github` 未指定 — gh API 呼び出しで実測 32.9s かかり、batch session L3 末尾での watchdog timeout / `/auto` 親 SIGTERM で kill されやすい
2. `2>/dev/null` で stderr を全捨て — 失敗時の原因が一切残らず再発診断が不可能
3. `|| echo "Warning..."` による silent continue — レポート不在に後日まで気付かない

## Changed Files

- `skills/auto/SKILL.md`: L3 auto-retrospective sub-step 2 の `get-auto-session-report.sh` 呼び出しを 3 点改修 (bash 3.2+ compatible)

## Implementation Steps

1. `skills/auto/SKILL.md` の L3 auto-retrospective sub-step 2 "Generate data layer report" コードブロック (lines 712-714) を次の構造に置き換える (→ AC1, AC2, AC3):
   - `--no-github` フラグを追加 (→ AC1)
   - `2>/dev/null` を `2>"$SESSION_DIR/data-layer-stderr.log"` に変更 (→ AC2); retry 時は `2>>` で append
   - retry-once ロジック追加: 1 回目失敗時に同じコマンドを再試行; 2 回連続失敗で `echo "Warning..."` を出力; 成功時 (1 回目 or 2 回目) は stderr log を `rm -f` で削除 (→ AC3)
   - コードブロック説明ラベルを "Generate data layer report (best-effort; log warning on failure and continue):" から実態を反映した文言に更新
   
   置き換え後のコードブロック例:
   ```bash
   if ! "${CLAUDE_PLUGIN_ROOT}/scripts/get-auto-session-report.sh" "$AUTO_SESSION_ID" --output "$SESSION_DIR/data-layer.md" --no-github 2>"$SESSION_DIR/data-layer-stderr.log"; then
     if ! "${CLAUDE_PLUGIN_ROOT}/scripts/get-auto-session-report.sh" "$AUTO_SESSION_ID" --output "$SESSION_DIR/data-layer.md" --no-github 2>>"$SESSION_DIR/data-layer-stderr.log"; then
       echo "Warning: data-layer.md generation failed — continuing without data layer report"
     else
       rm -f "$SESSION_DIR/data-layer-stderr.log"
     fi
   else
     rm -f "$SESSION_DIR/data-layer-stderr.log"
   fi
   ```

## Verification

### Pre-merge

- <!-- verify: grep "get-auto-session-report.sh.*--no-github" "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` の `get-auto-session-report.sh` 呼び出しに `--no-github` が追加されている
- <!-- verify: rubric "skills/auto/SKILL.md Step 2 の get-auto-session-report.sh 呼び出しで stderr が単に捨てられず log ファイルに保存される構造になっている" --> <!-- verify: grep "data-layer-stderr" "skills/auto/SKILL.md" --> stderr が `$SESSION_DIR/data-layer-stderr.log` 等に redirect されている (`2>/dev/null` 単独ではない)
- <!-- verify: rubric "skills/auto/SKILL.md Step 2 の get-auto-session-report.sh 呼び出しで初回失敗時に 1 回 retry し、両方失敗で初めて warning する旨が記述されている" --> 失敗時の retry-once ロジックが Step 2 に明記されている

### Post-merge

- 次回 `/auto --batch` 完走時に対象 session directory に `data-layer.md` が存在することを確認

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective + Auto-Resolve Log (AC2 に補足 grep ヒント追加, `--no-github` フラグ実装確認) / https://github.com/saitoco/wholework/issues/848#issuecomment-4828453919

## Notes

- `--no-github` は `scripts/get-auto-session-report.sh` line 56 に実装済み (Issue Retrospective で確認)
- `--no-github` 指定時、data-layer.md の "Fully closed" / "phase/verify remaining" カラムは `N/A (--no-github)` となる。フル gh API モードのデータが必要な場合は `/audit auto-session <id>` を別途実行
- Issue Retrospective の自動解決判定: AC2 の rubric 単独では semantic 判定のみになるため、`grep "data-layer-stderr"` 補足ヒントを追加済み (Issue 本文に反映済み)
