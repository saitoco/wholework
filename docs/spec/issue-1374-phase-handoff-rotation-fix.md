# Issue #1374: verify: Phase Handoff ローテーションが merge フェーズで既存ブロックを置換せず二重化する

## Overview

`modules/phase-handoff.md` の Write Procedure は、既存の `## Phase Handoff` ブロックを検索し、見つかった場合は Edit tool でブロック全体を置換する (ローテーション) と規定している。しかし Issue #1363 の `/verify` 実行時、`/merge` フェーズの書き込みで既存の `code` フェーズのブロックが置換されず、`## review retrospective` セクションの後に新しい `merge` フェーズのブロックが追加され、同一 Spec ファイル内に `## Phase Handoff` セクションが2つ残留する事態が観測された。

本 Issue は、この "latest 1 phase" 不変条件の違反を防ぐため、ローテーション処理に決定論的な安全網を追加する。

## Reproduction Steps

1. `/code` が最初の `## Phase Handoff` ブロック (`<!-- phase: code -->`) を Spec に書き込む。
2. `/review` が `## review retrospective` セクションを追記した後、Write Procedure に従い既存ブロックを `<!-- phase: review -->` へ置換しようとする。
3. `/merge` が squash merge 後、Write Procedure に従い既存ブロックを `<!-- phase: merge -->` へ置換しようとする (Edit tool による「既存ブロック検索 → ブロック全体置換」)。
4. Issue #1363 の実測では、最終的な Spec に `<!-- phase: code -->` ブロック (旧) と `<!-- phase: merge -->` ブロック (新) の2つが残留していた。後者は `## review retrospective` セクションの後に新規追加される形になっており、既存ブロックの検出・置換が機能しなかったことを示す。

## Root Cause

Write Procedure の Step 3 (既存ブロック検出・置換) は、LLM が Edit tool を用いて実行するプローズ手順のみで規定されており、置換が実際に正しい境界 (次の `## ` 見出しまたは EOF の直前まで) を検出・削除できたかを機械的に検証する仕組みがない。

対照的に、同じく Spec ファイルへの追記を行う Consumed Comments 機構 (`modules/l0-surfaces.md`) は、LLM 主導の Edit 試行 (Primary) に加えて、決定論的な bash 後処理 (`scripts/append-consumed-comments-section.sh`, Secondary) を持つ二層構成になっている。Phase Handoff の Write Procedure にはこの Secondary 層が存在しないため、LLM の Edit 呼び出しが既存ブロックの境界検出に失敗した場合 (コンテキスト圧迫時や境界判定の曖昧性など) に、"latest 1 phase" 不変条件が無言で破られ、これを検知・修正する手段がなかった。

## Changed Files

