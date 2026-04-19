# Issue #276: verify-executor: verify command type 単位で実行権限を宣言できるようにする

## Overview

`modules/verify-executor.md` の翻訳テーブルに Permission 列（`always_allow` / `always_ask`）を追加し、
カスタムハンドラに `**Permission:**` 宣言フィールドを追加する。
Permission 宣言を解析する `scripts/get-verify-permission.sh` を新設し、
bats テストでその動作を検証する。
将来的に Managed Agents `permission_policy` への 1:1 移植を可能にするセマンティクス準備が目的。

## Changed Files

- `modules/verify-executor.md`: 翻訳テーブルに Permission 列を追加、Step 3c にハンドラの Permission 宣言読み取りを追記、Managed Agents `permission_policy` 対応注記を追加
- `docs/environment-adaptation.md`: Custom Verify Command Handlers セクション Handler Contract に `**Permission:**` フィールドを追加、Safe Mode Self-Declaration テーブル後に Permission Self-Declaration テーブルを追加
- `scripts/get-verify-permission.sh`: 新規ファイル — ハンドラファイルから `**Permission:**` 宣言を解析して `always_allow` / `always_ask` を返す bash 3.2+ 互換スクリプト
- `tests/get-verify-permission.bats`: 新規ファイル — `get-verify-permission.sh` の動作検証 bats テスト
- `docs/structure.md`: スクリプト数 35→36 に更新、Project utilities セクションに `scripts/get-verify-permission.sh` のエントリを追加

## Implementation Steps

1. `modules/verify-executor.md` を更新する（→ 受け入れ条件 1, 2, 4）:
   - Step 3c に「ハンドラファイルから `**Permission:**` 宣言を抽出し、`always_allow` / `always_ask` を記録する。宣言が省略された場合のデフォルトは `always_ask`（保守側）」を追記
   - 翻訳テーブルに Permission 列を追加し、各組み込みコマンドに値を付与:
     - `always_allow`（副作用なし読み取り専用）: `file_exists`, `file_not_exists`, `dir_exists`, `dir_not_exists`, `file_contains`, `file_not_contains`, `files_not_contain`, `grep`, `section_contains`, `section_not_contains`, `json_field`, `symlink`
     - `always_ask`（実行・副作用あり・外部呼び出し）: `command`, `build_success`, `lighthouse_check`, `browser_check`, `browser_screenshot`, `mcp_call`, `github_check`, `http_status`, `html_check`, `api_check`, `http_header`, `http_redirect`
   - Processing Steps 末尾（または Output Format 直前）に、本機構が Managed Agents `permission_policy` と対応する旨の注記を追加:
     「`always_allow` は `permission_policy: always_allow`、`always_ask` は `permission_policy: always_ask` に対応する。将来の Managed Agents 移植時に 1:1 でマッピング可能」

2. `docs/environment-adaptation.md` を更新する（→ 受け入れ条件 3）:
   - Custom Verify Command Handlers の Handler Contract テンプレート内、`**Safe mode:**` フィールドの直後に `**Permission:** always_allow` または `**Permission:** always_ask` フィールドを追加
   - Safe Mode Self-Declaration テーブルの後に Permission Self-Declaration テーブルを追加:
     | 宣言 | 動作 |
     | `**Permission:** always_allow` | 副作用なし確認済みのコマンドを常時許可 |
     | `**Permission:** always_ask` | 実行前にユーザー確認を要求 |
     | （未宣言） | `always_ask` として扱う（デフォルト） |

3. `scripts/get-verify-permission.sh` を新規作成する（→ 受け入れ条件 5）:
   - 入力: `$1` にハンドラファイルパス（省略 or 存在しない場合は `always_ask` を出力して exit 0）
   - `grep -m1 '^\*\*Permission:\*\*'` でファイル先頭近くの宣言を取得し、`sed` でフィールド値を抽出
   - `case` 文で `always_allow` の場合のみ `always_allow` を出力、それ以外は `always_ask` を出力
   - `set -euo pipefail`、bash 3.2+ 互換

4. `tests/get-verify-permission.bats` を新規作成する（→ 受け入れ条件 5）:
   - `@test "Permission: always_allow returned for handler with always_allow declaration"`
   - `@test "Permission: always_ask returned for handler with always_ask declaration"`
   - `@test "Permission: always_ask is default when declaration is missing"`
   - `@test "Permission: always_ask returned when file does not exist"`
   - `@test "Permission: always_ask returned for empty file path argument"`

