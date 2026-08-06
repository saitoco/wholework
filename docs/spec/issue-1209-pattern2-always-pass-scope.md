# Issue #1209: triage: AC verify command 監査に「常時 PASS」パターンを追加

## Overview

`skills/triage/skill-dev-verify-audit.md` の Pattern 2 (常時 PASS な verify command 検出) は、現状 `file_contains`/`grep` (文字列存在ベース) と `command` (exit code 設計起因) の 3 種別のみをカバーしている。本 Issue はこの検出対象を `section_contains` / `github_check` / `rubric` 型 verify command まで拡張し、先行 Issue の着地により事後的に無効化された AC (vacuously true 化) が気づかれないまま閉じる状態を防ぐ。

起票時点の Issue 本文は「Pattern 表は常時 PASS 検出が未カバーであり Pattern 7 を新設する」という前提だったが、`/spec` Step 6 の投稿済みコメント消費と codebase investigation により、この前提が事実と一致しないことが判明した (詳細は Notes 参照)。Issue 本文は Pattern 2 拡張スコープへ更新済み。

## Changed Files

- `skills/triage/skill-dev-verify-audit.md`: 既存の `### Pattern 2: 常時 PASS な verify command (Always-PASS Command)` セクション内 (`command` 型サブパターンの直後、`### Pattern 3` の直前) に、`section_contains`/`section_not_contains` 型・`github_check` 型・`rubric` 型を対象とする 3 つの新規サブパターンを追加

## Implementation Steps

1. `skills/triage/skill-dev-verify-audit.md` の Pattern 2 セクションに、`section_contains`/`section_not_contains` 型 AC の常時 PASS サブパターンを追加する。既存の `command` 型サブパターン (`**exit code 設計に起因する常時 PASS (`command` 型 AC)**:` 見出しスタイル) と同じ構造 (太字ラベル見出し → Detect 説明 → 具体例 → Detection approach → Fix options) を踏襲する。
   - Detect: 対象ファイルの main ブランチ時点で、指定 heading セクション内に検索文字列が既に存在する場合、実装前から常時 PASS になる
   - Detection approach: 対象ファイルを読み、`modules/verify-executor.md` の `section_contains` 仕様通り (heading 行から次の同格以上見出しの直前まで) にセクションを切り出し、text を検索する。既に一致していれば常時 PASS として検出する
   - Fix options: main ブランチにまだ存在しない文字列を選ぶ / `section_not_contains` へ切り替えて削除の検証に変える
   (→ acceptance criteria AC1, AC2)
2. 同じ Pattern 2 セクションに、`github_check` 型 AC の常時 PASS サブパターンを追加する (after 1) (同じ構造を踏襲)。
   - Detect: `gh_command` を現状の repository 状態に対して実行した結果が既に `expected_value` を含む場合、実装前から常時 PASS になる
   - Detection approach: safe mode の allowlist 対象コマンド (`gh issue view`/`gh pr view`/`gh pr checks`/`gh api` GET/`gh run view`) であれば、現状の repository 状態に対してそのまま実行し、出力に `expected_value` が既に含まれるか確認する
   - Fix options: 実装後にのみ真になる状態を参照する `gh_command`/`expected_value` に変更する / post-merge の observation 型 AC へ移す
   (→ acceptance criteria AC1, AC2)