- `scripts/dedupe-phase-handoff-section.sh`: new file — Phase Handoff ローテーションの決定論的フォールバック。指定 Issue の Spec ファイルを特定し、`## Phase Handoff` 見出しが2つ以上存在する場合、最後 (最新) の1ブロックのみを残し、それより前のブロック (各ブロックは見出し行から次の `## ` 見出し行の直前、または EOF まで) を削除する。1つ以下ならno-op。commit/push は行わない (呼び出し元が直後に行う既存の commit ステップがファイル差分を拾う設計)。bash 3.2+ 互換。`scripts/append-consumed-comments-section.sh` の SPEC_FILE 特定ロジック (`get-config-value.sh spec-path` 経由) を踏襲する。
- `modules/phase-handoff.md`: Write Procedure Step 4 の後に、新しい決定論的フォールバックの存在と呼び出し元 (code/review/merge の各 SKILL.md) を説明する記述段落を追加 (`modules/l0-surfaces.md` の "Bash wrapper fallback" と同様、ポインタ的な説明であり本モジュール自身の実行手順ではない)。`## Notes` に二層構成 (LLM Edit 試行 = Primary、bash dedupe = Secondary) の要約を追記。
- `skills/code/SKILL.md`: Phase Handoff write ステップ (Step 5, L703-706) の直後・commit ステップ (Step 6, L707) の前に、`bash ${CLAUDE_PLUGIN_ROOT}/scripts/dedupe-phase-handoff-section.sh $NUMBER` 呼び出しを新ステップとして挿入 (以降のステップ番号を1つ繰り下げ)。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/dedupe-phase-handoff-section.sh:*` を追加 (`append-consumed-comments-section.sh:*` の隣)。
- `skills/review/SKILL.md`: Phase Handoff write ステップ (Step 4, L893-896) の直後・commit ステップ (Step 5, L897) の前に、`bash ${CLAUDE_PLUGIN_ROOT}/scripts/dedupe-phase-handoff-section.sh $ISSUE_NUMBER` 呼び出しを新ステップとして挿入 (以降のステップ番号を1つ繰り下げ)。frontmatter `allowed-tools` に同エントリを追加。
- `skills/merge/SKILL.md`: 「Phase Handoff write」内の substep 3 (Write Procedure 呼び出し, L270-271) の直後・substep 4 (commit, L272) の前に、同スクリプト呼び出しを新 substep として挿入。frontmatter `allowed-tools` に同エントリを追加。
- `tests/phase-handoff.bats`: 新規テストケースを追加 (→ acceptance criteria B)。既存の「ドキュメント文言確認のみ」の shallow test に加え、`scripts/dedupe-phase-handoff-section.sh` の実際のローテーション挙動を検証する test を追加する。最低限: (a) spec ファイルが存在しない場合は exit 0 で no-op、(b) `## Phase Handoff` が1個以下なら no-op でファイル内容が変化しない、(c) **回帰シナリオ**: 既存の `## Phase Handoff` ブロックの後に `## review retrospective` など別の `## ` 見出しセクションが続き、さらにその後に2つ目の `## Phase Handoff` ブロックが存在する fixture に対してスクリプトを実行し、実行後は `## Phase Handoff` が1個のみ残り、その内容が2つ目 (最新) のブロックと一致し、1つ目のブロックの内容 (`### Key Decisions` 等の本文) が削除されていることを確認する。ファイル冒頭のコメント (「LLM レスポンスはモックしない」旨) を実態に合わせて更新する。
- `docs/structure.md`: Scripts 一覧 (`scripts/append-consumed-comments-section.sh` エントリの近く) に新スクリプトのエントリを追加。Directory Layout の `scripts/` ファイル数コメントを `(87 files)` → `(88 files)` に更新。
- `docs/ja/structure.md`: 上記 `docs/structure.md` の変更を日本語訳として反映 (`docs/translation-workflow.md` の Sync Procedure に従う)。`(87 ファイル)` → `(88 ファイル)`。

## Implementation Steps

1. `scripts/dedupe-phase-handoff-section.sh` を新規作成する (→ acceptance criteria A)。
   - Fail-safe critical 該当性: 本スクリプトは失敗時に「安全側のデフォルト」(ファイル変更を行わず終了) を返す設計であるため、以下のエッジケースの期待動作を明記する:
     - 空入力/巨大入力: Spec ファイルが存在しない → stderr に警告し exit 0 (no-op)。`## Phase Handoff` 見出しが0または1個 → exit 0 (no-op)。ファイルサイズに起因する特別処理は不要 (awk のストリーム処理で対応可能)。
     - 特殊文字 (`>`, `"`, 改行, CRLF, 多バイト文字): ブロック本文に含まれる任意の文字は awk の `print` でそのまま透過するため無害。見出し行のプレフィックスマッチ (`^## Phase Handoff` / `^## `) のみで判定し、本文の文字種に依存しない。CRLF 混在時も行頭プレフィックスマッチには影響しない。
     - 依存コマンド失敗時の挙動 (fail-open/fail-closed とその理由): `awk` 実行自体が失敗した場合、または書き換え結果が空になった場合は、一時ファイルを破棄し **元のファイルを一切変更せず** exit 0 で終了する (fail-closed: 書き換えの安全性を保証できない場合はファイルを壊すより現状の二重化を許容する)。一方、呼び出し元 (SKILL.md) への影響としては常に exit 0 を返す best-effort 設計 (fail-open: dedupe に失敗してもフェーズの commit 自体は妨げない)。理由: 二重化の実害は軽微 (Background 参照) だが Spec 本文の欠損は Spec 全体の cross-phase memory を損なう、非対称なリスクであるため。
   - ロジック: `## Phase Handoff` 見出しの出現数を `grep -c` で数え、2以上の場合のみ awk で「最後の出現より前のブロックを削除」する単一パスの書き換えを行う (境界検出は `append-consumed-comments-section.sh` の `awk -v start=... 'NR>start && /^## /{print NR; exit}'` パターンと同じ考え方 — 次の `## ` 見出しでブロック終端と判定)。
