# Issue #1466: review: CI 失敗診断が決定的な既存失敗をフレークと誤判定し件数不一致シグナルを見落とす

## Overview

`/review` の CI 失敗診断 (`skills/review/SKILL.md` Step 9 と `modules/ci-failure-classifier.md`) に、2 つの独立した精度問題がある。いずれも根は同じで、「決定的な失敗を安全側 (non-blocking / retriable) に誤分類しうる」という判定粒度の粗さに起因する。

1. #1462 review retrospective は Step 9 の Pre-existing failure exception (現状 `forbidden-expressions` 単体限定) を他ジョブに汎用化する提案をしたが、その根拠となった事例 (`tests/resolve-preview-env.bats` の basic-auth 失敗を「既存の環境依存フレーク」と判定) は誤診断だった。実際は `file_mode` ヘルパの GNU stat 分岐バグによる Linux 上 100% 決定的な失敗であり、「main の複数 commit にわたって同一パターンで再現する」という観測は、フレークの証拠ではなく決定性の証拠である。
2. 同じ CI run で並列ステップが `# bats warning: Executed N instead of expected M tests` という件数不一致を出力して exit 1 していたが、これは `modules/ci-failure-classifier.md` の 7 シグネチャのいずれにも該当せず、`/review` は直列再実行ステップの `not ok` 行のみを診断根拠にしているため、この signal 自体が診断入力に存在しない。

本 Spec では、(1) Pre-existing failure exception のスコープを `forbidden-expressions` 単体のまま維持する決定と、将来汎用化する場合に必須となる決定性判別条件を明文化し、(2) 件数不一致を "ci-infra ではない別種のシグナル" として `modules/ci-failure-classifier.md` に明記して、`/review` Step 9 がそれを診断根拠として引用できるようにする。いずれもドキュメント (SKILL.md / モジュール) の追記のみで、`scripts/pre-merge-check.sh` の実際の分類ロジックや `.github/workflows/test.yml` は変更しない。

## Reproduction Steps

