# Issue #82: settings: install.sh でテンプレート展開し絶対パスのハードコードを解消

## Overview

`.claude/settings.json` の `permissions.allow` に含まれるハードコード `/Users/saito/` を除去し、OSS 公開時に他ユーザ環境で動作するようにする。

**重要**: #80 で得た「`~/` 展開不動作」という結論は、テストが shell operators (`2>&1 | head -N`) 付きで実施されたことに起因する可能性が高い。このため、本 Spec では最初に simple invocation での **clean test** を行い、`~/` が実際に動作する場合は install.sh 方式を省略する。全ケースでハードコードは除去される。

## Changed Files

**Phase A（調査フェーズ、全ケース共通）:**
- `.claude/settings.json`: `~/` 形式で一時書き換え（clean test 用）。結果次第で採用または revert

**Phase B（install.sh 方式、`~/` が動作しない場合のみ）:**
- `install.sh`: 新規作成（template から `.claude/settings.json` を生成）
- `.claude/settings.json.template`: 新規作成（git 管理される source of truth）
- `.gitignore`: `.claude/settings.json` を除外に追加、`.claude/settings.json.template` の除外解除を追加

## Implementation Steps

1. **`~/` 展開の clean test**: `.claude/settings.json` の `Bash(/Users/saito/.claude/plugins/cache/saitoco-wholework/wholework/*/scripts/*.sh *)` を `Bash(~/.claude/plugins/cache/saitoco-wholework/wholework/*/scripts/*.sh *)` に変更、commit + push。ユーザがセッション再起動後、plugin cache 配下のスクリプトを **simple invocation**（shell operators なし、例: `/Users/saito/.claude/plugins/cache/saitoco-wholework/wholework/<hash>/scripts/gh-pr-merge-status.sh 82`）で実行し、プロンプトの有無を確認
2. **結果による分岐判断**:
   - **`~/` が動作**: `~/` 形式を確定。repo 直下の絶対パス `Bash(/Users/saito/src/wholework/scripts/*.sh *)` も同様に `~/` 形式に置換可能か評価（現状は相対パスで dev モードをカバーしているため削除で済む可能性が高い）。Phase B はスキップ。Issue の Pre-merge 条件 2/3/4 は不適用として Issue 本文を更新
   - **`~/` が不動作**: Phase A を revert し Phase B へ進む
3. **Phase B の実装**（条件付き）: `.claude/settings.json.template` に `${HOME}` 記法で plugin cache パターンを記述。`install.sh` を新規作成し、`sed` または `envsubst` で template から settings.json を生成する処理を含める。`.gitignore` で `.claude/settings.json` を除外、`.claude/settings.json.template` を除外解除
4. **動作確認**: 採用方式を問わず、ユーザがセッション再起動後に `/auto` 実行でプロンプトが発生しないことを目視確認（Post-merge）

## Verification

### Pre-merge
- <!-- verify: file_not_contains ".claude/settings.json.template" "/Users/saito" --> `.claude/settings.json.template`（または後継の設定ソース）に `/Users/saito` が含まれない
- <!-- verify: file_exists "install.sh" --> `install.sh` が存在する
- <!-- verify: file_contains "install.sh" "settings.json" --> `install.sh` が `.claude/settings.json` を生成する処理を含む
- <!-- verify: file_contains ".gitignore" ".claude/settings.json" --> `.gitignore` が生成後の `.claude/settings.json` を除外する（もしくは、代替方式採用時は settings.json 自体にハードコードが残らない形に変更）

### Post-merge
- `install.sh` をユーザが異なるホームディレクトリで実行し、生成された `.claude/settings.json` で `/auto` 実行時にプロンプトが発生しないことを確認（install.sh 方式採用時のみ）
- `git pull` 後に `install.sh` 再実行で settings.json が正しく更新されることを確認（install.sh 方式採用時のみ）

## Notes

### #80 の前提見直し

#80 で「`~/` 展開が permission pattern で機能しない」と結論したが、本セッション内の追加検証で以下が判明:

- hardcoded pattern `Bash(/Users/saito/.claude/plugins/cache/saitoco-wholework/wholework/*/scripts/*.sh *)` がキャッシュされた状態で、**shell operators なしの simple invocation**（`validate-permissions.sh skills`）を実行 → **プロンプトなし、マッチ成功**
- 同じ hardcoded pattern 下で、`validate-permissions.sh 2>&1 | head -3` のように shell operators を含む呼び出しを実行 → **プロンプト発生**
- #80 の `~/` テストで使用した 2 つの呼び出し（`check-file-overlap.sh --help 2>&1 | head -5`、`wait-external-review.sh 2>&1 | head -5`）はいずれも `2>&1 | head -5` を含んでいた

したがって、#80 のテストは `~/` 展開の可否ではなく shell operators の影響を測定していた可能性が高い。Step 1 の clean test で真の可否を確定する。

### Conditional implementation

この Spec は light 構成だが実装フローは Step 1 の結果次第で分岐する。`/code` フェーズでは:

- Step 1 を実施して push → ユーザのセッション再起動 → ユーザが結果報告
- 報告結果に応じて Step 2 の分岐を選択し、Step 3 は条件付きで実行
- 結果次第では Issue 本文の受入条件修正（install.sh 関連条件の削除）が発生

### Issue 受入条件との整合

Issue #82 の Pre-merge 受入条件は install.sh 方式を前提としているが、本 Spec では `~/` 方式採用時に一部条件が不適用となるため、`/code` フェーズで採用方式確定後に Issue 本文の受入条件を調整する方針。`/verify` 時点でミスマッチが起きないよう、`/code` 実装時に必ず Issue 本文を更新する。

### 代替方式 (Option B/C) の扱い

Issue 本文では `${HOME}` / `${CLAUDE_PROJECT_DIR}` 展開を Option B/C として挙げているが、本 Spec ではまず Option B の先行ステップとして `~/` を再検証する構成。`~/` が不動作かつ `${HOME}` が動作するケースは実質的に稀と考え、`~/` 不動作確定時は直ちに install.sh 方式 (Option A) に進む。Option B/C を追加で調査する場合は別 Issue として切り出す。