2. (after 1) `modules/phase-handoff.md` を更新する (→ acceptance criteria A)。Write Procedure Step 4 の後に、決定論的フォールバックの存在と3つの呼び出し元 (code/review/merge) を説明する段落を追加。`## Notes` に二層構成 (Primary: LLM の Edit 試行、Secondary: `scripts/dedupe-phase-handoff-section.sh`) の要約を1行追加する。
3. (after 1, 2) `skills/code/SKILL.md`・`skills/review/SKILL.md`・`skills/merge/SKILL.md` の3ファイルに、Phase Handoff write ステップ直後・commit ステップ直前の位置で `scripts/dedupe-phase-handoff-section.sh` 呼び出しを追加し、各ファイルの frontmatter `allowed-tools` に対応エントリを追加する (→ acceptance criteria A)。挿入位置は Changed Files セクション記載のとおり。
4. (after 1) `tests/phase-handoff.bats` に新規テストケースを追加する (→ acceptance criteria B)。既存スイートが PASS することだけでなく、Changed Files セクションで記述した回帰シナリオ (既存ブロックの後に別セクションが続き、さらに2つ目の Phase Handoff ブロックが続く状態でのローテーション) を検証する新規テストケースを追加したうえでスイートが PASS すること。fixture・モック規約は `tests/append-consumed-comments-section.bats` の `setup()` パターン (`WHOLEWORK_SCRIPT_DIR` モックディレクトリ、`BATS_TEST_TMPDIR` ベースの repo fixture、`get-config-value.sh` のモック) に倣う。
5. (after 1, 3, 4) `docs/structure.md` と `docs/ja/structure.md` を更新し (Changed Files セクション参照)、全 bats テストスイートを実行して回帰がないことを確認する (→ acceptance criteria A, C)。

## Verification

### Pre-merge

- <!-- verify: rubric "modules/phase-handoff.md の Write Procedure が、既存の Phase Handoff セクション検出・置換を確実に実行する仕組み (決定論的 bash fallback の追加、または LLM 手順の明確化・検証ステップ追加) を備えるよう更新されている" --> Phase Handoff のローテーションが確実に機能するよう改善されている
- <!-- verify: rubric "tests/phase-handoff.bats に、既存の `## Phase Handoff` ブロックの後に別のセクション (`## Phase Handoff` 以外の `## ` 見出し) が続く状態でローテーション処理が既存ブロックを正しく検出・置換し、二重化を防ぐことを検証する新規テストケースが追加されている" --> 二重化再発を防ぐ回帰テストが追加されている
- <!-- verify: command "bats tests/*.bats" --> 既存の bats テストがすべて PASS する
- <!-- verify: grep "(88 files)" "docs/structure.md" --> docs/structure.md の scripts/ ファイル数コメントが新規スクリプト追加を反映している

### Post-merge

なし

## Notes

**実装アプローチの Auto-Resolve (非対話モード)**: Issue の Auto-Resolve Log は「決定論的 bash fallback 追加 vs. LLM 手順明確化」の選択を `/spec` の裁量に委ねていた。本 Spec は **決定論的 bash fallback (dedupe スクリプト) を採用**する。理由:
1. AC2 (rubric) が要求する新規回帰テストは、実際に呼び出し可能な決定論的手順に対してのみ書ける — bats は LLM のプローズ手順の遵守そのものをテストできないため、AC2 を満たすには何らかの決定論的スクリプトが必要になる。
2. `append-consumed-comments-section.sh` (`modules/l0-surfaces.md` Bash wrapper fallback) という構造的に類似した Primary/Secondary 二層構成の前例が既に本番で機能しており、これに倣うことでリスクを抑えられる。

