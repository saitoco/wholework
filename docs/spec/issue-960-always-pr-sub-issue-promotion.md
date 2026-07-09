# Issue #960: auto: run-auto-sub.sh に ALWAYS_PR promotion ロジックを追加

## Overview

`.wholework.yml` に `always-pr: true` を設定したプロジェクトで `/auto` を XL Issue に対して実行すると、Size=XS/S の sub-issue が `run-auto-sub.sh` 経由で **PR もレビューも経ずに直接 main へコミットされる**。`skills/auto/SKILL.md` Step 2 (単一 Issue パス) には ALWAYS_PR promotion ロジック (patch route → pr route への昇格) が実装済みだが、XL Issue の sub-issue 並列実行を担う `scripts/run-auto-sub.sh` には同等のロジックが存在しない。本 Issue では `run-auto-sub.sh` が `.wholework.yml` の `always-pr` を読み込み、Size ベースの route 決定時に同じ promotion ロジックを適用できるようにする。

## Reproduction Steps

1. `.wholework.yml` に `always-pr: true` を設定したプロジェクトで、Size=XS または S の sub-issue を含む XL Issue に対して `/auto` を実行する
2. `run-auto-sub.sh` が該当 sub-issue の Size (XS/S) を取得し、`case "$SIZE" in XS|S)` 分岐に入る
3. `run-code.sh --patch` (main への直接コミット、PR/レビューなし) が実行される — `always-pr: true` の設定が無視される

## Root Cause

`run-auto-sub.sh` は `.wholework.yml` を一切読み込んでおらず (`get-config-value.sh` 未使用)、`always-pr`/`ALWAYS_PR` という文字列も現状のコードに存在しない (`grep -n "always-pr|ALWAYS_PR" scripts/run-auto-sub.sh` が 0 件であることをコードベース調査で確認済み)。

一方、以下の2箇所には既に同種の promotion ロジックが実装されている:
- `skills/auto/SKILL.md` Step 2 (単一 Issue の `/auto N` パス): `ALWAYS_PR=true` かつ ROUTE が patch (Size XS/S) の場合に pr route へ昇格
- `skills/code/SKILL.md` Step 0 (`/code` 直接呼び出しパス): 同様の flag precedence ロジック

`run-auto-sub.sh` は XL Issue の sub-issue 並列実行を担う独立したシェルスクリプトであり、上記いずれの LLM 駆動ロジックからも独立して Size ベースの route (`case "$SIZE" in XS|S|M|L`) を自前で決定している。そのため、XL 経路 (sub-issue 実行) と単一 Issue 経路とで `always-pr` の扱いに一貫性がなく、Size XS/S の sub-issue は `always-pr: true` 設定下でも常に patch route (直接コミット) を選択してしまう。

## Changed Files

- `scripts/run-auto-sub.sh`: Size 判定 (`case "$SIZE" in`) の直前に `ALWAYS_PR` 設定読み込みと patch→pr promotion ロジックを追加 — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: `setup()` に `get-config-value.sh` の実スクリプトコピー (mock) を追加し、`always-pr: true` 設定下での Size XS/S promotion を検証する bats テストを2件追加 — bash 3.2+ 互換
- `skills/auto/SKILL.md`: XL route セクション (`run-auto-sub.sh` 呼び出し箇所) に、sub-issue 実行でも Step 2 と同じ ALWAYS_PR promotion ロジックが適用される旨の注記を追加

## Implementation Steps

1. `scripts/run-auto-sub.sh`: Size 判定ロジックに ALWAYS_PR promotion を追加する (→ 受入基準 AC1, AC2)
   - 挿入位置: `echo "${LOG_PREFIX} Size: ${SIZE}"` の直後、`# Execute phases according to Size-based route.` コメント (および `case "$SIZE" in`) の直前
   - `run-code.sh` / `run-issue.sh` / `run-spec.sh` / `run-merge.sh` / `run-review.sh` が既に踏襲している `get-config-value.sh` 読み込みパターンを採用する:
     ```bash
     ALWAYS_PR=$("$SCRIPT_DIR/get-config-value.sh" always-pr false 2>/dev/null || echo false)
     ```
   - `SIZE` 自体は Size 表示 (`Size: ${SIZE}` ログ) と `sub_start`/`size_refresh` イベントの正確性を保つため書き換えない。代わりに新しい変数 `EFFECTIVE_SIZE` を導入し、これを後続の `case` 文の分岐対象にする:
     ```bash
     EFFECTIVE_SIZE="$SIZE"
     if [[ "$ALWAYS_PR" == "true" ]] && [[ "$SIZE" =~ ^(XS|S)$ ]]; then
       echo "${LOG_PREFIX} always-pr: true is set in .wholework.yml. Promoting to pr route."
       emit_event "always_pr_promotion" "size=${SIZE}"
       EFFECTIVE_SIZE="M"
     fi
     ```
   - 既存の `case "$SIZE" in` を `case "$EFFECTIVE_SIZE" in` に変更する。`EFFECTIVE_SIZE="M"` に昇格した場合、既存の `M)` 分岐 (worktree 名は patch/pr route 共通の `code/issue-$NUMBER` のため衝突なし、`run-code.sh --pr` → `run-review.sh --light` → `run-merge.sh`) がそのまま再利用される
   - ログ出力・`emit_event` の形式は、既存の `size_refresh` (Post-spec route demotion/upgrade) ログパターンを踏襲する
