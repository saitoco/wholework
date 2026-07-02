# Issue #875: auto: data-layer.md を廃止し session.md に Metrics 小節を機械生成埋め込み (view 層 SSoT 二重化解消)

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (Ambiguity Auto-Resolution: `docs/workflow.md` / `docs/ja/workflow.md` の AC 欠落を #854 precedent に倣い rubric + file_not_contains で補完。Triage: Type=Task / Size=L (PR route) / Value=3。AC Verify Command Audit: 5 パターン該当なし) / https://github.com/saitoco/wholework/issues/875#issuecomment-4862507823

## Overview

`/auto` セッションの view 層が session.md (人間可読ナラティブ) と data-layer.md (機械生成メトリクス) の 2 ファイルに二重化しており、data-layer.md の events.jsonl → 表変換ロジックが workflow 実態と乖離した品質バグ (session_id 継承 / PR-Issue mapping 欠如 / verify 未計上 等) を抱えている。

本 Issue は view 層 SSoT を session.md に一本化する。`scripts/get-auto-session-report.sh` に `--metrics-only` フラグを追加して `## Metrics` 小節を stdout に出力し、それを session.md に機械生成埋め込みする。独立 data-layer.md ファイルの生成を廃止し、過去の data-layer.md を一括削除する。データ層 SSoT (`events.jsonl` / `.tmp/auto-events.jsonl`) は変更しない。#854 (cross-session `_daily/` view 廃止) と同じ「使われない view 層を消す」パターンを session 内 view 層に適用する形。

## Changed Files

- `scripts/get-auto-session-report.sh`: `--metrics-only` フラグ追加 (stdout に `## Metrics` 小節を出力); `--output` フラグ / `OUTPUT_PATH` 変数 / `TODAY` によるパス生成 / `mkdir -p` / `cat > "$OUTPUT_PATH"` ファイル書き込み / "See also" cross-link ファイル追記ブロックを削除。bash 3.2+ 互換維持。
- `skills/auto/SKILL.md`: L3 auto-retrospective step を data-layer.md 独立生成 → `--metrics-only` 出力を session.md `## Metrics` 小節へ埋め込む形に変更。`data-layer.md` 参照を全削除。
- `skills/audit/SKILL.md`: auto-session Subcommand を session.md 内 `## Metrics` 小節参照に変更。`--output` 引数記述と `data-layer.md` 参照を全削除。description (frontmatter) と usage 行も更新。
- `docs/structure.md`: session ディレクトリツリーから `data-layer.md` 行を削除、session.md 行コメントに Metrics 埋め込みを反映、`get-auto-session-report.sh` 説明を更新。
- `docs/ja/structure.md`: 同上 (日本語ミラー、Japanese-format パターン維持)。
- `docs/workflow.md`: `/audit auto-session` 説明を "data-layer report" から session.md 内 `## Metrics` 小節参照に更新。
- `docs/ja/workflow.md`: 同上 ("data-layer レポート" を session.md `## Metrics` 小節参照に更新、Japanese-format 維持)。
- `docs/product.md`: `/audit` Terms 行の `/audit auto-session` 記述 (line 162 "existing data-layer report or fallback generation") を session.md `## Metrics` 小節参照に更新 (Steering Docs sync — §E doc-sweep 完遂のため auto-resolve で追加、Notes 参照)。
- `tests/get-auto-session-report.bats`: 全 `run` を `--metrics-only` (stdout assert) に書き換え、`--output`/`$OUTPUT_PATH`/`[ -f ... ]` を除去。cross-link "See also" テスト 2 件を削除 (機能廃止)。`## Metrics` 開始 + 必須小節 (Summary / Phase Activity Summary / Sub-Issue Completion Timeline / Token Usage Aggregate) の assert を維持・追加。
- `tests/audit-auto-session.bats`: 同様に `--metrics-only` へ書き換え (`--output`/`Report written to`/`Session Report.*<id>` heading assert 除去)。stale な `data-layer.md` コメントを更新。
- `docs/sessions/*/data-layer.md` (11 ファイル): 一括削除。過去 session の session.md への backfill は行わない (#854 と同方針、retro obsoleteance 許容)。

**No change needed (grep 確認済み):**
- `docs/tech.md` / `docs/ja/tech.md`: `WHOLEWORK_ISSUE_BODY_DIR` 環境変数の説明のみ。Verify Phase Residuals 小節 (verify-type breakdown) を `--metrics-only` 出力に維持するため env var 挙動は不変。変更不要。
- `modules/event-emission.md`: "per-skill data-layer reference" は概念語であり `data-layer.md` ファイル参照ではない。変更不要。
- `docs/reports/event-log-schema.md`: `--narrative-draft` 削除の歴史的記録 (#776)。変更不要。

## Implementation Steps

1. `scripts/get-auto-session-report.sh` 引数パース改修: `--metrics-only` を認識するフラグ (`METRICS_ONLY=true`) を追加。`--output` case とその usage 記述、`OUTPUT_PATH` 変数、report mode の `TODAY` パス生成 (`OUTPUT_PATH="docs/sessions/..."`)、`mkdir -p "$(dirname ...)"` を削除。ヘッダコメント (usage / options) を `--metrics-only` 前提に更新。(→ acceptance criteria 1, 2)
2. `scripts/get-auto-session-report.sh` レンダリング改修 (after 1): report mode の出力先を `cat > "$OUTPUT_PATH"` から `cat` (stdout) に変更。先頭行を `# /auto Session Report — ${SESSION_ID}` から `## Metrics` に変更し、直後にキャベアブロック (下記 Notes 参照) を挿入。既存の `## <section>` 見出しを `### <section>` に降格 (session.md `## Metrics` 配下に nest させるため)。`**Session start/end**` / `**Wall-clock**` / `**Route mix**` 行と全既存小節 (Summary / Phase Activity Summary / Sub-Issue Completion Timeline / Token Usage Aggregate / Recovery Events / Verify Phase Residuals / Concurrent Sessions Detected / Improvement Candidates Surfaced) を維持。末尾の L3 session.md "See also" cross-link 追記ブロック (`_l3_session_found` 探索と `>> "$OUTPUT_PATH"`) と `echo "Report written to: ..."` を削除。`--no-github` フラグは orthogonal に維持。(→ acceptance criteria 1, 2)
3. `skills/auto/SKILL.md` L3 Step 2 改修: "Generate data layer report" ブロック (`get-auto-session-report.sh ... --output "$SESSION_DIR/data-layer.md" --no-github` の retry-once + stderr log) を削除。session ディレクトリ作成と `events.jsonl` 抽出、Empty-dir guard は維持。(→ acceptance criteria 3)
4. `skills/auto/SKILL.md` L3 Step 3 (not-notable path) 改修 (after 3): commit 対象を `events.jsonl` のみとし、`git add "$SESSION_DIR"` / commit はそのまま (dir 内は events.jsonl)。出力メッセージ "L3 data layer committed (not notable — session.md skipped)." の "data layer" 表現を events ベースに更新 (`data-layer.md` 文字列を残さない)。(→ acceptance criteria 3)
5. `skills/auto/SKILL.md` L3 Step 4 (notable path, session.md 生成) 改修 (after 3): session.md 書き込み前に `get-auto-session-report.sh --metrics-only "$AUTO_SESSION_ID" --no-github` を実行し stdout を scratch ファイル `.tmp/auto-metrics-${AUTO_SESSION_ID}.md` に取得 (retry-once + stderr log、失敗時は Metrics 小節にフォールバック注記)。session.md テンプレートの title 直後・`## What worked` 直前に取得した `## Metrics` 小節を埋め込む。`## See also` の `[Data layer report](.../data-layer.md)` ブロックを削除。埋め込み後に scratch ファイルを削除。(→ acceptance criteria 3)
6. `skills/audit/SKILL.md` auto-session Subcommand 改修: (a) frontmatter description (line 3) と usage 行 (line 23) の `--output` / data-layer report 記述を session.md `## Metrics` 小節参照に更新; (b) "Output Template Structure" のパス記述 `docs/sessions/{...}/data-layer.md` を session.md `## Metrics` 小節に変更; (c) "Argument Parsing" から `--output` 行を削除; (d) "Existence Check" の glob 対象を `data-layer.md` から `session.md` に変更し、存在時は session.md 内 `## Metrics` 小節を表示; (e) "Step 1 (fallback)" の呼び出しを `--metrics-only` に変更 (`--output` 除去、`--no-github` は文脈条件を維持)。ファイル内 `data-layer.md` 文字列を全除去。(→ acceptance criteria 4)
7. `docs/structure.md` / `docs/ja/structure.md` 改修: session ディレクトリツリーの `data-layer.md` 行を削除。`session.md` 行コメントに Metrics 小節埋め込みを反映 (例: session.md 行に「Metrics 小節を機械生成埋め込み」を追記)。`scripts/get-auto-session-report.sh` の説明行を `--metrics-only` による Metrics 小節生成に更新。ja は Japanese-format を維持。(→ acceptance criteria 6)
8. `docs/workflow.md` / `docs/ja/workflow.md` 改修: `/audit auto-session` の説明を "data-layer report" / "data-layer レポート" 参照から「session.md 内 `## Metrics` 小節を表示、なければ `--metrics-only` で on-demand 生成」に更新。列挙小節 (Phase Activity Summary / Sub-Issue Completion Timeline / Token Usage Aggregate / Verify Phase Residuals / Recovery Events) は維持。ja は Japanese-format を維持。(→ acceptance criteria 7)
9. `docs/product.md` 改修: `/audit` Terms 行 (line 162) の `/audit auto-session (existing data-layer report or fallback generation from .tmp/auto-events.jsonl)` を session.md `## Metrics` 小節参照 (例: `session.md 内 Metrics 小節の表示、なければ .tmp/auto-events.jsonl からの fallback 生成`) に更新。(→ Notes auto-resolve item)
10. `tests/get-auto-session-report.bats` / `tests/audit-auto-session.bats` 書き換え + `docs/sessions/*/data-layer.md` 削除: 両 bats の全 `run bash "$SCRIPT" <id> --output "$OUTPUT_PATH" --no-github` を `run bash "$SCRIPT" <id> --metrics-only --no-github` に変更し、`[ -f "$OUTPUT_PATH" ]` / `grep -q "..." "$OUTPUT_PATH"` を `echo "$output" | grep -q "..."` に、`[[ "$output" == *"Report written to"* ]]` と `Session Report.*<id>` heading assert を除去。`get-auto-session-report.bats` の cross-link "See also" テスト 2 件を削除 (機能廃止 — 保持シナリオなし)。`## Metrics` 先頭行 assert と必須小節 (Summary / Phase Activity Summary / Sub-Issue Completion Timeline / Token Usage Aggregate) assert を追加/維持。stale な `data-layer.md` コメントを session.md/Metrics に更新。最後に `docs/sessions/*/data-layer.md` (11 ファイル) を `git rm` で一括削除。(→ acceptance criteria 5, 8, 9)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/get-auto-session-report.sh に --metrics-only フラグが実装されており、実行すると Summary/Phase Activity Summary/Sub-Issue Completion Timeline/Token Usage Aggregate を含む markdown 小節を stdout に出力する" --> `scripts/get-auto-session-report.sh` に `--metrics-only` フラグが追加され `## Metrics` から始まる markdown 小節を stdout 出力する
- <!-- verify: rubric "scripts/get-auto-session-report.sh から data-layer.md を独立ファイルとして生成する処理 (--output でファイルパス指定 + ファイル書き込み) が削除されており、--metrics-only モードもしくは同等の埋め込み用出力のみが残る" --> `--output` 経由の `data-layer.md` 独立ファイル出力ロジックが削除されている
- <!-- verify: rubric "skills/auto/SKILL.md L3 auto-retrospective step が data-layer.md を独立生成する記述ではなく、get-auto-session-report.sh --metrics-only の出力を session.md 内 ## Metrics 小節に埋め込む記述に変更されている" --> <!-- verify: file_not_contains "skills/auto/SKILL.md" "data-layer.md" --> `skills/auto/SKILL.md` L3 step が `--metrics-only` を使い session.md 内 `## Metrics` 小節に埋め込む記述に変更されている
- <!-- verify: rubric "skills/audit/SKILL.md の per-session mode で data-layer.md ではなく session.md 内 ## Metrics 小節を読む記述に変更されている" --> <!-- verify: file_not_contains "skills/audit/SKILL.md" "data-layer.md" --> `skills/audit/SKILL.md` per-session mode が session.md 内 Metrics 小節を参照する記述に変更されている
- <!-- verify: rubric "find docs/sessions -name data-layer.md の結果が空である (過去 session の data-layer.md も全削除)" --> `docs/sessions/` 配下の全 `data-layer.md` ファイルが削除されている
- <!-- verify: file_not_contains "docs/structure.md" "data-layer.md" --> <!-- verify: file_not_contains "docs/ja/structure.md" "data-layer.md" --> `docs/structure.md` / `docs/ja/structure.md` から `data-layer.md` 記述が削除されている
- <!-- verify: rubric "docs/workflow.md および docs/ja/workflow.md の /audit auto-session の説明が、data-layer レポートではなく session.md 内 Metrics 小節を参照する内容に更新されている" --> <!-- verify: file_not_contains "docs/workflow.md" "data-layer report" --> <!-- verify: file_not_contains "docs/ja/workflow.md" "data-layer レポート" --> `docs/workflow.md` / `docs/ja/workflow.md` の `/audit auto-session` 節が session.md 内 Metrics 小節を参照する記述に更新されている
- <!-- verify: command "bats tests/get-auto-session-report.bats" --> bats test で `get-auto-session-report.sh --metrics-only` の出力に必須小節 (Summary / Phase Activity / Sub-Issue Completion / Token Usage) が含まれることを assert する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats test suite 全体が緑のまま

### Post-merge

- 次回 `/auto --batch` 実行で `docs/sessions/{ID-DATE}/session.md` に `## Metrics` 小節が機械生成埋め込みされることを観察 (verify-type: observation event=auto-run)
- `docs/sessions/{ID-DATE}/` 配下に新 `data-layer.md` ファイルが生成されないことを観察 (verify-type: observation event=auto-run)

## Tool Dependencies

### Bash Command Patterns
- none (`${CLAUDE_PLUGIN_ROOT}/scripts/get-auto-session-report.sh:*` は既に `skills/auto/SKILL.md` および `skills/audit/SKILL.md` の `allowed-tools` に登録済み。新規 script / gh パターン追加なし)

### Built-in Tools
- none (Read / Write / Edit / Bash / Glob / Grep いずれも両 SKILL.md の `allowed-tools` に登録済み)

### MCP Tools
- none

## Notes

### Auto-Resolved Ambiguity Points (非対話モード)

1. **非 notable session の Metrics 永続化** — data-layer.md 廃止後、not-notable な batch/XL session は session.md が生成されないため view 層メトリクスが永続化されなくなる。**解決**: 許容する。データ層 SSoT (`events.jsonl` は commit 済み) からいつでも再生成可能で、`/audit auto-session` が on-demand で `--metrics-only` 生成する。#854 の「冗長な view を永続化しない」哲学および本 Issue の Purpose と整合。
2. **Metrics 小節配下の見出しレベル** — session.md `## Metrics` に埋め込む際、既存の `## Summary` / `## Phase Activity Summary` 等は `### ` に降格する。**解決**: 降格する。降格しないと `## Summary` が session.md 内で `## Metrics` の兄弟 h2 となり文書階層が崩れる。Markdown 構造規約から一意に推論可能。テキスト grep (小節名文字列) は見出しレベルに依存しないため verify command への影響なし。
3. **`--metrics-only` 出力の小節スコープ** — Issue A の "含める内容" は 6 項目だが現行 report は Recovery Events / Verify Phase Residuals / Concurrent Sessions Detected / Improvement Candidates Surfaced も持つ。**解決**: 全小節を維持する。Issue の列挙は必須最小セット (含める内容) であり排他リストではない。既存 bats が Recovery Events / Verify Phase Residuals / Improvement Candidates の存在を assert しており、これらは診断価値を持つ。削減はカバレッジと情報を失うだけで利得なし。
4. **`docs/product.md` の doc-sweep 補完** — product.md line 162 が `/audit auto-session (existing data-layer report ...)` を参照しており本変更後に事実誤りとなる。§E doc-sweep (structure.md/workflow.md) と同クラスの stale 参照。**解決**: Changed Files + Implementation Step 9 に追加して修正する。Issue body の Pre-merge AC 集合 (triage 済み 9 件) は変更せず (scope 規律 + 長大 body 再構築リスク回避)、Implementation Steps でカバー。#854 retrospective が確立した「Proposal に明記された doc は完遂する」学びに沿う。

### Metrics 小節キャベア (Implementation Step 2 で `## Metrics` 冒頭に挿入)

以下 3 点を `## Metrics` 見出し直後にキャベア (blockquote 等) として明記する (Issue Proposal A、Out of Scope の既知構造欠陥に対応):
- verify phase は `/verify` が wrapper なし Skill invocation のため `phase_start/complete` events を emit せず計上されない旨
- 手で介入した silent no-op 回復等は Tier 1/2/3 machinery を経由しないため recovery events に反映されない旨
- Phase breakdown の順序は event 発生順である旨

これらの根本解決 (verify phase event emission / PR-Issue mapping / subprocess session_id 継承) は本 Issue scope 外 (別 Issue)。

### 実装上の注意

- `--metrics-only` 出力の scratch 取得は `.tmp/auto-metrics-${AUTO_SESSION_ID}.md` を使用 (`.tmp/` は `.gitignore` 済みで commit されない)。既存 SKILL.md が subprocess stderr を `2>` でリダイレクトしている前例に倣い、subprocess stdout の `>` リダイレクト取得は許容 (エージェントによる temp コンテンツ生成の redirect 禁止規約とは別)。
- SKILL.md 本文編集時は `validate-skill-syntax.py` MUST 制約を遵守: 半角 `!` 禁止 (コードフェンス/インラインコード/HTML コメント外)、本文への triple backtick 直書き禁止、frontmatter は単一行。
- `--output` 削除後、report mode (session-id あり) の唯一の出力形態は stdout への `## Metrics` 小節。`--metrics-only` は明示的セレクタフラグとして全 caller (auto/audit SKILL.md、bats) が渡す。
- `--output`/`OUTPUT_PATH` 削除に伴い両 bats の `setup()` 内 `export OUTPUT_PATH=...` は未使用となる (削除可)。`audit-auto-session.bats` の `teardown()` の `rm -f "$OUTPUT_PATH"` も同様。
- `get-auto-session-report.bats` の cross-link テスト 2 件削除は機能廃止に伴うもので、保持すべきシナリオはない (#526 test replacement 観点で確認済 — cross-link 追記機能自体が消滅)。