5. `docs/structure.md` を更新する（after 3）:
   - `scripts/` のファイル数を `35 files` → `36 files` に変更
   - Project utilities セクションに `scripts/get-verify-permission.sh — extract permission value from a verify command handler file` を追加

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/verify-executor.md" "always_allow" --> `modules/verify-executor.md` の翻訳テーブルに Permission 列（`always_allow` / `always_ask`）が追加されている
- <!-- verify: file_contains "modules/verify-executor.md" "always_ask" --> `modules/verify-executor.md` に `always_ask` のデフォルト挙動が記述されている
- <!-- verify: file_contains "docs/environment-adaptation.md" "Permission" --> `docs/environment-adaptation.md` の Custom Verify Command Handlers セクションに `**Permission:**` 宣言の contract が追加されている
- <!-- verify: grep "permission_policy\|Managed Agents" "modules/verify-executor.md" --> 本機構が Managed Agents `permission_policy` と対応する旨（将来移植の意図）が注記されている
- <!-- verify: command "find tests -name '*permission*.bats' -type f | grep -q ." --> permission 宣言の解釈を検証する bats テストが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 追加されたテストを含む全 bats テストが CI で PASS する

### Post-merge

- 実 Issue で `always_allow` 宣言のあるカスタムコマンドが非対話で実行され、`always_ask` 宣言のカスタムコマンドが対話確認を求めることを確認 <!-- verify-type: opportunistic -->

## Notes

- `always_allow` = 現状の `--dangerously-skip-permissions` 相当。`always_ask` = 現状の対話モード。既存の safe/full モードは廃止しない（追加レイヤ）
- デフォルト `always_ask` は保守側の判断: カスタムハンドラ作者が明示的に副作用の安全性を宣言した場合のみ `always_allow` になる
- HTTP 系コマンド（`http_status`, `html_check`, `api_check`, `http_header`, `http_redirect`）は読み取り専用 GET だが外部呼び出しのため `always_ask` に分類
- `github_check` も読み取り専用ケースが多いが外部 API のため `always_ask` に分類
- 実際の enforcement（`always_allow` 宣言に基づいた実行制御）は本 Issue のスコープ外。将来の Managed Agents 移植のための宣言形式導入のみ
- patch route（Size S）のため PR が存在しない。`gh pr checks` は使用不可。CI 確認は `gh run list` で行う（Issue 本文の `github_check "gh pr checks"` を `gh run list` 形式に自動修正済み）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- `docs/ja/` 翻訳ファイル（`environment-adaptation.md`, `structure.md`）への同期が Spec に記載されていなかった。doc-checker モジュールが検出したため追加対応した。

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件は全て `file_contains` / `grep` / `command` / `github_check` の verify コマンドが付与されており、自動検証可能な形式で記述されていた
- パッチルート（PR なし）であることを Spec Notes に明示し、`github_check "gh run list"` 形式を使用するよう記載されていた点は適切

#### design
- 英語ドキュメント更新時の `docs/ja/` 翻訳ファイル同期が Spec の実装ステップに含まれていなかった。doc-checker が検出して対応（commit 0876284）したが、Spec テンプレートまたは `/spec` スキルで翻訳同期タスクの明示をサポートしていれば、この漏れを防げた可能性がある
- 変更ファイルの列挙と実装ステップの粒度は適切だった

#### code
- デザインからの逸脱なし。リワークなし
- 翻訳ファイル同期（commit 0876284）が Spec 外の追加コミットになったが、doc-checker モジュールによる自動検出で対応できており、実装品質への影響なし

#### review
- パッチルート（Size S）のため PR レビューなし。コードの変更範囲が小さく（翻訳テーブルへの列追加 + 新規スクリプト）、レビューなしでも品質を維持できた

#### merge
- パッチルート（main への直接コミット）。コンフリクトなし

#### verify
- 5条件が PASS、1条件が PENDING（CI in_progress）
- CI の最新ラン（2026-04-19T15:45:47Z）が実行中のため PENDING。1つ前のラン（2026-04-19T15:45:02Z）は success であり、実装品質は問題ない可能性が高い
- Post-merge opportunistic 条件は実際の Issue での動作確認が必要（自動検証対象外）

### Improvement Proposals
- `/spec` スキルの実装ステップテンプレートに「英語ドキュメントを更新した場合は `docs/ja/` の対応ファイルも更新リストに含める」チェック項目を追加することで、翻訳同期漏れを Spec 段階で防止できる