1. `/review` を #1462 (PR #1465) で実行すると、`tests/resolve-preview-env.bats` の basic-auth テスト 2 件が CI で FAILURE として報告される。
2. review は `main` の直近 CI run でも同一 2 件が同一パターンで失敗していることを確認し、「本 PR の diff と無関係な既存の環境依存フレーク」と判定した (`pre-merge-check.sh` は `forbidden-expressions` 専用であり、このジョブには使えないため、review 自身が独自にこの判定を行った)。
3. 実際には `file_mode()` ヘルパ (`stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null`) が GNU coreutils 環境で `-f` を `--file-system` と解釈し、stray stdout がフォールバック出力と連結されてモード比較が Linux 上で常に失敗する既知の決定的バグ (#1429 以降存在)。「main でも同一パターンで再現する」ことは「既存の失敗である」根拠にはなるが、独立した軸である「非決定的 (フレーク) である」根拠にはならない。
4. 同じ CI run で並列ステップ `bats --jobs $(nproc) tests/` が `# bats warning: Executed 2038 instead of expected 2045 tests` を出力して exit 1 した。原因は `tests/check-bare-bracket-assertions.bats` の heredoc 内 fixture の行頭 `@test` を CI の bats 1.10.0 パーサが実テストとして計上したこと (phantom 7 件)。実際に `not ok` になったテストは 0 件であるため、直列再実行ステップは "再実行対象なし" となり、`/review` が根拠にする `not ok` 行が存在しない。

## Root Cause

- **問題 1**: Step 9 の Pre-existing failure exception は「既存失敗であること」のみを判定軸にしており、「決定的か非決定的か」を独立して判別する手段を持たない。#1462 review retrospective の汎用化提案も同じ軸の欠落を引き継いでいた。「同一パターンが複数 commit にわたって再現する」という観測は、環境が固定なら常に同じ結果になる決定的失敗の典型的特徴であり、同一条件下で結果が揺れるというフレークの定義とは正反対である。この 2 軸 (既存性 / 決定性) の混同が根本原因であり、混同したまま汎用化していた場合、bats gate は恒久的に赤のままマージが継続する結果になっていた。
- **問題 2**: `modules/ci-failure-classifier.md` の Signature Table は CI プラットフォームのインフラ障害 (steps 空、timeout、runner error、network error、no workflow run、Set up job 失敗、queued stall) の 7 パターンのみを想定しており、「テストランナー自身の件数整合性エラー」という "テストが失敗した" のではなく "一部テストが実行されなかった" ことを示す別種のシグナルを扱っていない。この結果、(a) 件数不一致シグナルが `ci-infra` (retriable) と誤分類されるリスクが `modules/ci-failure-classifier.md` の全 8 consumer に残っており、(b) `/review` Step 9 がこの signal を診断根拠として引用する手段がない。

## Changed Files

- `skills/review/SKILL.md`: Step 9 の "Pre-existing failure exception (baseline attribution)" セクションに、スコープを `forbidden-expressions` 単体のまま維持する決定・理由と、将来汎用化時に必須となる決定性判別条件を追記する。同じ Step 9 の "FAILURE jobs" 記述に、件数不一致パターンを引用する指示を追記する。
- `modules/ci-failure-classifier.md`: Signature Table の直後・`## Output` の直前に "Test Count Mismatch Signal (non-infra)" セクションを新設する。
- `docs/tech.md` (Scope 追加、投資対効果が高いため実装に含める): "CI bats Parallel/Serial Split" テーブルに、件数不一致で並列ステップが exit 1 するが直列再実行には再実行対象がない第 4 のケースを追記する。既存の 3 行 (PASS/(not run)/Success、FAIL/PASS/Success、FAIL/FAIL/Failure) はこのケースを表現できていない。
- [Steering Docs sync candidate] キーワード `"ci-failure-classifier.md"` (18 件) と `"review"` (1098 件) はいずれも discriminating power フィルタ (8 件超) でスキップ。個別列挙は行わない。

## Implementation Steps

1. `modules/ci-failure-classifier.md` の Signature Table (`| 7 | Queued stall | ... |` の行) の直後・`## Output` 見出しの直前に "### Test Count Mismatch Signal (non-infra)" セクションを追加する。内容: bats の `# bats warning: Executed N instead of expected M tests` を例示し、「テストが失敗した」のではなく「一部テストが実行されなかった (件数不一致)」ことを示す別種のシグナルであり、単独では 7 シグネチャのいずれにも該当せず `ci-infra` と分類しないこと、CI が確定 FAILURE 状態でこの signal のみが存在する場合は既存ルールどおり `implementation` verdict になること、consumer は `not ok` 行の有無だけでなくこの signal 自体を FAILURE の根拠として引用すべきことを明記する (→ acceptance criteria 2)
2. `skills/review/SKILL.md` の "Pre-existing failure exception (baseline attribution)" セクション、"**Applicable scope (exhaustive)**: ... Every other FAILURE job keeps the unconditional blocking behavior above." 段落の直後に新しい段落を追加する。内容: (a) このスコープを `forbidden-expressions` 単体のまま維持し汎用化しない決定と、その理由 (#1466 で判明した「既存性の観測をフレークの根拠と混同した」誤診断事例)、(b) 将来汎用化する場合に必須となる決定性判別条件 — 同一 commit SHA での単発再実行 (`modules/orchestration-fallbacks.md#ci-wait-silence-timeout` の既存パターンと同系統) を行い、結果が一定なら決定的 (exception 対象外、blocker のまま)、結果が揺れるならフレーク (non-blocking 対象) と判定すること、cross-commit での再現は「既存性」の根拠にしかならず「決定性」の根拠にはならない旨、を明記する (parallel with 1) (→ acceptance criteria 1)
3. `skills/review/SKILL.md` Step 9 冒頭の "**FAILURE jobs**: list failed job names and statuses; suggest fixes where possible." の一文に続けて、ジョブログに件数不一致パターン (`modules/ci-failure-classifier.md` § Test Count Mismatch Signal 参照) が含まれる場合はそれを FAILURE の根拠として明示的に引用し、直列再実行ステップの `not ok` 行の有無だけに依拠しない旨を追記する (after 1) (→ acceptance criteria 2)
4. `docs/tech.md` の "CI bats Parallel/Serial Split" テーブル (3 行: `PASS/(not run)/Success`、`FAIL/PASS/Success`、`FAIL/FAIL/Failure`) に 4 行目を追加する: 件数不一致で並列ステップが exit 1 するが `not ok` テストが 0 件のため直列再実行には再実行対象がないケース (Meaning 列に `modules/ci-failure-classifier.md` § Test Count Mismatch Signal への参照を含める)。テーブル直後に、件数不一致がフレーク・真の失敗のどちらとも異なる (テスト未実行を示す) 別種の signal である旨の一文を追加する (after 1) (→ SHOULD-level、専用 AC なし)
5. `bats tests/` を実行し、ドキュメントのみの変更でリグレッションがなく全件 PASS することを確認する (after 1, 2, 3, 4) (→ acceptance criteria 3)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md の Pre-existing failure exception セクションに、既存失敗を非ブロッキング扱いする条件として決定性 (フレークか決定的失敗か) の判別が明記されている。または汎用化を見送る判断とその理由が記載されている" -->
- <!-- verify: grep "instead of expected|件数不一致" "modules/ci-failure-classifier.md" -->
- <!-- verify: command "bats tests/" -->

### Post-merge

- 決定的な既存失敗を含む PR で `/review` を実行し、exception が適用されず MUST としてブロックされることを観察する <!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - `/review` の Response Summary で当該 CI FAILURE が `severity: "MUST"` として記録されていること
    - Pre-existing failure exception による非ブロッキング判定 (`PRE_EXISTING`/`FIXED`/`CLEAN`) が適用されていないこと

## Notes

- **汎用化するかどうかの判断 (Issue 本文 Autonomous Auto-Resolve Log で `/spec` に委任)**: 汎用化は行わず、`forbidden-expressions` 単体のスコープを維持する。理由: 本 Issue の誤診断事例そのものが「既存失敗 = 安全に non-blocking 化してよい」という前提の危険性を示している。決定性判別を自動化する (複数 run の再現率収集、結果比較ロジック) には新規基盤構築が必要で、Size M / light spec のスコープを超える。判定条件を文書化し、将来の汎用化がこの条件を満たすことを要件とする形にとどめた。AC1 のルーブリックは「汎用化する場合の条件明記」と「汎用化を見送る判断とその理由」のどちらも許容しており、本判断はその両方 (条件の明記 + 見送りの理由) を満たす。
- **決定性判別手段の選定 (同じく `/spec` に委任)**: 同一 commit SHA での単発再実行を採用する (`modules/orchestration-fallbacks.md#ci-wait-silence-timeout` の "re-run CI on the same SHA" と同系統の既存パターン)。複数 run にわたる再現率や OS 依存切り分けは追加のデータ収集基盤を要するため、将来の汎用化 Issue 側の検討事項として残し、本 Issue では採用しない。
- **Issue 本文 vs 実装の整合性確認**: Issue 本文の事実主張 (`forbidden-expressions` が `pre-merge-check.sh` の唯一の dispatch table エントリであること、`ci-failure-classifier.md` の 7 シグネチャに件数不一致が含まれないこと) をそれぞれ `scripts/pre-merge-check.sh` の `case "$CHECK" in` ブロックと `modules/ci-failure-classifier.md` の Signature Table で確認し、いずれも一致した。矛盾なし。
- **`docs/tech.md` の SHOULD-level 追加**: Issue 本文の Scope には明記されていないが、コードベース調査で "CI bats Parallel/Serial Split" テーブル (`docs/tech.md`) が件数不一致ケースを表現できていないことが判明した。本 Issue の根本原因と直結し、修正コストが低いため Implementation Steps 4 として追加した。専用の Pre-merge AC は設けていない (Issue 本文の Scope 外である旨を明確にするため)。
- **Fail-safe critical script identification**: 本 Issue が変更するのは SKILL.md のプローズ手順とドキュメントのみであり、`scripts/pre-merge-check.sh` を含むいずれの `.sh` ファイルも変更しない (`case` の dispatch table に新規エントリを追加しない)。fail_open/fail_closed の分岐を新設しないため、本チェックの対象 (a)/(b)/(c) のいずれにも該当しないと判断した。
- **新規分岐ロジックへのテストケース要件**: 本 Issue はスクリプトへの新規分岐ロジック追加を伴わない (SKILL.md ドキュメント追記のみ) ため、新規 bats テストケースの追加は不要と判断した。既存スイート (`bats tests/`) が回帰なく PASS することのみを AC3 で確認する。
- **Steering Docs sync candidate check**: 抽出キーワード `"ci-failure-classifier.md"` (18 ヒット) と `"review"` (1098 ヒット) はいずれも discriminating power フィルタ (8 件超) でスキップされた。個別列挙は行っていない。

## Consumed Comments

- **saito** (MEMBER, first-class): `/issue` フェーズの Issue Retrospective コメント。`session=next` タグ欠落の修正、曖昧性の自動解決記録 (決定性判別手段の選定と件数不一致シグナル追加方法を `/spec` に委任)、前フェーズ (`/triage`) からの Consumed Comments 引き継ぎを含む。いずれも Issue 本文の内容と重複しており、本 Spec に対する新規の指示は含まれていなかった。 https://github.com/saitoco/wholework/issues/1466#issuecomment-5651664760
- `/code` フェーズ: cutoff (`phase/ready` ラベル付与時刻 2026-09-13T06:48:09Z) 以降の新規コメントなし。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1–5 をそのまま実装した。

### Design Gaps/Ambiguities
- Spec の Changed Files には含まれていなかったが、`docs/tech.md` はトップレベル `docs/*.md` として `docs/translation-workflow.md` の同期義務対象であり、Step 9 のドキュメント整合性チェック (`docs/ja/` 同期チェック) で `docs/ja/tech.md` との同期ギャップが検出された。対応する日本語訳 (4 行目の追加行と補足文) を `docs/ja/tech.md` に追記した。Spec 作成時点で `docs/ja/` 同期義務の対象になることが見落とされていたが、実装フェーズの機械チェックで捕捉されたため実害はなかった。

### Rework
- N/A — 手戻りは発生しなかった。

## review retrospective

### Spec vs. implementation divergence patterns

なし。`review-light` エージェントによる検証で、Implementation Steps 1–5 は diff とすべて一致していることを確認した。`docs/ja/tech.md` の同期追記は Spec の Changed Files に未記載だったが、Code フェーズの機械チェック (`docs/translation-workflow.md` 同期義務) が既に捕捉・修正済みで、review 時点で新規の乖離は残っていなかった。

### Recurring issues

本 Issue 自体が「#1462 review retrospective の誤診断」を発端としており、CI 失敗診断における「既存失敗であること」と「非決定的 (フレーク) であること」の混同という同種の誤りが再発しやすい領域であることを示している。今回追加された "Scope decision" / "Required condition for future generalization" のセクションは、この混同を将来の汎用化提案が繰り返さないための明示的なガードレールとして機能する見込み。

また、`/triage` の AC verify command 監査が Pre-merge AC2 (grep) の「常時 PASS」パターンを Issue 段階で事前検出し、`/spec` 着手前に本文が修正されていた。今回の review では AC2 は正常に機能する状態で検証できており、verify command 品質問題の再発を上流フェーズで防いだ好例として記録する。

### Acceptance criteria verification difficulty

UNCERTAIN なし。rubric (AC1) は `skills/review/SKILL.md` の該当セクションを目視で確認し明確に PASS 判定できた。grep (AC2) は上記の事前修正により固有文字列にマッチする健全な verify command として機能した。command (AC3、`bats tests/` 全件) は 18 並列実行で 2074 件 PASS・件数不一致なしを確認。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Step 7 は `.wholework.yml` に `copilot-review`/`claude-code-review`/`coderabbit-review` のいずれも設定されておらず全て `false` のため、7.1–7.6 を全てスキップし Step 8 に進んだ。
- Step 10 は `REVIEW_DEPTH=light` (ARGUMENTS の `--light` 明示指定、Size=M とも整合) のため、`review-light` エージェント 1 体による軽量統合レビューを実施した。

### Deferred Items
- 決定性判別の自動化 (複数 run 再現率収集、結果比較ロジック) は本 Issue のスコープ外のまま — `/code` フェーズの Deferred Items を引き継ぐ (将来の汎用化 Issue に委ねる)。
- Post-merge AC (決定的な既存失敗を含む PR での `/review` 実行観察、`verify-type: observation event=auto-run session=next`) は未検証のまま — 次回の `/verify` セッションで観察される。

### Notes for Next Phase
- MUST/SHOULD/CONSIDER のいずれも検出されなかったため Step 12 (修正サイクル) は実行していない。`/merge` にそのまま進んで良い。
- CI は全 15 ジョブ (7 種 × push/pull_request) SUCCESS。Pre-existing failure exception は不発火 (該当ジョブなし)。
- 本 PR はドキュメント追記のみ (`modules/ci-failure-classifier.md`, `skills/review/SKILL.md`, `docs/tech.md`, `docs/ja/tech.md`) — `scripts/pre-merge-check.sh` や `.github/workflows/test.yml` への変更はない。
