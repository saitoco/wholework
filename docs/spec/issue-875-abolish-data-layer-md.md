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

## issue retrospective

### Ambiguity Auto-Resolution

- **`docs/workflow.md` / `docs/ja/workflow.md` 更新の AC 欠落**: Proposal §E は `docs/workflow.md` / `docs/ja/workflow.md` の `/audit auto-session` 節の記述更新を明記していたが、対応する Pre-merge AC が存在しなかった (`docs/structure.md` は AC 化済みだったが `docs/workflow.md` は未記載)。
  - コード調査で両ファイルの `/audit auto-session` 説明が現在 "data-layer レポート" (`docs/ja/workflow.md` L159) / "data-layer report" (`docs/workflow.md` L166) を参照していることを確認した。
  - #854 (同パターンの precedent、cross-session `_daily/` view 廃止) の Issue Retrospective でも同種の「Proposal に明記されているが AC 未記載」ギャップが `docs/structure.md` 系で発生し、triage 後の追加 AC で補完されていた。同じ判断基準を適用し、rubric + `file_not_contains` の AC を追加した。
  - 他の選択肢 (AC を追加せず `/verify` の AI fallback に委ねる) は、structure.md との一貫性を欠き、#854 retrospective の学びと矛盾するため不採用。

### Triage 結果

- Type: Task (廃止・統合系のメンテナンス変更)
- Size: L (PR route)。#854 (同スコープ規模の precedent) と同じ Size 判定を適用
- Value: 3 (Impact=2: skills/scripts/docs 横断の shared component、Alignment=2: Vision の "Governance and verification depth" と中程度整合)
- 重複候補・停滞・依存関係の異常: なし

### AC Verify Command Audit

`skills/triage/skill-dev-verify-audit.md` の 5 パターン (grep 引数順・常時PASS/FAIL・patch route不整合・破壊的コマンド) をチェックし、該当なし。全 rubric/file_not_contains/command/github_check verify command は Size=L (PR route) と整合している。

## spec retrospective

### Minor observations

- `tests/audit-auto-session.bats` も同じ `get-auto-session-report.sh` を `--output` 経由で叩いているが、どの Pre-merge AC にも名指しされていない。`--output` 削除でこのファイルは壊れるが、それを捕えるのは「bats suite 全体が緑」の github_check AC のみ。コード調査で両 bats を洗い出さないと code phase で見落としうる構造的リスク。両ファイルを Changed Files に明記した。
- `docs/product.md` L162 が `/audit auto-session (existing data-layer report ...)` を参照しているが、Issue §E doc-sweep にも AC にも含まれていなかった。上記 workflow.md ギャップと同クラス (Proposal doc-sweep に一貫性がない)。Symbol impact discovery grep で拾い、Changed Files + Implementation Step 9 で補完した。

### Judgment rationale

- `--metrics-only` 出力に現行 report の全小節 (Recovery Events / Verify Phase Residuals / Concurrent Sessions / Improvement Candidates を含む) を維持した。Issue A の "含める内容" 6 項目は必須最小セットであり排他リストではなく、既存 bats がこれら追加小節の存在を assert しているため、削減は情報とカバレッジを失うだけで利得がない。
- session.md `## Metrics` 配下に nest させるため既存 `## <section>` 見出しを `### ` に降格する設計とした。テキスト grep (小節名) は見出しレベルに依存しないため verify command への副作用はない。
- `docs/product.md` は pre-merge AC 化せず Changed Files + Implementation Step のみでカバーした。triage 済み Issue body AC 集合 (9 件) を非対話モードで書き換える scope リスクを避けつつ doc-sweep を完遂する判断。verify の `/audit drift` が残存 stale を二次的に捕捉する。

### Uncertainty resolution

- 非 notable batch/XL session は session.md が生成されないため data-layer.md 廃止後は view 層メトリクスが永続化されない、という懸念を「許容 (events.jsonl から再生成可能、`/audit auto-session --metrics-only` で on-demand)」と解決した。#854 の「冗長 view を永続化しない」哲学と一致し、データ層 SSoT は不変であることが根拠。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note. The review-spec agent cross-referenced all 13 Changed Files categories listed in the Spec against the PR diff (`--metrics-only` flag / `--output` removal, both SKILL.md updates, 4 doc files, 2 bats files, 11 `data-layer.md` deletions) and found an exact match — no out-of-scope changes, no undocumented implicit decisions, no enum-coverage gaps (Spec defines no enum in this Issue).

### Recurring issues

