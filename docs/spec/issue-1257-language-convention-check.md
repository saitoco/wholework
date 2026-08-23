# Issue #1257: review: 英語指定ドキュメントへの日本語混入を検出する転記チェックを追加

## Overview

CLAUDE.md の Language Conventions では `skills/**/*.md` (skill docs) / `modules/*.md` (module docs) / `scripts/*` (source code) は英語指定だが、Spec Notes や Issue 本文の rationale (正しく日本語) をこれらへ転記する際に翻訳ステップが抜け、日本語が混入する事故が #975 (2026-07-12, XS/patch route) と #1236 (2026-08-07, L/PR route, 1 PR で 3 ファイル同時) の 2 回発生した。既存の `scripts/check-forbidden-expressions.sh` は言語を検査せず、`skills/review/skill-dev-recheck.md` の "Transcription Divergence Check" は対象が異なる (spike report の aspirational language ドリフト専用)。

Issue 本文は対応方針として 案 A (review 観点として `skill-dev-recheck.md` に追加) と 案 B (機械的チェックスクリプトを追加) を提示し、選択判断を本 `/spec` フェーズに委譲している。本 Spec は **案 B (機械的チェック) を採用**する — 理由は `## Notes` を参照。

## Changed Files

- `scripts/check-language-convention.py`: 新規。差分スコープで CJK 文字混入を検出するスクリプト
- `.github/workflows/test.yml`: 新規 CI job `language-convention` を追加
- `tests/check-language-convention.bats`: 新規。真陽性 (規約違反) と偽陽性防止 (正当な日本語) の両方を検証
- `docs/structure.md`: Scripts (Tooling) 一覧・CI Workflows 節・`test.yml` ツリーコメント・`scripts/`/`tests/` ファイル数コメントを更新
- `docs/ja/structure.md`: 上記の日本語ミラー更新 (`docs/translation-workflow.md` Sync Procedure に従う)

## Implementation Steps

1. `scripts/check-language-convention.py` を新規作成する (→ 受入条件 AC1, AC2)。仕様:
   - **入力**: unified diff (`git diff` 形式) を標準入力から受け取る。ファイル名は追加された diff 内の `+++ b/<path>` ヘッダー行から追跡する (呼び出し元が `git diff -- skills/ modules/ scripts/` でパス制限済みの diff を渡す前提のため、スクリプト自身はパスフィルタを行わない)
   - **走査対象**: `+` で始まる追加行のみ (`+++`/`---` ヘッダー行を除く)。ファイルごとに ` ``` ` フェンス行の出現をカウントし、奇数回目〜偶数回目の間 (フェンス内) の追加行はスキップする
   - **偽陽性除外ロジック (フェンス外の残り行に適用)**: (a) インラインコードスパン (`` `...` ``) の中身を除去、(b) ダブルクォート文字列リテラル (`"..."`) の中身を除去。除去後に残ったテキストに Hiragana (U+3040–U+309F) / Katakana (U+30A0–U+30FF) / CJK 統合漢字 (U+4E00–U+9FFF) のいずれかの文字が含まれていれば違反として記録する
   - **出力/終了コード**: 違反があれば `{path}:{行内容}` 形式で標準出力に列挙し exit 1。違反なしなら exit 0
   - **AC2 対応 (実装成果物への明記)**: スクリプト冒頭のモジュール docstring に、上記の偽陽性除外ロジックが対応する正当なケースを明記する — (i) フェンス内の terminal output テンプレート (CLAUDE.md の "Skill output (terminal): Japanese" 規約に対応。例: `skills/verify/SKILL.md` の `Print advisory` テンプレートブロック)、(ii) インラインコードスパンで囲まれた日本語キーワード (例: `skills/audit/SKILL.md` の domain 分類テーブルの `` `デザイン` `` 等 — Issue 本文を検索するためのデータ値であり説明文ではない)、(iii) `Print:`/`Notify user:` 等に続くダブルクォート文字列内の出力メッセージ。これら 3 パターン以外の平文プロースに現れる CJK 文字は規約違反として扱う、という判断基準を明記する
   - 依存は Python 標準ライブラリ (`re`, `sys`) のみ

2. (after 1) `.github/workflows/test.yml` に新規 job `language-convention` (name: `Language Convention check`) を追加する (→ AC1)。`check-forbidden-expressions` job の直後に配置。
   - `actions/checkout@v4` を `fetch-depth: 0` (フルクローン) で実行 — diff 計算に過去コミットが必要なため
   - イベント種別ごとに base を分岐: `pull_request` イベントなら `git diff origin/${{ github.base_ref }}...HEAD -- skills/ modules/ scripts/`、それ以外 (`push`) なら `git diff HEAD^..HEAD -- skills/ modules/ scripts/` (patch route の直接 push 、および PR route の squash-merge 後の push はいずれも 1 コミット差分のため `HEAD^` で足りる — `github.event.before` を使う方式は新規ブランチ最初の push で all-zero SHA になる edge case があるため採用しない)
   - 上記 diff の標準出力を `python3 scripts/check-language-convention.py` にパイプする。事前の `actions/setup-python` ステップは不要 (`ubuntu-latest` に同梱の python3 で標準ライブラリのみのため十分)

3. (after 1) `tests/check-language-convention.bats` を新規作成する (→ AC4)。**テスト入力形式**: 各 `@test` ケースは unified diff のリテラルテキストブロックを fixture として用意し、`+++ b/<path>` ヘッダー行 1 行 + `@@ ... @@` hunk ヘッダー行 1 行 + `+` 始まりの追加行 (0 行以上) の形式で `check-language-convention.py` に標準入力として渡す。最低限のケース:
   - 真陽性: `modules/example.md` への `+` 追加行に、フェンス外・インラインコード外・クォート外の平文日本語プロース (例: `転記した内容の rationale をそのまま英語ドキュメントに追加する。`) を含む diff → exit 1 を期待
   - 偽陽性防止 (フェンス内): 同様の diff だが対象行が ` ``` ` フェンスで囲まれたコードブロック内にある → exit 0 を期待
   - 偽陽性防止 (インラインコード): テーブル行内の `` `デザイン` `` のようなバッククォート囲みの日本語キーワード → exit 0 を期待