3. 同じ Pattern 2 セクションに、`rubric` 型 AC の常時 PASS サブパターンを追加する (after 2) (同じ構造を踏襲)。本 Issue 自身の起票時点の AC1 (「Pattern 6 と同じ構造で新規 Pattern が追加されている」という rubric 文言が、既存の Pattern 2 を該当と解釈されて vacuous-PASS しかけた事例) を具体例として使う。
   - Detect: grader が現状の (実装前の) 状態を rubric text の条件に照らして既に満たしていると判定する場合、実装前から常時 PASS になる。既存パターンの説明文をそのまま再利用した rubric text は特に起こりやすい
   - Detection approach: audit を実行している LLM 自身が、rubric text の主張を Grep/Read で現状のファイル内容と照らし合わせ、「実装前から既に成立していないか」を判定する (Pattern 2 の file_contains/grep 検出が現状の main に対してチェックを実行するのと同じ発想を、文字列一致ではなく意味的な判定に拡張したもの)
   - Fix options: 現状のリポジトリ内容を rubric text に明示的に含める (差分を条件に組み込む) / 既存の類似実装を rubric text 内で明示的に除外する
   (→ acceptance criteria AC1, AC3)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/triage/skill-dev-verify-audit.md の Pattern 2 (常時 PASS な verify command) に、section_contains・github_check・rubric 型の verify command が実装前から無条件 PASS になるケースを検出する新しいサブパターンが、file_contains/grep/command 型の既存サブパターンと同じ構造 (症状・検出手順・修復案) で追加されている" --> Pattern 2 に section_contains/github_check/rubric 型を対象とするサブパターンが追加されている
- <!-- verify: section_contains "skills/triage/skill-dev-verify-audit.md" "Pattern 2" "github_check" --> Pattern 2 セクション内に github_check 型サブパターンへの言及がある
- <!-- verify: rubric "skills/triage/skill-dev-verify-audit.md の Pattern 2 に追加されたサブパターンの検出手順が、静的な記述チェックだけでなく『現状のリポジトリに対して verify command を空撃ちして PASS するか確認する』動的チェックを含んでいる。section_contains・github_check・rubric それぞれについて空撃ちの具体的な実行方法が記述されていること" --> 検出手順に section_contains/github_check/rubric それぞれの空撃ちによる動的チェックが含まれている

### Post-merge

- 次に同一領域を連続して扱う Issue (先行 Issue 着地後に着手する後続 Issue) の `/issue` 実行時、AC verify command が空撃ちされ、無条件 PASS になっていれば強化されることを観察する

## Consumed Comments

Cutoff: undetermined (Issue timeline に `phase/*` ラベル付与履歴なし、`.tmp/auto-events.jsonl` にも該当 `phase_start` イベントなし。全コメントを best-effort で消費)

| Login | Association | Trust tier | Intent summary | URL |
|-------|-------------|-----------|-----------------|-----|
| saito | MEMBER | first-class | Issue 本文の前提 (Pattern 2 は常時 PASS 未カバー) が実装と矛盾していることを指摘。git history 上 Pattern 2 は初版から存在し `file_contains`/`grep`/`command` をカバー済みで、真のギャップは `section_contains`/`github_check`/`rubric` 型の未対応であると分析。「Pattern 7 新設」ではなく「Pattern 2 拡張」へのリスコープを推奨し、AC1 (rubric) の vacuous-PASS リスクと AC2 の見出しターゲット誤りを指摘 | https://github.com/saitoco/wholework/issues/1209#issuecomment-5205310124 |

- saito / MEMBER / first-class / ## Autonomous Auto-Resolve Log (`/spec`, non-interactive) / https://github.com/saitoco/wholework/issues/1209#issuecomment-5206634526
## Notes

**Issue body vs. existing implementation conflict (Step 6, 非対話モード自動解決)**:

起票時点の Issue 本文 Background は「Pattern 表は 6 パターンをカバーしており、常時 PASS になる verify command (vacuously true) の検出は未カバー」としていたが、`skills/triage/skill-dev-verify-audit.md` には既に **Pattern 2: 常時 PASS な verify command (Always-PASS Command)** が存在する。