One infrastructure friction point observed, not specific to this PR's content: the `capabilities.workflow: true` Workflow path (Step 10, per `skills/review/workflow-guidance.md`) failed immediately because the `review-spec`/`review-bug` custom agent types (`agents/review-spec.md`, `agents/review-bug.md`) are not registered in this session's Agent tool registry, even though the definition files exist in the repo. Fell back to `general-purpose` agents seeded with the full agent-definition prompts inline — functionally equivalent findings, but without the schema-validated structured output and adversarial-refutation pipeline that `workflow-guidance.md`'s Cost Transparency section describes, and at higher token cost than the fallback static path would normally use (no overlap between finder and verify stages). This suggests the self-hosting plugin setup may not always have `agents/*.md` installed under `~/.claude/agents/` in every execution environment — worth a follow-up Issue if this recurs on other `/review --full` runs in repos with `capabilities.workflow: true`.

### Acceptance criteria verification difficulty

Nothing to note. All 9 Pre-merge ACs used clear, mechanically verifiable hints (rubric / file_not_contains / command / github_check, some combined under AND semantics) and all verified PASS on the first pass with no UNCERTAIN results. Good template for future "abolish an unused generated artifact" Issues (#854 precedent).

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- Squash-merged PR #879 into `main` (`gh pr merge 879 --squash --delete-branch`); merge commit `78116b16`.
- `--delete-branch` failed locally because `main` was already checked out in the sibling non-worktree repo directory; the remote merge itself succeeded (confirmed via `gh pr view --json state,mergedAt`) and the leftover remote branch `worktree-code+issue-875` was removed separately via `gh api -X DELETE .../git/refs/heads/...`.
- Phase Handoff write and post-merge `main` sync were performed from `/Users/saito/src/wholework` (the pre-existing `main` worktree) rather than the `code+issue-875` worktree, since the latter's branch history diverged from `origin/main` after the squash and could not `--ff-only` merge.

### Deferred Items

- `METRICS_ONLY` inert-flag cleanup in `scripts/get-auto-session-report.sh` — still deferred (CONSIDER-level, non-blocking).
- Stale `data-layer.md` fixture name in `tests/verify-dirty-detection.bats` — still deferred, out of scope for #875.
- Root-cause fixes for the 5 structural quality bugs in the Issue's Background remain out of scope per the Issue's own "Out of Scope" section.

### Notes for Next Phase

- `/verify` is the next step; label transition to `verify` was applied via `gh-label-transition.sh`.
- The next `/auto --batch` run is the natural Post-merge observation point for the two observation-type ACs (session.md embeds `## Metrics`, no new `data-layer.md` generated).
- If a follow-up Issue is opened for the Workflow-path agent-registration gap noted in the review retrospective, link it back to this PR.

## Verify Retrospective

### Phase-by-Phase Review

#### spec

Nothing new beyond the `## issue retrospective` section already recorded: the `docs/workflow.md` / `docs/ja/workflow.md` AC gap was correctly auto-resolved following the #854 precedent; triage (Type=Task, Size=L, Value=3) and the AC Verify Command Audit (5 anti-patterns, none matched) held up through implementation with no deviation.

#### design

Nothing new beyond the `## spec retrospective` section already recorded: the two doc-sweep gaps found via code inspection (`tests/audit-auto-session.bats`, `docs/product.md` L162) were both correctly folded into Changed Files/Implementation Steps, and both are confirmed fixed in the merged diff (`grep data-layer` clean on `docs/product.md`, and `tests/audit-auto-session.bats` still passes as part of the green bats suite — see `#### verify` below).

#### code

An orchestration anomaly occurred, not yet recorded elsewhere in this Spec (no `## Auto Retrospective` section exists), so it is recorded here per the verify-retrospective skip-condition rule:

- `run-code.sh` for this issue was killed by an external Bash-tool timeout after ~660–720s, mid-flight, while `/auto`'s pr-route Step 4 was following the skill's own literal instruction to invoke it "via Bash (timeout: 600000)" combined with `run_in_background: true`.
- By the time of the kill, all 7 implementation commits were already made locally and DCO-signed, matching the Spec exactly (`git status` clean, `git log main..HEAD` showed the full expected commit set) — only the push + `gh pr create` steps had not yet run.
- Recovery: Tier 1 (`reconcile-phase-state.sh code-pr --check-completion`) correctly reported `matches_expected: false` (no PR). Tier 2 (`detect-wrapper-anomaly.sh`) found no known pattern (log shows only watchdog silence lines, no error signature). Tier 3 (`orchestration-recovery` sub-agent) correctly diagnosed the "commits done, push/PR pending" state and proposed a 3-step `recover` plan (push branch → create PR → transition label to `phase/review`), validated by `validate-recovery-plan.sh` and applied successfully — confirmed via a second Tier 1 check (`matches_expected: true`, PR #879 OPEN).
- **Root cause**: `skills/auto/SKILL.md`'s hard-coded `timeout: 600000` (10 min) in the pr-route Step 4 instructions conflicts with `run-*.sh`'s own internal watchdog design (visible via periodic "watchdog: still waiting" heartbeat lines), which is built to tolerate long silent windows. Size L code phases with `sonnet`/`high`-effort can legitimately exceed 10 minutes. By contrast, the review phase (~20 min) and merge phase in this same run were invoked with `run_in_background: true` and **no** explicit timeout, and both ran to natural completion without being killed — isolating `timeout: 600000` as the proximate cause rather than any inherent 10-minute platform ceiling.

#### review

Nothing new beyond the `## review retrospective` section already recorded. Reiterating for visibility since it links to an actionable follow-up (see Improvement Proposals): the `capabilities.workflow: true` Workflow path failed to find the `review-spec`/`review-bug` custom agent types in this session's Agent tool registry even though `agents/review-spec.md` and `agents/review-bug.md` exist in the repo, falling back to `general-purpose` agents with inline-seeded prompts (functionally equivalent findings, but without the schema-validated structured output + adversarial-refutation pipeline, at higher token cost).

#### merge

A second orchestration anomaly occurred, also not yet recorded elsewhere in this Spec:

- `run-merge.sh` exited 1, but Tier 1 reconciliation (`reconcile-phase-state.sh merge --check-completion`) confirmed the squash-merge business logic had already succeeded (PR #879 `MERGED`, merge commit `78116b16`) — override to success applied, no Tier 2/3 escalation needed.
- Per this Spec's own Phase Handoff (written by the merge phase before the wrapper failed): `gh pr merge 879 --squash --delete-branch`'s `--delete-branch` step failed because `main` was checked out in the sibling non-worktree repo directory at the time; the merge skill recovered by deleting the remote branch ref separately (`gh api -X DELETE .../git/refs/heads/...`).
- The wrapper's *trailing* steps (`mkdir .tmp`, sourcing `emit-event.sh`, falling back to `handle-permission-mode-failure.sh`) then failed with "No such file or directory" — these ran using relative paths after the worktree directory itself had already been removed as part of the merge/cleanup sequence, so the CWD (or the paths resolved from it) no longer existed. This produced a nonzero wrapper exit code despite the actual merge already having succeeded, masking success as failure at the orchestration layer.

#### verify

No FAIL. All 9 pre-merge conditions (rubric / file_not_contains / command / github_check, several combined under AND semantics) were re-verified PASS on the first pass from a fresh worktree — none of the two orchestration anomalies above (code-phase kill, merge-phase wrapper exit) left any trace in the actual deliverable; both recoveries were clean. The 2 post-merge conditions are both `verify-type: observation event=auto-run` and remain correctly unchecked, to be confirmed automatically on the next `/auto --batch` run.

### Retry Count

(Omitted — N=0; verify PASSed on the first attempt, no auto-retry fired.)

### Improvement Proposals

1. **`skills/auto/SKILL.md`'s hard-coded `Bash(timeout: 600000)` instruction for `run-code.sh`/`run-review.sh`/`run-merge.sh` calls causes premature external kill of long-running phases.** Affects multiple phase invocations (code/review/merge all call this pattern per Step 4 of `skills/auto/SKILL.md`); recurs on any Size L/XL issue whose code phase legitimately exceeds 10 minutes (e.g., `sonnet`+`high`-effort implementation work), forcing a Tier 3 recovery cycle that is otherwise entirely avoidable. Recommend removing the explicit `timeout: 600000` cap for backgrounded `run-*.sh` invocations (or raising it well above the observed p95 duration for Size L/XL phases), relying on the wrapper's own internal watchdog/timeout mechanism instead of an external hard kill that fights it.

2. **`run-merge.sh`'s trailing steps (`emit-event.sh` sourcing, `handle-permission-mode-failure.sh` fallback) are not robust to the worktree/CWD being removed by a preceding squash-merge + branch-cleanup sequence.** When the worktree directory disappears mid-script (e.g., after a `--delete-branch` conflict recovery), subsequent relative-path operations fail with "No such file or directory", producing a false-failure wrapper exit code even though the merge itself succeeded — this masks success as failure and requires a Tier 1 reconcile override to detect the true state on every occurrence. Recommend capturing an absolute path (or explicitly `cd`-ing back to the parent repo root) before any trailing cleanup/event-emission step that runs after worktree removal.

3. **Follow-up on the review retrospective's Workflow-path agent-registration gap.** The `review-spec`/`review-bug` custom agent types referenced by `capabilities.workflow: true` (per `skills/review/workflow-guidance.md`) were not found in the Agent tool registry in this self-hosting execution environment, even though `agents/review-spec.md` and `agents/review-bug.md` exist in the repo — causing a silent fallback to `general-purpose` agents with inline-seeded prompts. This is functionally OK but loses the schema-validated structured output + adversarial-refutation pipeline described in `workflow-guidance.md`'s Cost Transparency section, at higher token cost. Recommend investigating why `agents/*.md` isn't installed/registered under the expected location in this plugin/self-hosting setup, or adding a startup check that warns when `capabilities.workflow: true` is set but the expected custom agent types are unavailable.