4. (after 1, parallel with 2, 3) `docs/structure.md` と `docs/ja/structure.md` を更新する (SHOULD レベルのドキュメント整合性):
   - Scripts (Tooling) 一覧に `scripts/check-forbidden-expressions.sh` の直後の行として `check-language-convention.py` のエントリを追加
   - CI Workflows 節の `test.yml` の説明文に「言語規約チェック」に相当する記述を追加 (英語版は "language convention check"、日本語版は「言語規約チェック」)
   - Directory Layout 内の `test.yml` ツリーコメントにも同様に追加
   - `scripts/` ディレクトリのファイル数コメント: 現状表記 `(79 files)` / `（79 ファイル）` は本 Issue 着手前の実ファイル数 (80) に対して既に 1 件古い (pre-existing drift)。本変更で 1 ファイル追加するため `(81 files)` / `（81 ファイル）` に修正する
   - `tests/` ディレクトリのファイル数コメント: 同様に現状表記 `(114 files)` / `（114 ファイル）` は実ファイル数 (115) に対して既に 1 件古い。本変更で 1 ファイル追加するため `(116 files)` / `（116 ファイル）` に修正する

5. (Spec のみ、コード変更なし) 案 A/B の比較と選択理由を本 Spec の `## Notes` に記録する (→ AC3)。以下の `## Notes` セクションが該当。

## Verification

### Pre-merge
- 英語指定ドキュメントへの日本語混入を検出する手段が、レビュー観点または機械的チェックとして追加されている <!-- verify: rubric "英語指定パスへの日本語混入を検出する仕組みが、skills/review/skill-dev-recheck.md への観点追加またはスクリプト追加のいずれかの形で実装されている" -->
- ユーザー向け出力文字列 (terminal output) の日本語を偽陽性としない切り分け基準が、選択した方式の実装成果物 (案 A なら `skills/review/skill-dev-recheck.md`、案 B なら追加スクリプト本体) に明記されている (Spec のみへの記載は不可 — `docs/tech.md` の Distributable-first improvement principle により Spec/Steering Docs は配布対象外) <!-- verify: rubric "CLAUDE.md の Skill output (terminal): Japanese に該当する正当な日本語と、英語指定箇所への規約違反とを区別する基準が、選択した実装成果物 (skill-dev-recheck.md への追記またはスクリプト本体のコメント/ドキュメント) 内に文書化されている。Spec のみの記載は不十分と判定する" -->
- 選択した方針 (レビュー観点 / 機械的チェック) と却下した方針が Spec に記録されている <!-- verify: rubric "Spec に案 A/B の比較と選択理由が記載されている" -->
- 機械的チェックを追加した場合、bats テストで正当な日本語と規約違反の双方が検証されている <!-- verify: rubric "機械的チェックを選択した場合に限り、偽陽性ケースと真陽性ケースの双方を検証する bats テストが存在する。レビュー観点のみを選択した場合はこの条件を N/A とする" -->