- `git log -- skills/triage/skill-dev-verify-audit.md` で確認: Pattern 2 は初版 (`782cd95c`, #584) から存在。Pattern 6 追加 (`a9891ebf`, #1083) 以降、Pattern 表への新規追加はない (直近の `8e317b92` は実行条件の変更のみで Pattern 内容は無変更)
- `docs/spec/issue-1181-recovery-record-consolidation.md`・`docs/sessions/56516-*/session.md` の過去の retrospective も同じ実測 (Pattern 2 は文字列存在ベースの常時 PASS を既にカバーしているが exit code 設計起因は当初未カバー) を独立に記録しており、後者のギャップは #1083 で `command` 型サブパターンとして解消済み (`docs/sessions/11623-*/session.md` が 2026-08-06 時点でその sub-pattern の存在を裏付け)
- 上記コメント (first-class, MEMBER) の指摘と完全に一致

**解決した判断 (auto-resolve, 非対話モード)**: スコープを「Pattern 7 新設」から「**Pattern 2 の検出対象を section_contains / github_check / rubric 型 verify command へ拡張**」へ変更した。判断根拠:
- 起票時点の AC1 (rubric: 「Pattern 6 と同じ構造で新規 Pattern が追加されている」) を字面通り実装すると、grader が既存 Pattern 2 の「症状・検出手順・修復案」構造を該当と解釈し実装 0 行で PASS しうる vacuous-PASS リスクがあった
- 起票時点の AC2 (`section_contains ... "Pattern 7" ... "PASS"`) は Pattern 7 という見出しが実装対象として存在しないため、Pattern 7 を新設しない限り確実に FAIL する
- 実際に残るギャップ (`section_contains`/`github_check`/`rubric` 型が Pattern 2 の対象外) を解消することが Issue の Purpose (先行 Issue 着地による事後的な AC 無効化の防止) に直接資する

Issue 本文 (Background / Purpose / Acceptance Criteria) はこの判断に基づき更新済み。判断の詳細は Auto-Resolve Log として Issue コメントに投稿済み: https://github.com/saitoco/wholework/issues/1209#issuecomment-5206634526

**スコープ境界 (計測範囲: `modules/verify-executor.md` の Verification Command 変換テーブル全 27 行)**: Pattern 2 は本 Issue の実装後、27 種別中 6 種別 (`file_contains`/`grep`/`command`/`section_contains`/`github_check`/`rubric`) をカバーする。残り 21 種別は本 Issue のスコープ外。特に `file_not_contains`/`file_not_exists`/`dir_not_exists` 等の「不在アサーション」型の常時 PASS (対象が実装前から既に存在しない場合に真になる) は、Pattern 2 が扱う「存在アサーション」型と対称的な別種のギャップであり、将来の Issue 候補になりうるが本 Issue には含めない。`http_status`/`mcp_call`/`browser_check` 等の外部・実行時状態依存型は、`main` ブランチという静的な空撃ち対象を持たないため同種の拡張になじまない。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜3 をそのまま実施。3 サブパターンは個別コミットではなく 1 回の Edit にまとめて追加したが、追加内容・構造 (太字ラベル見出し → Detect → 具体例 → Detection approach → Fix options) は Spec の記述と完全に一致する

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Pattern 2 に `section_contains`/`section_not_contains`・`github_check`・`rubric` の 3 サブパターンを、既存の `command` 型サブパターンと同じ構造 (太字ラベル見出し → Detect → 具体例 → Detection approach → Fix options) で追加した
- 各サブパターンの Detection approach に、AC3 が要求する「現状のリポジトリに対する空撃ち」の具体的な実行方法 (grep/section 切り出し、gh_command 実行、grader による自己判定) を明記した

### Deferred Items
- 「不在アサーション」型 (`file_not_contains`/`file_not_exists`/`dir_not_exists` 等) の常時 PASS 検出は Spec Notes のスコープ境界により本 Issue から除外。将来の Issue 候補
- `http_status`/`mcp_call`/`browser_check` 等の外部・実行時状態依存型も対象外 (静的な `main` ブランチ空撃ち対象を持たないため)

### Notes for Next Phase
- patch route のため `/review`/`/merge` は経由しない。`/verify` は Post-merge の observation 型 AC (次の同一領域 Issue の `/issue` 実行時に空撃ち強化が観察されるか) のみが対象
- テスト結果: `bats tests/` 全 1490 件 PASS、`validate-skill-syntax.py` 0 errors (既存の未関連 warning 1 件は本 Issue の変更に起因しない)、`check-forbidden-expressions.sh` PASS
- Pre-merge AC 3 件はすべて実装時に自己検証済みで PASS (Issue チェックボックス更新済み)
