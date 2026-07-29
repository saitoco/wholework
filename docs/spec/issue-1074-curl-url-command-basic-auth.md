# Issue #1074: verify: curl 系 URL command (html_check / http_status / api_check) に Basic Auth を追加

## Overview

`modules/verify-executor.md` の curl 系 URL command (`html_check` / `http_status` / `api_check` / `http_header` / `http_redirect`) は URL 文字列のみを受け取り curl を直接実行する設計のため、Basic Auth 保護下の URL (PR preview 等) を検証できない。#1051 で `lighthouse_check` に Basic Auth 対応が入ったが、同 Issue のスコープは lighthouse-adapter に限定されており、curl 系 command は明示的にスコープ外とされていた (本 Issue はその follow-up)。

対応方針は Issue 本文の Auto-Resolved Ambiguity Points で `--config` 方式に決定済み: `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` (既存の環境変数、`.wholework.yml` への新規キー追加は不要) が両方設定されている場合、`user = "USER:PASS"` の一時 config ファイルを `mktemp` で作成し (デフォルト 600 権限)、`curl --config "$config_file"` で注入する。`modules/lighthouse-adapter.md` の `header_file` パターン (一時ファイル + 600 権限 + 削除) をそのまま踏襲し、マスキング方針も `modules/browser-adapter.md` / `modules/lighthouse-adapter.md` と揃える。環境変数未設定時は現状どおり認証なしで実行する (後方互換)。

**重要な設計上の要点**: 5 つの command の翻訳テーブル各行に書かれている curl コマンドは、safe mode (URL security check 通過後に curl 実行) と full mode (制限なしで curl 実行) の両方から共有される単一の記述であるため、この curl 行に `--config` を追加するだけで両モードに Basic Auth が適用される。これにより、Issue 本文が報告する実際の障害ケース (`/review` の safe mode で実行される pre-merge-preview tier の `html_check` AC が 401 で FAIL する) が解消される。

## Changed Files

- `modules/verify-executor.md`: change — 「### Basic Authentication Support」節に curl 系 URL command 向けの Basic Auth 注入手順 (一時 `--config` ファイル、マスキング、後方互換) を追記し、5 つの翻訳テーブル行 (`http_status` / `html_check` / `api_check` / `http_header` / `http_redirect`) の curl コマンド記述に `--config` 注入を反映する

## Implementation Steps

1. `modules/verify-executor.md` の「### Basic Authentication Support」節 (現状 `browser_check`/`browser_screenshot` と `lighthouse_check` の委譲説明のみ、L256-260 付近) に、curl 系 URL command (`http_status` / `html_check` / `api_check` / `http_header` / `http_redirect`) 向けの新しい段落を追記する。要点:
   - `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` が両方設定されている場合、次のシェルスニペットで一時 config ファイルを作成する:
     ```bash
     mkdir -p .tmp
     config_file="$(mktemp .tmp/curl-auth-XXXXXX.cfg)"
     printf 'user = "%s:%s"\n' "$PREVIEW_BASIC_USER" "$PREVIEW_BASIC_PASS" > "$config_file"
     ```
     (`mktemp` はデフォルトで 600 権限のファイルを作成するため、明示的な `chmod` は不要 — 実機確認済み、Notes 参照)
   - 次ステップの翻訳テーブルの curl コマンドに `curl --config "$config_file"` として注入する旨を明記する。この説明文には **リテラルな連続文字列 `curl --config`** (「curl」の直後に半角スペース 1 つと「--config」が続く形) をそのまま含めること — Pre-merge AC5 の `<!-- verify: grep "curl --config" "modules/verify-executor.md" -->` の検証対象文字列のため
   - コマンド完了後 (成功・失敗を問わず) `rm -f "$config_file"` で削除する後始末を明記する
   - `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` の値・config ファイルの内容を、ログや検証結果詳細に出力しない (`****` としてマスク) 旨を、`modules/browser-adapter.md` Step 3 / `modules/lighthouse-adapter.md` Step 2 と同じマスキング方針として明記する
   - どちらか一方でも環境変数が未設定の場合は `--config` 注入をスキップし、現行の無認証動作を維持する (後方互換) 旨を明記する
   - `--allow-localhost` フラグとは独立して動作する (直交する設定) 旨を明記する
   (→ Pre-merge AC1, AC2, AC3, AC4, AC5)