### Post-merge
- 次回以降、Spec Notes の rationale を英語指定ドキュメントへ転記する変更を含む PR で、日本語混入が検出または未然に防止されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### 案 A vs 案 B の比較と選択理由 (AC3 対応)

**案 A (`skill-dev-recheck.md` の "Transcription Divergence Check" に観点追加)**:
- 長所: 既存の「転記による劣化」検出の枠組みに収まり追加コストが小さい
- 短所 (致命的): `skill-dev-recheck.md` は `/review` 専用の domain file であり、`/review` は Size M/L/XL の **PR route でのみ実行される**。Size XS/S の **patch route は `/review` を経由せず main に直接 commit される** (`docs/tech.md` Architecture Decisions 参照)。本 Issue の再発記録のうち #975 はまさに Size XS/patch route で発生しており、案 A ではこの経路を **構造的に検出できない**。2 件中 1 件が patch route である以上、レビュー観点のみでは再発防止のカバレッジが不十分と判断した

**案 B (機械的チェックスクリプトを追加)**: **採用**
- `.github/workflows/test.yml` は `on: push` (ブランチ制限なし) と `on: pull_request` の両方でトリガーされるため、patch route (main への直接 push) と PR route (pull_request イベント) の **両方を CI が捕捉できる** — 案 A のカバレッジ欠落を構造的に解消する
- 短所として偽陽性リスクが挙げられていたが、実装レベルで対応可能 (Implementation Steps 1 参照)。既存コードの実地調査 (後述) により、正当な日本語出現は「フェンス内」「インラインコード内」「ダブルクォート文字列内」の 3 パターンにほぼ収まることを確認し、この 3 パターンを除外条件として設計した

**却下した代替案**: `scripts/check-forbidden-expressions.sh` 自体を拡張する案も検討したが、以下の理由で見送り、独立スクリプト (`check-language-convention.py`) とした:
- Related に記載の **#1139** (同スクリプトへの diff スコープ限定モード追加、本 Issue 起票時点で OPEN・未着手) と同一ファイルを触ると、将来のマージ時にコンフリクトするリスクがある
- 既存の `check-forbidden-expressions.sh` は非 diff スコープ (リポジトリ全体走査・固定語彙リスト) だが、言語混入チェックは性質上 diff スコープ必須 (後述の False Positive 調査参照) であり、実装方式が異なる
- 本リポジトリは 1 スクリプト 1 関心事の粒度で `check-*.sh` を分割する既存パターンを持つ (例: `check-ac-checkbox-format.sh`, `check-skill-change-observation-ac.sh` 等)

### False Positive 調査 (diff スコープが必須である根拠)

実装前に現状コードを調査した結果、リポジトリ全体には既に多数の「英語指定ファイル中の日本語」が存在することを確認した (すべて診断目的の grep で確認、修正はしていない):
- `scripts/emit-event.sh`: イベントセマンティクスを説明する日本語コメントが複数行、本 Issue と無関係に既存
- `skills/audit/SKILL.md`: domain 分類テーブルの日本語キーワード (`` `デザイン` `` 等、インラインコード囲み)、"滞留期間" 等の日本語併記見出し
- `skills/verify/SKILL.md`: `Print`/`Notify user`/`echo` に続く日本語の完了・案内メッセージ (フェンス内、またはダブルクォート文字列内)

これらを非 diff スコープ (全文走査) で検出しようとすると、本 Issue と無関係な大量の既存箇所が一斉に FAIL し CI が機能しなくなる。そのため Issue 本文の案 B 説明にある「差分に対し」を必須要件として設計した (Implementation Steps 1, 2)。

### スコープ判断: `agents/*.md` は対象外

Issue 本文の案 B は対象パスを `skills/**/*.md` / `modules/*.md` / `scripts/*` と明示しており、`agents/*.md` は含まれていない。`agents/*.md` も英語指定の skill doc 相当だが、Issue 本文に明記のない範囲拡張を Spec 側で行わないため、今回は対象外とする (将来的に必要なら別 Issue で検討)。

### bats テスト入力形式

Implementation Steps 3 に記載の通り、`tests/check-language-convention.bats` の各 `@test` は unified diff のリテラルテキストを fixture として `check-language-convention.py` の標準入力に渡す形式で記述する。

## Consumed Comments

