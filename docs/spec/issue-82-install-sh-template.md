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

## Code Retrospective

### Deviations from Design

- **Route override**: Spec は Size=M を想定し pr route を前提としていたが、`/code 82` 実行時に Step 1 のみを probe commit として PR 化（pr route を維持）。ただし PR の性質は「通常の実装 PR」ではなく「条件付き probe PR」となったため、タイトルと本文で明示した
- **Step 2–4 の未実施**: Step 1（probe commit）のみを #83 で実装し、Step 2（分岐判断）と Step 3（Phase B）と Step 4（Post-merge 検証）はユーザーのセッション再起動後の結果に応じて follow-up 実装として扱う
- **Step 10 acceptance check のスキップ**: Pre-merge hints（`file_exists "install.sh"` 等）は install.sh 方式を前提としており、probe commit の時点では前提未達成で全 FAIL する。partial implementation であることを明示し、acceptance check 実行は follow-up iteration に defer
- **`closes #82` の PR 本文からの除外**: 通常の pr route は PR 本文に `closes #N` を含めるが、本 PR は条件付きで Issue を解決しない可能性があるため `closes #82` を意図的に除外し、`Related to #82` のみ記載

### Design Gaps/Ambiguities

- **Conditional implementation の /code 対応**: 本 Spec は Step 1 完了後にユーザー介入を挟む設計だが、`/code` skill は single-shot で end-to-end 実装を前提としている。そのため「Step 1 のみを partial 実装して commit+PR」という判断を `/code` 実行時に下す必要があった。将来的に conditional spec パターンへの skill 対応（例: 中間 checkpoint commit + 次 step への明示的な待機指示）を検討する余地あり
- **Size 見積もりのずれ**: Spec は Size=M として triage されたが、Step 1 単体は XS 相当（1 ファイル 1 行変更）。Phase A 完了時点で Size 見直し（XS に降格）する選択肢もあった。Phase B 実装時に改めて Size 評価すべき
- **PR 化 vs patch 化の判断**: 本来 probe commit は patch route（main への直接コミット）の方が軽量だが、pr route 選択により CI/review フローが走る。CI コストと review の重さを考慮し、次回以降 probe commit は `--patch` フラグ明示の運用を検討

### Rework

- なし（Step 1 のみの実装のため、この iteration でのリワークは発生せず）

## Review Retrospective

### Spec vs. 実装の乖離パターン

- Spec の Step 1 スコープ（`.claude/settings.json` の plugin cache パターン 1 行変更）と実装が完全一致。repo-root 絶対パスを据え置いた判断も Spec の Step 1 と整合しており乖離なし
- Code Retrospective で 3 項目（route override、Step 2–4 未実施、acceptance check スキップ）を事前記録していたため、review フェーズで追加指摘として挙がる事項がなかった

### 繰り返し発生している問題

- Conditional implementation の skill 対応が既知の課題として継続（`/code` が single-shot 前提のため、partial 実装を都度判断する必要がある）。将来的には `/code` skill に checkpoint/pause 機能を導入するか、conditional spec を別パターンとして扱う仕組みを検討する余地あり

### 受入条件検証の難易度

- 本 PR の acceptance criteria は install.sh 方式を前提としており、probe commit の時点で FAIL/UNCERTAIN が前提となる構造。これは「conditional implementation で初期受入条件を full scope に設定している」ことに起因する
- 代替案: conditional spec では Pre-merge 条件を「Step 1 が正しく commit されている」等の小さな粒度に分割し、iteration ごとにスコープを拡大する運用が考えられる

## Phase A Clean Test Results (post-merge of probe PR #83)

セッション再起動後に以下の条件でクリーンテストを実施:

