# Issue #1407: config: .wholework.yml の未知/typoキーを検出する schema validation を追加

## Overview

`.wholework.yml` は Wholework 全体の唯一の設定面であり、`modules/detect-config-markers.md` が Marker Definition Table で約39件のキーを SSoT として定義しているが、`scripts/get-config-value.sh` はキー名自体の存在検証を行わず、未知キー (typo 含む) を常に既定値へ静かにフォールバックさせる (例: `autonomy:` を `autonomy-tier:` と誤記しても警告なく `AUTONOMY_TIER=L1` にフォールバックする)。

本 Issue はこの silent failure を防ぐため、`.wholework.yml` の未知/typo したトップレベルキーを検出し警告する CI チェックスクリプトを追加する。Issue Retrospective で自動解決済みの2方針 (詳細は下記 Notes) に従い、既存の `scripts/check-forbidden-expressions.sh` + `.github/workflows/test.yml` パターン (push/PR ごとに自動実行される独立スクリプト) に倣い、`modules/detect-config-markers.md` の Marker Definition Table を実行時に動的参照することで、別途キー一覧をハードコードした場合の SSoT drift を回避する。

検証対象は AC1 の rubric 文言どおりトップレベルキーのみ (`capabilities.*` 等ネストされた子キーの typo 検出は範囲外)。

## Changed Files

- `scripts/check-config-schema.sh`: new file — `.wholework.yml` のトップレベルキーを `modules/detect-config-markers.md` の Marker Definition Table と突き合わせ、未知キーを警告する。bash 3.2+ compatible
- `tests/check-config-schema.bats`: new file — 新規スクリプトの新規ロジック (未知キー検出・既知キー通過・ネスト子キー除外・コメント行除外・ファイル不在時の挙動) を検証する新規テストケース
- `.github/workflows/test.yml`: add `check-config-schema` CI job — `check-forbidden-expressions` ジョブと同構造で `bash scripts/check-config-schema.sh` を push/PR ごとに実行
- `docs/tech.md`: add `## Config Schema Validation` section (`## Forbidden Expressions` の直後) — トリガー地点 (CI) と警告メッセージ形式をドキュメント化
- `docs/ja/tech.md`: `## 禁止表現` の直後に対応する日本語セクションを追加 (`docs/translation-workflow.md` 同期義務)
- `modules/detect-config-markers.md`: 冒頭の既存 `docs/guide/customization.md` ポインタ行の直後に `docs/tech.md § Config Schema Validation` への1行ポインタを追加
- `docs/structure.md`: Directory Layout の `scripts/` ファイル数 91→92、`tests/` ファイル数 127→128 に更新。Scripts § Tooling リストに新規スクリプトの説明行を追加。CI Workflows の `test.yml` 説明文に "config schema check" を追記
- `docs/ja/structure.md`: 上記と同内容を日本語で反映 (`docs/translation-workflow.md` 同期義務) — ファイル数 91→92 ファイル、127→128 ファイル、Tooling リスト追加行、test.yml 説明文追記

## Implementation Steps

1. `scripts/check-config-schema.sh` を新規作成する (→ acceptance criteria AC1)。
   - `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` で自スクリプトの位置を解決する (`apply-run-fact-match.sh` 等と同じ規約)。`modules/detect-config-markers.md` は `$SCRIPT_DIR/../modules/detect-config-markers.md` として常に実ファイルを参照する (CWD に依存しない)。`.wholework.yml` は `${WHOLEWORK_CONFIG_PATH:-.wholework.yml}` (CWD 相対、`get-config-value.sh` と同じ override 規約) を読む。
   - `.wholework.yml` が存在しない場合、または `modules/detect-config-markers.md` が見つからない場合は exit 0 (何もチェックせず正常終了)。
   - 既知キー集合の抽出: `modules/detect-config-markers.md` の `### Marker Definition Table` 見出し以降、`| \`` で始まる行が途切れるまでを awk で抽出し、各行の先頭バッククォート内の文字列を sed で取り出し、`.` 以降を除去してトップレベルキー名に正規化 (例: `capabilities.browser` → `capabilities`、`auto-retry-on-fail.enabled` → `auto-retry-on-fail`) した上で `sort -u` により重複排除する。
   - 実キー集合の抽出: `.wholework.yml` から行頭 (インデントなし) が `^[A-Za-z0-9_-]+:` にマッチする行のみを `grep`/`sed` で抽出する (コメント行 `#...` とネストされた子キー行 (インデントあり) は正規表現の性質上自然に除外される)。
   - 実キーを既知キー集合と突き合わせ (`grep -Fxq`)、集合に含まれないキーごとに次の形式で標準出力へ警告する: `Unknown key '<key>' in <config-file> (not found in modules/detect-config-markers.md's Marker Definition Table). Check for a typo, or add it to the table if intentional.` 1件以上検出した場合は exit 1。
   - 連想配列・`mapfile` 等の bash 4+ 専用機能は使用しない (bash 3.2 互換)。