| login | authorAssociation | trust tier | 内容概要 | URL |
|-------|-------------------|-----------|---------|-----|
| saito | MEMBER | first-class | Issue Retrospective: Background 事実確認 (訂正なし)、AC2 を「選択した実装成果物への記載」に明確化した Auto-Resolve Log、post-merge observation AC への `session=next` 付与根拠、案 A/B 選択判断は `/spec` フェーズへの委譲を確認 | https://github.com/saitoco/wholework/issues/1257#issuecomment-5227226402 |

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1257#issuecomment-5227671103
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5228485571
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5235407578
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5246565737
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5255760595
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5296389977
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5304277249
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5310551596
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5327736181
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5341248616
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5354383510
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5369699770
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5378426447
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1257#issuecomment-5384000217
## Code Retrospective

### Deviations from Design
- None. Implementation Steps 1–5 were followed as written.

### Design Gaps/Ambiguities
- None. Spec's false-positive exclusion logic (fence / inline code / double-quoted string) and its docstring documentation requirement (AC2) were unambiguous and required no interpretation during implementation.

### Rework
- None.

### Notes
- `tests/check-language-convention.bats` covers 6 cases (Spec's 3 minimum plus a double-quoted-string false positive, a no-CJK-content case, and a removed-line (`-` prefix) exclusion case) — purely additive coverage, not a deviation from the Spec's Implementation Steps 3 minimum.
- Behavioral Change Detection (`/code` Step 9) triggered a full parallel bats run (`bats --jobs 18 tests/`, 1626/1626 PASS) instead of narrow scope, because `tests/visual-diff-adapter.bats` references `.github/workflows/test.yml` in a comment (documenting where its Node runtime setup comes from) — an incidental match unrelated to the new `language-convention` job actually added, but the mechanical path-grep check does not distinguish comment references from behavioral dependencies.

## review retrospective

### Spec vs. implementation divergence patterns
- No implementation-vs-Spec divergence, but a Spec-level algorithm gap was found: Implementation Steps 1 described fence tracking as counting `` ``` `` occurrences among "追加行" (added lines) only, and `check-language-convention.py` implemented exactly that literal wording. The resulting bug — editing a single line inside an already-existing fenced block (fence delimiters themselves unchanged, hence appearing only as diff context lines) was misclassified as outside the fence — reproduced directly against the script's own docstring example (`skills/verify/SKILL.md`'s `Print advisory` template). The root cause traces to the Spec's algorithm description, not to an implementation shortcut; the Spec itself under-specified how to handle unchanged/context state when the check's *subject* is a diff but its *correctness target* is the resulting file's structure.

### Recurring issues
- Nothing to note. This is the first Issue in this area (post-#975/#1236 line of fixes) to reach `/review` with a script-level correctness bug; no repeat-of-known-pattern signal.

### Acceptance criteria verification difficulty
- Nothing to note. All 4 Pre-merge AC are `rubric`-type; each graded cleanly to PASS by both `/code`'s and `/review`'s independent grader passes, with no UNCERTAIN results. The bats suite (converted to 7 cases after the review fix) gave a fast, reliable local reproduction/verification loop for the one MUST finding.

### Improvement proposal (recorded here only; not filed as an Issue per `/verify`-aggregation convention)
- When a Spec's Implementation Steps describe a diff-scanning algorithm whose correctness target is *post-diff file state* (e.g. "is this added line inside a fence/block/scope in the final file"), the Spec should explicitly call out whether unchanged context lines must also be tracked — not just added lines — to avoid this exact class of bug recurring in future diff-scanning script specs.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash-merged PR #1291 with no conflicts (`mergeable=true`, `reason=clean`, CI green, review approved) — no rebase/conflict-resolution steps were needed.
- Pre-merge AC gate: all 4 pre-merge Acceptance Criteria confirmed checked (`unchecked_count=0`) and review completion was organic (not fallback-origin) — merge proceeded without an override marker.

### Deferred Items
- Post-merge observation AC (`session=next`, `event=auto-run`) remains unchecked — carried over unchanged from `/code` and `/review`; requires a future session to observe whether language-mixing is caught/prevented in a subsequent transcription-style PR.

### Notes for Next Phase
- `/verify` should treat the post-merge observation AC as the sole remaining item; all pre-merge AC are already PASS and require no re-check.
- No policy/AC-text change occurred during merge.

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- AC2 を「Spec のみへの記載は不可」と明示し、`docs/tech.md` の Distributable-first improvement principle を根拠として rubric に組み込んだ判断が効いた。Spec は配布対象外であるため、切り分け基準がスクリプトの docstring 側に落ちることが実装時点で確定していた
- AC4 を「機械的チェックを選択した場合に限り」と条件付きにしており、案 A (レビュー観点のみ) を選んだ場合に常時 FAIL にならない構造になっていた。案の選択が未確定な段階の AC として適切

#### spec

- 案 A/B の比較・却下理由・`agents/*.md` を対象外とする範囲判断・bats の入力形式まで Notes に記録されており、判断の追跡可能性が高い
- 一方で **Implementation Steps 1 の走査アルゴリズム記述に欠陥があった**。フェンス追跡を「追加行のみで ` ``` ` の出現をカウントする」と記述したため、既存フェンス内の 1 行を編集した場合 (フェンス区切り自体は変更されず context 行としてしか現れない) にフェンス外と誤判定される。実装はこの記述に忠実に従っており、逸脱ではなく Spec 側の under-specification である

#### code

- Implementation Steps 1〜5 を逸脱なく実施、rework ゼロ
- bats を Spec の最低 3 ケースから 6 ケースへ拡張 (追加分は加算的カバレッジ)
- Behavioral Change Detection が `tests/visual-diff-adapter.bats` のコメント内 `.github/workflows/test.yml` 参照に反応して全件並列実行 (1626/1626 PASS) にエスカレートした。機械的な path-grep がコメント参照と挙動依存を区別できないことによる過剰発火だが、実害は実行時間のみ

#### review

- **MUST 指摘 1 件で上記の Spec 由来アルゴリズム欠陥を捕捉した**。指摘はスクリプト自身の docstring 例 (`skills/verify/SKILL.md` の `Print advisory` テンプレート) に対して直接再現しており、根拠が具体的。修正後に bats はケース 7 (既存フェンス内編集) を含む 7 件へ拡張された。パーサ系変更に対する review の実効性が示された事例
- **#1256 で修正した自己 PR 422 フォールバックが、本 PR で初めて実発火した**。MUST 指摘があったため `EVENT=REQUEST_CHANGES` が選択され、自己 PR に対する GitHub の 422 応答をフォールバックが捕捉して COMMENT へ切り替えている (review body 先頭に `Note: posted as COMMENT instead of REQUEST_CHANGES ...` が付与)。修正前は判別文言がレスポンスボディ (stdout) 側にあり捨てられていたため hard-fail していた経路であり、本 PR は #1256 の post-merge observation 条件そのものに該当する。証拠は #1256 のコメントに記録済み

#### merge

- `mergeable=true` / `reason=clean` / CI green / review approved を確認し squash merge。Pre-merge AC gate は `unchecked_count=0`、review completion は organic (fallback 由来ではない)。コンフリクトなし

#### verify

- 初回 (2026-08-08): Pre-merge 4 件は既チェックのため既定どおり skip、post-merge の observation 1 件は `auto-run` 未発火で SKIPPED。FAIL・UNCERTAIN ゼロ
- 実体をスポット確認した: `scripts/check-language-convention.py` は存在・実行可能、bats 7 件すべて PASS。呼び出し元は `.github/workflows/test.yml:85,87` のみで `skills/` / `modules/` からの参照はゼロのため、`allowed-tools` への追加が不要な構成であることも確認した (#1266 で拡張した allowed-tools impact chain check の Case 1 は新規 `scripts/*.sh` を対象とするが、本 Issue の新規スクリプトは `.py` かつ CI 専用のため対象外で正しい)
- 再走 (2026-08-23): `event=auto-run` 発火を確認し PASS 判定。`docs/spec/issue-1302-audit-ref-existence-check.md` (2026-08-16) に、`skills/spec/SKILL.md` への生の CJK プローズ混入を CI の Language Convention check が実際に検出し `/review` で修正した記録があり、本 Issue の post-merge observation が要求する「転記経由の日本語混入検出」の直接的な実例として確認できた

### Improvement Proposals

- **diff 走査アルゴリズムの Spec 記述で context 行の扱いを明示する規約 (Tier 2 — 記録のみ)**: `/review` retrospective が記録した提案を引き継ぐ。Spec の Implementation Steps が diff を走査するアルゴリズムを記述する際、その正しさの判定対象が「diff 適用後のファイル状態」である場合 (フェンス内か・スコープ内か等)、追加行だけでなく変更なしの context 行も追跡する必要があるかを明示すべき。本 Issue はまさにこの欠落で MUST 指摘 1 件を生んだ。Tier 1 に上げなかった根拠: 変更対象は `skills/spec/SKILL.md` 単一で multi-file ripple なし、`/review` retrospective 自身が「This is the first Issue in this area ... no repeat-of-known-pattern signal」と再発性を明示的に否定している。関連する既存 open Issue として #1125 (`review`: パーサ系変更への negative/edge case 実測ステップの定型化) があるが、あちらは `/review` フェーズ、本提案は `/spec` フェーズを対象とするため追記ではなく独立の記録とした。同型が `/spec` 側で再発した場合は Tier 1 へ引き上げる
