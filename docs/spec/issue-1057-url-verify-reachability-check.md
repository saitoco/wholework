# Issue #1057: spec: URL を引数に取る verify command の疎通確認ステップを追加

## Overview

URL を引数に取る verify command (`http_status`/`html_check`/`api_check`/`http_header`/`lighthouse_check`/`browser_check`/`browser_screenshot`) について、`/spec` Step 10 に疎通確認 (reachability check) ステップを追加する。既存の "String-matching verify command existence check" と同じ非ブロッキングパターン (警告 + Uncertainties 記録 + 続行) を踏襲する: 2xx 以外が返る場合は警告とリダイレクト先候補 (`%{redirect_url}`) を提示し、`$PREVIEW_URL` のように Spec 作成時点で未解決の変数は `PRODUCTION_URL` に置換して確認する。`PRODUCTION_URL` 未設定時はチェックをスキップして注記し、到達不能時も警告のみで継続する。3xx を仕様として期待する `http_redirect` はこのチェックの対象外とする。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の "String-matching verify command existence check" 直後に "URL reachability check" セクションを追加

## Implementation Steps

1. `skills/spec/SKILL.md` Step 10 に "URL reachability check" セクションを追加する。挿入位置: "String-matching verify command existence check" ブロック末尾 (`... so /code can verify it before implementation.` の直後) と `**Notes and verify command consistency**` の間。内容: (a) 対象コマンド `http_status`/`html_check`/`api_check`/`http_header`/`lighthouse_check`/`browser_check`/`browser_screenshot` の URL 引数を抽出し、`http_redirect` は 3xx を仕様として期待するため対象外である旨を明記、(b) `curl -s --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" "$URL"` で疎通確認、(c) 2xx 以外は警告を出し `%{redirect_url}` によるリダイレクト先候補を提示、(d) `$PREVIEW_URL` など Spec 作成時点で解決できない変数は `PRODUCTION_URL` (`.wholework.yml` の `production-url`) に置換して確認し、`PRODUCTION_URL` 未設定時はチェックをスキップして Uncertainties セクションに注記、(e) 到達不能 (DNS 解決失敗・タイムアウト等) の場合も警告のみで継続、(f) いずれの警告も Spec 作成自体をブロックしない旨を明記する。 (→ 全 Pre-merge AC)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md に URL を引数に取る verify command の疎通確認ステップが追加され、2xx 以外が返る場合に警告とリダイレクト先候補を提示する手順が記載されている" --> `/spec` に URL 系 verify command の疎通確認ステップが追加されている
- <!-- verify: section_contains "skills/spec/SKILL.md" "Step 10: Create Spec" "redirect_url" --> 疎通確認ステップがリダイレクト先候補の提示 (`redirect_url`) に言及している
- <!-- verify: rubric "疎通確認の対象コマンドが列挙されており、http_redirect が対象外である旨が明記されている" --> 対象コマンドの範囲が明確に定義されている
- <!-- verify: section_contains "skills/spec/SKILL.md" "Step 10: Create Spec" "http_redirect" --> `http_redirect` が対象外である旨が Step 10 内に明記されている
- <!-- verify: grep "reachability" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` に疎通確認 (reachability) への言及がある

### Post-merge

- trailing slash 付き URL を含む Spec を作成し、警告とリダイレクト先候補が提示されることを確認する

## Notes

- **実装済みの Issue 本文修正 (Comment Consumption 経由)**: `/spec` 実行開始時の Comment Consumption Procedure で、triage AC audit コメント (2026-08-21T05:49:16Z, saito/MEMBER) が指摘した AC2/AC4 の `section_contains` heading 引数の `###` 問題を検出した。`modules/verify-executor.md` L70 の仕様 (heading 引数は対象ファイルの実見出し行から先頭 `#` と空白を除去した文字列に部分一致させる) と照合し、heading 引数に `###` を残すと恒久的に「No heading matched」= UNCERTAIN になることを確認したうえで、Issue 本文の AC2/AC4 を `"### Step 10: Create Spec"` → `"Step 10: Create Spec"` に修正済み。本 Spec の Pre-merge Verification は修正後の Issue 本文から verbatim でコピーしている。
- **検討したが採用しなかった項目 (docs/guide/customization.md の production-url 行更新)**: `docs/guide/customization.md` L128 の `production-url` 設定リファレンス表の説明 ("Production URL for browser-based verify commands") は、本 Issue により `/spec` Step 10 の疎通確認という新しい consumer が増えるが、既存の説明のままでも矛盾しない (疎通確認も広義には verify command の実行を補助する用途) ため Changed Files には含めなかった。Issue 本文の Acceptance Criteria も `skills/spec/SKILL.md` のみを対象としている。
- **UI Design Phase**: `skills/spec/figma-design-phase.md` の自動判定基準に照らし、本 Issue はバックエンド/Skill ロジックの変更 (verify command 疎通確認ステップの追加) であり UI 要素を含まないため、UI Design セクションは不要と判断した。

## Consumed Comments

- saito (MEMBER, first-class): `/issue` フェーズの Issue Retrospective コメント。実行順序の補足 (ラベル遷移が Comment Consumption Procedure より先に実行された旨) と、`html_check` の実装が既に `pup` から `scripts/html-selector-match.py` (#1056) へ置き換わっている事実確認 (Issue 本文のコードスニペットは現行実装に更新済み)、AC3 (`grep "http_status"` → `grep "reachability"`) の修正根拠、AC1/AC2 への `section_contains` 補助チェック追加根拠を記録している。 (https://github.com/saitoco/wholework/issues/1057#issuecomment-5365701169)
- saito (MEMBER, first-class): Triage AC audit コメント。AC2/AC4 の `section_contains` heading 引数に残っていた `###` が常時 UNCERTAIN を引き起こすパターン (Pattern 6-1) を指摘。`modules/verify-executor.md` の仕様と照合のうえ、Issue 本文の AC2/AC4 を修正済み (詳細は本 Notes 冒頭の項目を参照)。 (https://github.com/saitoco/wholework/issues/1057#issuecomment-5365729524)

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps に記載された挿入位置・内容の通りに実装した。

### Design Gaps/Ambiguities

N/A

### Rework

N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Inserted the "URL reachability check" section exactly at the position specified in the Spec's Implementation Steps (between the "String-matching verify command existence check" block and "Notes and verify command consistency"), matching the Spec verbatim with no adjustment.
- Enumerated the exact command set from `modules/verify-executor.md`'s translation table (`http_status`/`html_check`/`api_check`/`http_header`/`lighthouse_check`/`browser_check`/`browser_screenshot`) rather than paraphrasing, so the AC3 rubric check ("target commands are enumerated") can match unambiguously.

### Deferred Items
- Post-merge AC (manual) — creating a Spec with a trailing-slash URL and confirming the warning + redirect candidate appear — is left for post-merge manual verification, per the Issue's own AC classification.

### Notes for Next Phase
- This is a patch route (direct commit to main, no `/review`/`/merge` phase) — `/verify` is the next phase and should focus on the post-merge manual AC.
- Full `bats tests/` suite (1904 tests) was run and passed due to Behavioral Change Detection matching `tests/check-file-overlap.bats`, `tests/run-spec.bats`, and `tests/operate-route.bats` (all reference `skills/spec/SKILL.md` outside the direct `tests/spec.bats` counterpart) — no action needed, just informational for `/verify`.