**テスト条件:**
- 新セッション（`~/` 形式 settings.json がキャッシュされた状態）
- Plugin cache 絶対パス invocation（`/Users/saito/.claude/plugins/cache/saitoco-wholework/wholework/0892daea71ff/scripts/gh-pr-merge-status.sh 83`）
- Shell operators なし（`2>&1`、`|`、`&&` 等を含まない simple invocation）
- `settings.local.json` に事前承認なし（`gh-pr-merge-status` は未承認スクリプトリスト）
- 現在の `settings.json` には plugin cache 用の `~/` 形式のみ存在（ハードコード形式は削除済み）

**結果: プロンプト発生、`~/` 不動作確定**

`.tmp/permission-log.txt` にエントリ記録 (2026-04-10 13:42:54)、`settings.local.json` に `Bash(/Users/saito/.claude/plugins/cache/saitoco-wholework/wholework/0892daea71ff/scripts/gh-pr-merge-status.sh 83:*)` が自動追加された（ユーザー承認の証跡）。

**結論**: permission pattern は literal string match（+ `*` glob）で処理され、`~/` tilde 展開は行われない。shell operators の影響という仮説は棄却。#80 の当初結論が正しかったことが clean test で再確認された。

→ Step 2 分岐判定: **`~/` 不動作** → Phase B（install.sh テンプレート展開）を採用

## Phase B Implementation Summary

Step 2 分岐の結果を受けて Phase B を実装:

1. `.claude/settings.json.template` を新規作成（`${HOME}` 記法で plugin cache パターンを記述）
2. `install.sh` を新規作成（template から sed で `${HOME}` を実 $HOME に置換して `.claude/settings.json` を生成）
3. `.gitignore` を更新: `.claude/settings.json` を untrack、`.claude/settings.json.template` を un-ignore
4. `git rm --cached .claude/settings.json` で index から除外（オンディスクは保持）
5. `install.sh` を実行して `.claude/settings.json` を再生成（結果は `.gitignore` で untrack されるため以降 commit されない）
6. 副次変更として repo-root 絶対パス `Bash(/Users/saito/src/wholework/scripts/*.sh *)` を template から削除（Issue 本文の Auto-Resolved Ambiguity Points に準拠。相対パス `scripts/*.sh *` エントリが dev モードをカバー）

これにより、他ユーザが clone 後に `./install.sh` を実行すれば環境別の settings.json が生成される状態を実現。

## Phase B Review Retrospective (PR #85)

### Spec vs. 実装の乖離パターン

- Spec の Phase B Implementation Summary（Step 1–6）と PR #85 の実装は完全一致。Spec 乖離は検出されなかった
- clean test の結果記録（Phase A Clean Test Results）を Spec に事前追記してから PR を作成したため、review フェーズで前提の食い違いによる指摘が発生しなかった

### 繰り返し発生している問題

- なし。今回の Phase B 実装は過去の #78、#80 での学びを踏まえて設計されており、同種の指摘は再発していない

### 受入条件検証の難易度

- `file_contains ".gitignore" ".claude/settings.json"` は literal text match であり、コメント行の記述や `.claude/settings.json.template` のプレフィックスマッチでも PASS になる点に留意が必要だった。実際には `.claude/*` パターンで ignore されているため `git check-ignore` での確認が最も正確だが、そのためには `command` hint が必要で safe mode で UNCERTAIN になる
- 代替案: `command "git check-ignore .claude/settings.json > /dev/null"` を `/verify` 段階で実行する post-merge 条件に移す案があり得る

### Review findings (PR #85)

- **install.sh:29 — atomic write (SHOULD)**: 対応済み。temp file + `mv` パターンに変更し、`trap` で一時ファイルを削除
- **install.sh:29 — sed delimiter conflict (CONSIDER)**: コメント追記のみ。実装変更は POSIX システムの `$HOME` 制約から不要
- **docs/structure.md:164 — git pull note (CONSIDER)**: 対応済み。`after git pull whenever the template has changed` を追記
- **README.md — 直接言及なし (CONSIDER)**: スキップ。既存のアンカーリンク経由で十分と判断