2. (after 1) `tests/check-config-schema.bats` を新規作成する (→ AC1、新規ロジックのテスト要件)。
   - `tests/check-forbidden-expressions.bats`/`tests/get-config-value.bats` と同じ規約: `SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-config-schema.sh"` を定義し、`setup()` で `$BATS_TEST_TMPDIR` へ `cd` する。
   - `modules/detect-config-markers.md` はテスト用フィクスチャを作らず、`WHOLEWORK_SCRIPT_DIR` を未設定のままにして実リポジトリの `modules/detect-config-markers.md` (動的参照の実物) を SCRIPT_DIR 相対解決させる。`.wholework.yml` のみ各テストケースで `$BATS_TEST_TMPDIR` にフィクスチャとして書く (入力データ形式: 通常の `key: value` フラット行、`#` で始まるコメント行、2スペースインデントのネストブロックの3種)。
   - 最低限のテストケース: (a) `.wholework.yml` 不在 → exit 0。(b) 実在する既知キーのみ (例 `spec-path: docs/spec`، `autonomy: L3`) → exit 0 かつ `Unknown key` を含まない。(c) Issue 本文の例に合わせた typo キー `autonomy-tier: L2` → exit 1 かつ出力に `Unknown key` と `autonomy-tier` を含む。(d) 既知セクションのネスト子キー (`capabilities:` ブロック配下に `browser: true`) はトップレベル `capabilities` として既知判定され exit 0。(e) コメント行 (`# key: value` 形式) はキーとして誤検出されず exit 0。

3. (after 1) (parallel with 2) `.github/workflows/test.yml` に `check-config-schema` ジョブを追加する (→ AC1, AC2 の検証タイミング)。挿入位置: `check-forbidden-expressions` ジョブブロックの直後、`bare-bracket-assertions` ジョブの直前。既存の `check-forbidden-expressions` ジョブと同構造 (`runs-on: ubuntu-latest`、`actions/checkout@v4`、`run: bash scripts/check-config-schema.sh`) を用いる。

4. (parallel with 1-3) `docs/tech.md` の `## Forbidden Expressions` セクション直後に `## Config Schema Validation` セクションを追加する (→ AC2)。トリガー地点 (CI: `.github/workflows/test.yml` の `check-config-schema` ジョブが push/PR ごとに自動実行)、検証スコープ (トップレベルキーのみ)、警告メッセージの形式 (ステップ1の `Unknown key '<key>' in <config-file> (not found in modules/detect-config-markers.md's Marker Definition Table). Check for a typo, or add it to the table if intentional.` 文言) を記載する。あわせて `modules/detect-config-markers.md` 冒頭の既存 `docs/guide/customization.md` へのポインタ行の直後に、`docs/tech.md § Config Schema Validation` への1行ポインタを追加する (→ AC2 の「reachable from modules/detect-config-markers.md」充足)。`docs/translation-workflow.md` の同期義務に従い、`docs/ja/tech.md` の `## 禁止表現` 直後にも対応する日本語セクションを追加する。

5. (after 1, 3) `docs/structure.md` を更新する (→ SHOULD レベルのドキュメント整合性)。Directory Layout の `scripts/ # ... (91 files)` → `(92 files)`、`tests/ # ... (127 files)` → `(128 files)` に更新し、Scripts § Tooling リストに `scripts/check-config-schema.sh` の説明行を追加し、CI Workflows の `.github/workflows/test.yml` 説明文に "config schema check" を追記する。`docs/translation-workflow.md` の同期義務に従い、`docs/ja/structure.md` の対応箇所 (ファイル数コメント2件、Tooling リスト、test.yml 説明文) も同時に更新する。

## Verification

### Pre-merge

