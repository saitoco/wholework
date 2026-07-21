# Issue #1026: observation: プロジェクト設定依存の observation AC に .wholework.yml 設定有効性の事前チェックゲートを追加

## Overview

`verify-type: observation event=<name>` の observation AC は「任意の `/auto` 完走」のような広いイベントに対して発火する。観察条件が特定のプロジェクト設定 (`.wholework.yml`) に依存する場合、その設定が対象リポジトリで無効だと条件は原理的に観察不能であるにもかかわらず、notification コメントだけが繰り返し蓄積する (実例: #797 の `always-pr` 観察は本リポジトリで `always-pr` 未設定のため観察不能。2026-06-28 以降 notification コメントが 30 件超蓄積し、`/verify` 再実行 4 回すべて SKIPPED)。

本 Issue では、observation AC に `config=<key>` 属性を追加できるようにし、`opportunistic-search.sh` の event モードマッチングループに `.wholework.yml` の当該キーが有効かを事前チェックするゲートを実装する。既存の `keyword=` 属性ゲート (#934) と同型の拡張とし、属性なしの AC は従来どおり無条件マッチ (後方互換) を維持する。

## Changed Files
- `scripts/opportunistic-search.sh`: event モードのマッチ抽出ループに `config=<key>` 属性の抽出と `.wholework.yml` 有効性ゲートを追加。ヘッダコメントに `config=` の挙動を追記 — bash 3.2+ 互換 (大小文字畳み込みに bash4 の `${VAR,,}` ではなく `tr` を使用)
- `modules/observation-trigger.md`: 既存の `## Condition Check Gate (keyword=)` に倣い `## Condition Check Gate (config=)` セクションを追加
- `tests/opportunistic-search.bats`: `config=` ゲートのテストケース (設定有効時マッチ / 設定無効時除外 / 属性なし無条件マッチ) を追加

## Implementation Steps

1. `scripts/opportunistic-search.sh` の event モードマッチ抽出ループに `config=` ゲートを追加する (→ acceptance criteria AC1, AC3):
   - 挿入位置: 既存の `keyword=`/`CONTEXT_FILE` ゲートブロック (`KEYWORD=$(...)` から続く `if [ -n "$KEYWORD" ] && [ -n "$CONTEXT_FILE" ]; then ... fi`) の直後、`# Extract text with HTML comments and checkbox markup removed` コメントの直前
   - 抽出: `keyword=` と同じパターンを使う — `CONFIG_KEY=$(echo "$line" | grep -oE 'config=[^ >]+' | sed -e 's/^config=//' -e 's/-*$//' || true)`
   - ゲート判定: `CONFIG_KEY` が空でなければ `CONFIG_VALUE=$("${SCRIPT_DIR}/get-config-value.sh" "$CONFIG_KEY" "false" | tr '[:upper:]' '[:lower:]')` で `.wholework.yml` の値を解決し、`"true"` でなければ `continue` (match から除外)
   - **新規 CLI 引数は追加しない**: `get-config-value.sh` は CWD 相対 `.wholework.yml` (テスト時は `WHOLEWORK_CONFIG_PATH` 経由) を直接読むため、呼び出し元 (`observation-trigger.sh`) からの `--context-file` 相当の引数中継は不要
   - `CONFIG_KEY` が空 (属性なし) の場合は何もせず従来どおり無条件マッチ
   - ヘッダコメント (5-20 行目付近、`--context-file gates event-mode matches...` の説明段落の直後) に `config=` の挙動を説明する段落を追加する。Usage 行 (`--event <event-name> [--dry-run] [--context-file <path>]`) 自体は変更しない (新規 CLI 引数を追加しないため)

2. `modules/observation-trigger.md` に `config=` ゲートの仕様セクションを追加する (→ acceptance criteria AC2):
   - 挿入位置: 既存の `## Condition Check Gate (keyword=)` セクションの直後
   - 属性書式: `<!-- verify-type: observation event=<name> config=<key> -->` (例: `config=always-pr`)
   - `<key>` はフラットな kebab-case キーのみサポートする (`get-config-value.sh` の既存制約と同一。`capabilities.*` のようなネストキーは本 Issue のスコープ外と明記する)
   - 判定は真偽値 (`true`/`false`、大小文字非依存) の一致のみ。enum 値キー (`auto-stop-at` 等) は本 Issue のスコープ外と明記する
   - 属性なしの AC は従来どおり無条件マッチ (後方互換) する旨を明記する

3. `tests/opportunistic-search.bats` に `config=` ゲートのテストケースを追加する (→ acceptance criteria AC4, AC5):
   - `@test "config gate: enabled config key includes the issue"` — `WHOLEWORK_CONFIG_PATH` を `$BATS_TEST_TMPDIR` 内フィクスチャ (`some-flag: true` 相当) に向けてエクスポートし、マッチすることを確認
   - `@test "config gate: disabled config key excludes the issue"` — `WHOLEWORK_CONFIG_PATH=/dev/null` (デフォルト値 `false` へフォールバック。`docs/tech.md` 記載の既存 BATS 規約) でマッチから除外されることを確認
   - `@test "config gate: AC without config= matches unconditionally"` — `config=` 属性のない AC 行が `WHOLEWORK_CONFIG_PATH` の値に関わらずマッチすることを確認 (既存の "AC without keyword=" テストと同型)

## Verification

### Pre-merge
- <!-- verify: rubric "observation AC の設定前提宣言属性の仕様がドキュメント (modules/ または該当スクリプトのヘッダ) に定義され、opportunistic-search.sh または observation-trigger.sh に .wholework.yml の設定有効性をチェックして無効時に match から除外するゲート判定が実装されている" --> observation AC の設定前提宣言属性の仕様定義とゲート判定実装
- <!-- verify: file_contains "modules/observation-trigger.md" "config=" --> `config=` 属性の仕様が `modules/observation-trigger.md` にドキュメント化されている
- <!-- verify: rubric "設定前提宣言属性を持たない observation AC が従来どおり無条件でマッチする後方互換動作が実装またはテストで確認できる" --> 属性なし AC の無条件マッチ (後方互換) が確認できる
- <!-- verify: rubric "tests/ 配下に、設定有効時のマッチ・設定無効時の除外・属性なし AC の無条件マッチを検証するテストが存在する" --> ゲート判定のテスト (3 ケース) が追加されている
- <!-- verify: file_contains "tests/opportunistic-search.bats" "config=" --> `config=` ゲートのテストケースが `tests/opportunistic-search.bats` に追加されている

### Post-merge
- 設定無効なプロジェクトで該当 observation AC への notification コメントが蓄積しなくなることを観察<!-- verify-type: observation event=auto-run -->

## Notes

- **実装箇所の最終確定 (Issue body / triage retrospective で `/spec` 判断に委任されていた点)**: ゲート判定は `scripts/opportunistic-search.sh` にのみ実装し、`scripts/observation-trigger.sh` は変更しない。根拠: `observation-trigger.sh` の実装を確認したところ独自のゲート判定ロジックを持たない純粋な pass-through であり (`opportunistic-search.sh --event ...` を呼び出して結果を転送するのみ)、`keyword=` ゲートが `--context-file` という新規 CLI 引数の中継を必要としたのに対し、`config=` は `.wholework.yml` を `get-config-value.sh` 経由で直接読めるため、`observation-trigger.sh` 側に新規引数を追加する必然性がない。
- **`capabilities.*` ネストキーの扱い (Issue body で `/spec` 判断に委任)**: 本 Issue のスコープ外とする。`config=<key>` はフラットな kebab-case キーのみサポートする — 再利用する `scripts/get-config-value.sh` 自身が「ネストキー (`capabilities.browser` 等) は非対応」と明記しているため、これに合わせた。`capabilities.*` 配下のキーを対象とする observation AC が今後発生した場合は、`get-config-value.sh` の拡張または別解決策を検討する follow-up Issue とする。
- **既存 Issue (#797 等) への `config=` 属性の追記 (Issue body で `/spec` 判断に委任)**: 本 Issue のスコープ外とする。Issue 本文の Pre-merge Acceptance Criteria 5 件はいずれも属性仕様の定義・ゲート実装・ドキュメント化・テスト追加のみを要求しており、既存 Issue の AC 行編集は要求していない。#797 等への `config=` 付与は別途 follow-up Issue として扱う。
- **値判定のセマンティクス**: `config=<key>` は真偽値 (`true`/`false`、大小文字非依存) の一致のみを判定する。#783 (`auto-stop-at: review`) のような enum 値キーは Related Issues に「同種パターン」として挙げられているのみで本 Issue の必須要件ではないため対象外とする。enum 値の比較が必要になった場合は `config=key:value` 形式への拡張を follow-up として検討する。
- **`get-config-value.sh` の再利用**: `.wholework.yml` の YAML パースを `opportunistic-search.sh` 内に再実装せず、既存の `scripts/get-config-value.sh` (CWD 相対 `.wholework.yml` 読み込み、`WHOLEWORK_CONFIG_PATH` によるテスト用オーバーライド対応済み) を `"${SCRIPT_DIR}/get-config-value.sh"` 経由で呼び出す。DRY であると同時に、bats テストを `WHOLEWORK_CONFIG_PATH` 経由でヘルメティックに保てる (`docs/tech.md` 環境変数表に記載済みの既存パターンを踏襲)。
- **Steering Docs sync candidate**: `docs/structure.md` と `docs/migration-notes.md` (および `docs/ja/` ミラー) が `opportunistic-search.sh` に言及している。両ファイルを確認した結果、`structure.md` のスクリプト一覧の一行説明 ("opportunistic skill search and observation event scan") は本変更後も正確であり、`migration-notes.md` の "Interface changes: None" 記録も CLI 引数を追加しない本設計では引き続き正確なため、変更は不要と判断した。`/code` フェーズで最終確認すること。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: Issue #1026 の triage フェーズ Issue Retrospective。Size M / Type Feature / Value 3 の判定根拠、実装場所を `opportunistic-search.sh` 軸と想定する Auto-Resolve Log の追記、`file_contains` 補助 verify command 2 件の追加を記録。`capabilities.*` ネストキーの扱いと #797 等既存 Issue への適用スコープは `/spec` 判断に委任する旨を明記。 / URL: https://github.com/saitoco/wholework/issues/1026#issuecomment-5030312095

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps に記載された挿入位置・抽出パターン・ゲート判定ロジックをそのまま実装した。逸脱なし。

### Design Gaps/Ambiguities
- N/A — Spec の Notes セクションで実装箇所・スコープ境界 (`capabilities.*` 対象外、真偽値のみ)・既存 Issue への適用範囲があらかじめ確定していたため、実装時に新たな曖昧点は生じなかった。

### Rework
- N/A — 巻き戻しや設計変更は発生しなかった。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `config=<key>` ゲートは `keyword=`/`CONTEXT_FILE` ゲートブロックの直後、`# Extract text with HTML comments...` コメントの直前に実装した (Spec 指定の挿入位置どおり)。新規 CLI 引数は追加せず、`get-config-value.sh` を `${SCRIPT_DIR}/get-config-value.sh` 経由で直接呼び出す設計を採用した。
- `modules/observation-trigger.md` の `config=` セクションは既存の `keyword=` セクションと同型の構成 (Problem → AC 例 → Matching specification) で追加し、スコープ制約 (フラット kebab-case キーのみ、真偽値のみ) を明記した。
- テストは 3 ケース (有効時マッチ / 無効時除外 / 属性なし無条件マッチ) を `tests/opportunistic-search.bats` に追加し、`WHOLEWORK_CONFIG_PATH` によるヘルメティックなオーバーライドパターン (既存の `get-config-value.bats` 等と同型) を踏襲した。

### Deferred Items
- #797 等、既存 observation AC への `config=` 属性の付与は本 Issue のスコープ外 (Spec Notes に明記済み)。follow-up Issue 化は本 PR 範囲外。
- `capabilities.*` ネストキーおよび enum 値キー (`auto-stop-at` 等) への対応拡張 (`config=key:value` 形式等) は将来の follow-up 候補として `modules/observation-trigger.md` に記録済み。

### Notes for Next Phase
- Behavioral Change Detection により `tests/observation-trigger.bats` が `opportunistic-search.sh` を参照していることが検出され、フルスイート (`bats tests/`, 1210 件) を実行して全件 PASS を確認済み。`/review`/`/verify` でも同様の再確認は不要 (CI で担保される)。
- Pre-merge AC 5 件はすべて PASS 判定済みで Issue の該当チェックボックスを更新済み。Post-merge の observation AC (`event=auto-run`) は本 PR merge 後、次回 `/auto` 完走時に発火する。