2. `tests/run-auto-sub.bats`: promotion ロジックのテストを追加する (→ AC1, AC2 の回帰防止) (after 1)
   - `setup()` 内、既存の `retry-on-kill.sh` 実スクリプトコピー (L110-111 付近) と同じパターンで `get-config-value.sh` の実スクリプトを `$MOCK_DIR` にコピーする (stub ではなく実スクリプト — `.wholework.yml` の内容をテストごとに変えて検証できるようにするため):
     ```bash
     cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/get-config-value.sh" "$MOCK_DIR/get-config-value.sh"
     chmod +x "$MOCK_DIR/get-config-value.sh"
     ```
   - 新規テストケースを2件追加する (両方とも `echo "always-pr: true" >> "$BATS_TEST_TMPDIR/.wholework.yml"` で `setup()` が作成した `.wholework.yml` に追記してから実行):
     - `"Size XS + always-pr: true: promoted to pr route (run-code.sh --pr, run-review.sh, run-merge.sh called)"` — 既存の "Size XS" テスト (`run-code.sh --patch` を検証) と対になる形で、`get-issue-size.sh` が `XS` を返す状態で `run-code.sh --pr` が呼ばれ `run-review.sh`/`run-merge.sh` も呼ばれることを検証
     - `"Size S + always-pr: true: promoted to pr route (run-code.sh --pr, run-review.sh, run-merge.sh called)"` — 同様に Size `S` で検証
   - 既存の "Size XS"/"Size S" テスト (`always-pr` 未設定時に `run-code.sh --patch` が呼ばれ `run-review.sh`/`run-merge.sh` が呼ばれないことを検証) は `get-config-value.sh` 追加後も無変更のまま回帰テストとして機能する (`.wholework.yml` に `always-pr` キーがない場合、`get-config-value.sh always-pr false` はデフォルト値 `false` を返すため)
3. `skills/auto/SKILL.md`: XL route セクションに ALWAYS_PR promotion 注記を追加する (→ AC3) (parallel with 1, 2)
   - 挿入位置: `**XL route: sub-issue dependency graph with parallel execution (...)：**` の見出し直後、`Read ${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md ...` (AUTO_MAX_CONCURRENT retain) の行の前
   - 追加文面 (趣旨): `run-auto-sub.sh` は `.wholework.yml` の `ALWAYS_PR` を独自に読み込み (`get-config-value.sh always-pr false`)、sub-issue ごとの Size 判定時に Step 2 と同じ patch→pr promotion ロジックを適用する。これにより単一 Issue パスと XL sub-issue パスで `always-pr` の扱いが一貫する旨を明記する

## Verification

### Pre-merge
- <!-- verify: grep "always-pr|ALWAYS_PR" "scripts/run-auto-sub.sh" --> `run-auto-sub.sh` が `always-pr` 設定を参照している
- <!-- verify: rubric "run-auto-sub.sh の Size 判定ロジックが、ALWAYS_PR=true の場合に Size XS/S であっても patch ルートではなく pr ルート (run-code.sh --pr) を選択するよう promotion される" --> Size XS/S でも `always-pr: true` の場合は pr ルートが選択される
- <!-- verify: rubric "skills/auto/SKILL.md の XL route (run-auto-sub.sh 呼び出し) セクションが、Step 2 の ALWAYS_PR promotion ロジックが sub-issue 実行にも適用されることを明記している" --> SKILL.md 側にも XL 経路での適用が明記されている

### Post-merge
なし

## Notes

- **Auto-Resolved Ambiguity Points (Issue 側で決定済み、/spec では再検討しない)**:
  - Config 読み込み方法: `get-config-value.sh always-pr false` パターンを採用 (他候補: 独自 grep/awk パース — 既存スクリプト群との一貫性を優先し不採用)
  - Promotion ログ出力形式: 既存の `size_refresh` (Post-spec route demotion/upgrade) ログパターン (`echo "${LOG_PREFIX} ..."` + `emit_event`) を踏襲 (他候補: SKILL.md の warning 文言のみで `emit_event` は発行しない — 既存の観測性パターンとの一貫性を優先し不採用)
- **`emit_event` イベント名**: 新規に `always_pr_promotion` を採用。`modules/event-emission.md` は `phase_start`/`phase_complete`/`wrapper_exit`/`token_usage` のみを正式登録対象とする SSoT であり、`size_refresh` や `sub_start` など本ファイル内の他の ad-hoc イベントも同モジュールに未登録のため、今回も同モジュールの更新は不要と判断した
- **ドキュメント同期範囲の判断**: `docs/workflow.md` / `docs/guide/customization.md` (および `docs/ja/*` 対訳) は既に `always-pr: true` を「Size に関わらず全 Issue を PR route で実行する」と記述しており、この契約自体は変更されない (実装ギャップの解消であり、ユーザー向け仕様の変更ではない) ため、これらのファイルは Changed Files に含めない
- **EFFECTIVE_SIZE 命名**: `run-auto-sub.sh` には元々 `ROUTE` 相当の変数がなく `SIZE` 文字列に直接 `case` させているため、`skills/auto/SKILL.md` Step 2 の `EFFECTIVE_STOP_AT` (config/flag 解決後の実効値) と同じ命名慣習に倣い `EFFECTIVE_SIZE` とした
- **Related Issues**: #954, #955 (同セッションで発見した別ギャップ、本 Issue の scope 外)

## Consumed Comments

- saito (MEMBER, first-class) — Issue Retrospective: Title/Type/Size/Value 決定根拠、Auto-Resolve Log (config 読み込みパターン・ログ形式の2件)、AC1 の BRE→ERE 修正、Background factual claim の検証結果を記録。新規要件の追加なし — https://github.com/saitoco/wholework/issues/960#issuecomment-4925611232