- <!-- verify: rubric "a mechanism exists (e.g. a validation script, or a check invoked from an existing skill flow such as /doc init or /audit) that compares the top-level keys actually present in .wholework.yml against the known key list documented in modules/detect-config-markers.md, and surfaces a visible warning for any key that does not match" --> `.wholework.yml` の未知キーを検出して警告する仕組みが実装されている
- <!-- verify: rubric "the new validation mechanism is documented (its trigger point, e.g. which skill/command runs it, and what the warning looks like) somewhere reachable from modules/detect-config-markers.md or docs/tech.md" --> 検証タイミングと警告内容がドキュメント化されている

### Post-merge

- 意図的に typo したキー (例: `autonomy-tier:`) を含む `.wholework.yml` で実際に警告が出力されることを確認

## Notes

- **Auto-Resolved Ambiguity Points (`/issue` フェーズより転記)**: (1) 検証のトリガー地点は `/doc init`/`/audit` 起動時のみのオプトイン検証ではなく、`check-forbidden-expressions.sh` + `test.yml` の既存パターン (CI で毎回自動実行される独立スクリプト) に倣う。オプトイン方式では `.wholework.yml` を直接編集した場合に検出できず、silent failure 防止という目的を達成できないため。(2) 既知キー一覧は `modules/detect-config-markers.md` の Marker Definition Table を単一の真実源として動的参照する。別途ハードコードすると、その一覧自体が本 Issue と同種の SSoT drift を起こしうるため。本 Spec はこの2方針をそのまま設計に採用した。
- **検証スコープ**: AC1 の rubric 文言 ("the top-level keys actually present") に従い、トップレベルキーのみを検証対象とする。`capabilities.*` 等のネストされた子キーの typo 検出は範囲外 (将来必要になった場合は別 Issue で検討)。
- **Fail-safe critical 判定 (該当なしと判断)**: `scripts/check-config-schema.sh` は CI 上の lint/warning チェックであり、`check-forbidden-expressions.sh`/`check-bare-bracket-assertions.sh` と同種の非本番影響スクリプトである。マージ可否を機械的に決定する gate (`check-pre-merge-ac.sh` 等) や本番状態を変更する validator ではないため、fail-safe critical の3基準 (a) gate (b) accept/reject validator (c) fail-open 設計、のいずれにも該当しないと判断した。
- **新規ロジックのテスト要件**: `scripts/check-config-schema.sh` は既存スクリプトへの分岐追加ではなく完全新規ファイルのため「既存スクリプトへの新規分岐追加」チェックの厳密な対象ではないが、同等の趣旨で `tests/check-config-schema.bats` に新規ロジック (未知キー検出・既知キー通過・ネスト子キー除外・コメント行除外・ファイル不在時の挙動) を検証する新規テストケースを追加したうえでスイートが PASS することを実装ステップ2の要件とした (`SPEC_DEPTH=light` のため Step 13 の spec retrospective は省略し、この要約を本 Notes に記録する)。
- **`verify-type: opportunistic` の整合性 (軽微な観察)**: Post-merge AC の `verify-type: opportunistic` タグは `modules/verify-classifier.md` の厳密な定義 ("verify X when `/skill-name` is run" パターン) と完全一致はしない (実態は「CI 実行時に」観測される一度きりの確認に近い) が、Issue 本文で既に確定済みのタグであり AC 文言自体は不変のため、そのまま踏襲した。
- **Steering Docs sync candidate 調査結果**: `modules/detect-config-markers.md` への参照は23件以上の既存ファイルに及ぶが、本 Issue の変更はキー一覧/変数セマンティクスを変更せず、ファイル冒頭への1行ポインタ追加のみのため、上記 Changed Files 以外の追加更新は不要と判断した。`docs/versioning.md` Gate 4b (リリース時の手動チェックリスト、`docs/guide/customization.md` § Available Keys と `modules/detect-config-markers.md` の突き合わせ) は本 Issue とは別目的 (2ドキュメント間の整合性、本 Issue は `.wholework.yml` 実体とドキュメントの整合性) のため変更不要と判断した。
- **Consumed Comments**: `/spec` フェーズ開始時点で新規コメントなし (Issue Retrospective コメント1件のみで、Issue 本文の Auto-Resolved Ambiguity Points と同内容のため新規指示なし)。詳細は本ファイル末尾の `## Consumed Comments` セクションを参照。

## Consumed Comments
No new comments since last phase.