**設計判断: commit/push ロジックを持たせない**: `append-consumed-comments-section.sh` は単独の安全網として主コミットの後に発火しうるため自前の commit/push を持つ。本スクリプトは常に各フェーズの「Phase Handoff write ステップの直後・既存の commit ステップの直前」という in-session の位置に挿入されるため、修正結果は既存の commit ステップ (`$SPEC_PATH/issue-$NUMBER-*.md` を git add 済み) にそのまま含まれる。したがって本スクリプト自身に commit/push ロジックは不要で、`append-consumed-comments-section.sh` より単純な実装になる。

**スコープ外: `/spec` と `/verify` は配線しない**: `modules/phase-handoff.md` の Phase Position Asymmetry 表より、`spec` は Write=Yes だが常に「最初の書き手」であり (既存ブロックが存在しない状態でのみ書き込む)、構造的に既存ブロックへ遭遇し得ない (rotation 分岐に到達不能) ため配線しても常に no-op になる。`verify` は Write=No のため対象外。よってフォールバックを配線するのは `code`/`review`/`merge` の3スキルのみとする。

**allowed-tools 影響: Case 2 (module 変更) は非該当と判断**: `modules/phase-handoff.md` に追加する記述はポインタ的な説明 (どのSKILL.mdが呼ぶかの記録) であり、本モジュール自身の Processing Steps が新スクリプトの実行をこのモジュールの読者に指示するものではない (`modules/l0-surfaces.md` の "Bash wrapper fallback" と同じ位置づけ)。したがって `spec`/`verify` の allowed-tools 更新は不要と判断し、実際に3スクリプト呼び出しを追加する `code`/`review`/`merge` の3ファイルのみ Case 1 として allowed-tools を更新する。

**Steering Docs 確認 (変更不要と判断)**: `docs/product.md` (Terms § Phase Handoff)・`docs/tech.md` (Cross-phase memory mechanisms)・`docs/workflow.md` (operate route の Phase Handoff 言及) を grep で確認したが、いずれも Phase Handoff の概念・フォーマット・フェーズ順序といったインターフェースレベルの記述に留まり、ローテーションの信頼性という実装詳細には踏み込んでいないため、変更不要と判断した。`docs/structure.md` (Scripts 一覧・ファイル数) のみ、新規スクリプトファイル追加に伴う機械的な更新が必要。

**Pre-merge 検証項目数の差異 (Issue body 3件 → Spec 4件) について**: Issue body の Acceptance Criteria (3件) はそのまま転記した。4件目 (`docs/structure.md` のファイル数確認) は `/spec` の Steering Docs sync 調査で判明した文書整合性の機械的な確認であり、Issue body 側の要求範囲 ("What") を変更するものではないため Issue body への追加は行わず、Spec 側にのみ追加した (Count alignment check は許容される差異として想定されている)。

**新規分岐ロジックに対する新規テストケース要件のまとめ** (SPEC_DEPTH=light のため本来の spec retrospective の代わりにここへ記録): Implementation Step 1 は `scripts/dedupe-phase-handoff-section.sh` という新規スクリプト (新規ロジック) を追加する。対応する Verification 項目 (AC2, rubric) は、既存スイートの PASS だけでなく `tests/phase-handoff.bats` への新規テストケース追加を明示的に要求しており、Implementation Step 4 で具体的な回帰シナリオ (既存ブロック + 別セクション + 新ブロックの3層構成) を規定した。