2. (after 1) 翻訳テーブルの `http_status` / `html_check` / `api_check` / `http_header` / `http_redirect` の 5 行 (現状 L73-77 付近) それぞれの curl コマンド記述に、`--max-time 10` の直後へ `[--config "$config_file"]` (両環境変数設定時のみ含まれる意の表記) を挿入する。各行の curl コマンドは safe mode ("external URLs executed with curl") と full mode (制限なしの明示コマンド) の両方から共有される単一の記述であるため、この 1 箇所の追記だけで両モードに Basic Auth が適用される。
   (→ Pre-merge AC1, AC5)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-executor.md の curl 系 URL command (html_check / http_status / api_check / http_header / http_redirect) が PREVIEW_BASIC_USER / PREVIEW_BASIC_PASS を読んで Basic 認証を付与する手順を持つ" --> curl 系 URL command が Basic Auth を通せる
- <!-- verify: rubric "認証情報がコマンドライン引数としてプロセスリストに露出しない方式 (一時ファイル経由等) が採用され、一時ファイルの権限設定と削除が定義されている" --> 認証情報がプロセスリストに露出しない
- <!-- verify: rubric "PREVIEW_BASIC_USER / PREVIEW_BASIC_PASS の値および導出物をログ・検証結果に出力しないマスキング方針が、browser-adapter / lighthouse-adapter と同じ方針で明記されている" --> マスキング方針が既存 adapter と揃っている
- <!-- verify: rubric "環境変数が未設定の場合は認証なしで実行される後方互換の挙動が明記されている" --> 後方互換が保たれている
- <!-- verify: grep "curl --config" "modules/verify-executor.md" --> curl 系 URL command が `--config` 経由の一時ファイルで認証情報を注入している

### Post-merge

- Basic Auth 保護下の preview URL に対して `html_check` を実行し、401 ではなく実際の HTML に対する判定結果 (PASS/FAIL) が返ることを確認する <!-- verify-type: manual -->
- 環境変数を未設定にして同じ AC を実行し、従来どおり認証なしで動作することを確認する <!-- verify-type: manual -->

## Notes