**bats テスト入力フォーマット**: fixture として使う Spec ファイルは `modules/phase-handoff.md` の Phase Handoff Section Format (`## Phase Handoff` / `<!-- phase: {name} -->` / `### Key Decisions` / `### Deferred Items` / `### Notes for Next Phase`) に準拠したテキストを用いる。モック規約は `tests/append-consumed-comments-section.bats` の `setup()` (WHOLEWORK_SCRIPT_DIR モックディレクトリに `get-config-value.sh` を配置し `spec-path` に `docs/spec` を返す、`BATS_TEST_TMPDIR/repo/docs/spec/issue-N-*.md` に fixture を作成) に倣うこと。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: 判断根拠および Auto-Resolve Log の記録 (AC 2→3件、Post-mergeセクション新設) / https://github.com/saitoco/wholework/issues/1374#issuecomment-5306815790

### /code (cutoff: phase/ready assigned 2026-08-16T10:04:39Z)

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- `tests/code.bats` も変更対象に追加した (Spec の Changed Files には未記載) — 理由: Step 9 でフルスイート実行を行った際、本 Issue とは無関係の既存バグ (`tests/code.bats` の Step 10 CI AC exclusion アサーションが、#1375 適用後の実際の `skills/code/SKILL.md` 文言 "Step 10 runs before the commit or PR that would produce a CI run" と食い違っており、常に FAIL していた) を検出した。本 Issue の Pre-merge AC (`command "bats tests/*.bats"` が全 PASS すること) を満たすために、アサーション文字列を実際の SKILL.md 文言に合わせて 1 行修正した。スコープ外の修正だが、影響範囲は該当テストの期待文字列 1 行のみで、独立 Issue を起票するほどの規模ではないと判断し、本 PR に含めた。

### Design Gaps/Ambiguities
- なし。Spec の Implementation Steps 1-5 は記述どおりに実装できた。

### Rework
- なし。

## review retrospective

### Spec vs. implementation divergence patterns

なし。実装 (dedupe スクリプト、3 SKILL.md への配線、`modules/phase-handoff.md` の説明追加、回帰テスト) は Spec の Implementation Steps と一致していた。Code Retrospective に記録済みのスコープ外修正 (`tests/code.bats` 1行) も理由付きで妥当と判断。

### Recurring issues

なし。今回検出した 2 件 (MUST/SHOULD) は、決定論的パーサースクリプトを新規追加する PR 全般に共通する「構造解析コードは実行ベースの edge case pre-check で検証すべき」というレビュー観点そのものが機能した結果であり、過去 PR で繰り返し観測されたパターンの再発ではない。

### Acceptance criteria verification difficulty

なし。3件の Pre-merge AC (rubric ×2、command ×1) はすべて機械的に判定可能だった。command 条件は safe mode の CI reference fallback (`Run bats tests` ジョブの run command containment 確認) で PASS 判定でき、フル実行を要さなかった。

### Improvement Proposals

- **新規の決定論的パーサー/バリデータースクリプトを追加する PR では、`/review` の Parser/Validator Edge Case Pre-check が実行ベースの edge case 実行で 2 件 (MUST 1, SHOULD 1) の未検出バグを実際に発見した** — 本 PR (#1388) 自身が「二重化を防ぐ決定論的フォールバック」を追加する PR でありながら、そのフォールバック自身の境界検出ロジック (`grep`/`awk` による見出し検出) がフェンスコードブロックを考慮していないという盲点を持っていた。Pre-check の効果が実証されたケースとして記録 (Issue 起票は不要 — 既に fix 済みで /verify 側の集約対象として次フェーズに委ねる)。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash merge (PR #1388) を pre-merge AC 3件全チェック済み・review-incomplete-fallback なし・mergeable=clean の状態で実行した。追加コミット (`085489cf`) を含め CI green を確認済みだった。
- `main` への squash merge 後、worktree を `origin/main` に fast-forward してから Phase Handoff の書き込みを行った (squash merge で PR ブランチが削除されるため、書き込みは post-squash に行う設計)。

### Deferred Items
- None

### Notes for Next Phase
- Post-merge AC はなし (Issue #1374 本文の `### Post-merge` セクションに記載どおり) — `/verify` は特段の検証作業なしで Issue クローズ状態を確認するのみでよい。