- **外部仕様確認 (`curl --config`、実機検証済み)**: `man curl` で `-K`/`--config` オプションの存在を確認した上で、実際にローカル HTTP サーバ (Python `http.server`) を立て、`user = "testuser:testpass"` を書いた config ファイルを `curl --config` で読ませたところ、`Authorization: Basic dGVzdHVzZXI6dGVzdHBhc3M=` ヘッダが正しく送信されることを実機で確認した (`dGVzdHVzZXI6dGVzdHBhc3M=` は `testuser:testpass` の base64 エンコードと一致)。また `mktemp` が作成する一時ファイルの権限が `-rw-------` (600) であることも実機で確認した (Implementation Step 1 で明示的な `chmod` を不要とした根拠)。
- **safe/full mode 両対応が本 Issue の核心**: 翻訳テーブルの各行は curl コマンドを 1 箇所にしか記述しておらず、safe mode ("external URLs executed with curl") と full mode (明示コマンド) の両方がこれを共有する構造になっている。したがって Implementation Step 2 の 1 箇所追記で両モードに Basic Auth が適用される。Issue 本文が報告する実害 (`/review` の safe mode 実行時に 401 で FAIL) は full mode 限定の対応では解消しないため、この点は実装時に見落とさないよう明記した。
- **クレデンシャル/セキュリティポリシー確認 (確認済み、矛盾なし)**: `SECURITY.md` および `grep -rl "credential\|security" docs/ SECURITY.md` (repo ルート) でヒットしたポリシー文書を確認したが、`PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` の取り扱いを制約する明示的な記述はなく (#1051 と同一の結論)、`SECURITY.md` の "Wholework does not store or transmit credentials" は GitHub CLI 認証に関する記述で本件とは別スコープ。
- **他ファイルへの影響なし (確認済み)**: `grep -rln "html_check\|http_status\|api_check\|http_header\|http_redirect" docs/guide/ docs/environment-adaptation.md skills/verify/ modules/` で言及箇所を確認したが、`docs/guide/customization.md` (pre-merge-preview tier 対象コマンド一覧)・`docs/environment-adaptation.md` (safe/full mode 実行可否表)・`modules/execution-context.md`・`modules/browser-verify-security.md`・`modules/verify-patterns.md` はいずれも Basic Auth の有無を主張する記述がなく、更新不要と判断した (#1051 の同種チェックと同じ結論)。`docs/guide/customization.md` は `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` 自体を未記載のままだが、これは本 Issue 以前からの既存ギャップでありスコープ外 (Changed Files が `SKILL.md` / `scripts/` を含まないため Steering Docs sync candidate check の対象外)。
- **アダプタパターン調査**: 本 Issue が扱う 5 command はいずれも `modules/verify-executor.md` の built-in translation table に既存の command type であり、新規 command type を導入しないため `docs/environment-adaptation.md` Extension Guide Step 0 の対象外と判断した。
- **Issue 本文と実装の整合性チェック (確認済み、矛盾なし)**: Issue 本文が主張する現行実装 (curl 系 5 command が URL 文字列のみを受け取り `-u` / `--header` / `--config` 相当のオプションを持たない) は `modules/verify-executor.md` の該当行と完全に一致することを確認した。
- **Smoke Test セクション不採用**: 本 Issue の verify command は `mcp_call` を含まず `capabilities.mcp` も無関係のため、Smoke Test セクションの採用条件に該当しない。また wholework 自身のリポジトリには Basic Auth 保護下の preview URL が存在しないため、pre-merge での実地スモークテストは対象読者環境でのみ可能 (Post-merge AC で確認する設計、#1051 と同じ扱い)。

## Consumed Comments

- saito (MEMBER, first-class): `/issue` 非対話フローの Issue Retrospective コメント (2026-07-29T03:48:20Z)。Size=S / Type=Feature / Value=3 のトリアージ結果、AC verify command 監査で発見した常時 PASS defect (`grep "PREVIEW_BASIC_USER"` から `grep "curl --config"` への修正)、`--config` 方式の自動解決根拠を記録したもので、いずれも本 Issue 本文の Acceptance Criteria / Auto-Resolved Ambiguity Points に既に反映済みのため、Spec 作成上の追加対応は不要と判断した。 (https://github.com/saitoco/wholework/issues/1074#issuecomment-5112604944)

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在 (Step 3 precondition check)**: `/code` 開始時点で Issue #1074 のラベルは `triaged` / `phase/code` / `retro/verify` で、`phase/ready` が付与されないまま `phase/code` に遷移していた (`reconcile-phase-state.sh code-patch 1074 --check-precondition` も `matches_expected: false` を返した)。ただし Spec (`docs/spec/issue-1074-curl-url-command-basic-auth.md`) 自体は Design Complete コメントまで完了した内容で既に存在するため、「Spec なしで Issue 本文から直接実装」ではなく、既存の完成済み Spec を正としてそのまま実装を進めた。

## Auto Retrospective

### Manual recovery (code-patch)
- **Date**: 2026-07-29 04:34 UTC
- **Issue**: #1074, phase: code-patch
- **Source**: parent session manual recovery
- **Recovery type**: push-only
- **Wrapper exit code**: unknown
- **Outcome**: success
