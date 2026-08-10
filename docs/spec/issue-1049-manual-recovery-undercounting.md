# Issue #1049: run-auto-sub: --write-manual-recovery の manual_intervention event under-counting 調査

## Overview

`run-auto-sub.sh --write-manual-recovery` による `manual_intervention` event の under-counting を調査する Issue。当初は emission path 側のバグを疑っていたが、Issue 本文のコメント欄で行われた対照実験 (session `97764-1786198856` vs `1497-1786326732`) により、真因は emission path ではなく「`--write-manual-recovery` の呼び出しの有無」そのものと判明済みだった。本 Spec では、その上で (主) なぜ既存の呼び出し規定 (`skills/auto/SKILL.md` の Manual recovery hand-off) が session `97764` で遵守されなかったかを実地調査で特定し、再発防止の是正を実装する。(従) `#1224` 適用後に emission path 側の under-counting が再現するかをコードレベルで再検証する。

## Reproduction Steps

1. `/auto` 実行中に Tier 1/2/3 いずれの自動復旧も届かない障害が発生し、親セッションが手動で復旧する (実例: `#1304` の merge フェーズで `mergeable: UNKNOWN` を待つ復旧、`#1305` の `phase/issue` ラベル付与漏れの復旧)
2. 親セッションは復旧完了後、`skills/auto/SKILL.md` の Manual recovery hand-off 規定 (該当箇所: Stop-and-Report Fallback 直後の "Manual recovery hand-off" 段落) に従って `run-auto-sub.sh --write-manual-recovery` を呼ぶことなく次フェーズへ進行する
3. 後続の `/verify` が Step 12 (Retrospective) を実行し、`docs/reports/orchestration-recoveries.md` に当該 Issue のエントリが存在しないことを検知する
4. Step 12 の現行規定 "If a Tier 2, Tier 3, or Manual recovery occurred but is recorded in neither `orchestration-recoveries.md` nor a pre-existing Spec entry, it qualifies as notable content. Do not skip; record it in the verify retrospective." に従い、LLM が Spec の `## Verify Retrospective` 内に `### Manual recovery (parent session)` という自由記述の節を追記する (`#1304`・`#1305` の実 Spec で確認済み)
5. 結果として `docs/reports/orchestration-recoveries.md` にはエントリが追加されず、`manual_intervention` event も emit されないまま、Spec 上のプレーンテキストのみが「記録された」という体裁を作ってしまう

## Root Cause

### なぜ既存規定 (`skills/auto/SKILL.md` Manual recovery hand-off) が session 97764 で遵守されなかったか

`session 97764-1786198856` (2026-08-09) が扱った `#1304` / `#1305` の実 Spec ファイルを調査した結果、`--write-manual-recovery` が呼ばれなかった理由は `skills/auto/SKILL.md` 側の可視性問題ではなく、**`skills/verify/SKILL.md` Step 12 (Retrospective) 自身の規定が原因**と判明した。

両 Spec の `### Manual recovery (parent session)` 節はいずれも次の一文で始まる:

> `docs/reports/orchestration-recoveries.md` に本 Issue のエントリが存在しないため、`skills/verify/SKILL.md` Step 12 の規定に従いここに記録する。

これは `skills/verify/SKILL.md` Step 12 の「Tier 2/3/Manual automatic recovery handling」規定にある以下の一文を LLM が文字通り実行した結果である:

> "If a Tier 2, Tier 3, or Manual recovery occurred but is recorded in neither `orchestration-recoveries.md` nor a pre-existing Spec entry, it qualifies as notable content. Do not skip; record it in the verify retrospective."

つまり、実際に復旧が起きた時点 (`/auto` 親セッションによる手動復旧) で `--write-manual-recovery` の呼び出しが漏れていたのは事実だが、その「漏れ」を後から検知する唯一の仕組みである `/verify` Step 12 は、検知した際の対処として「Verify Retrospective に記述する」(Spec へのプレーンテキスト追記) しか指示していない。**正規の記録先 (`orchestration-recoveries.md` + `manual_intervention` event) へ遡って書き戻す指示を一切含んでいない。** この結果、LLM は `#1181` で撤去されたはずの「Manual recovery を Spec に書き込む」という挙動を、bash 自動化 (`_write_manual_recovery_to_spec()`) ではなく Step 12 の指示に従う形で再現してしまった — `#1181` のクローズ (2026-08-05) からわずか 4 日後の事象である。`modules/orchestration-fallbacks.md` の `manual-recovery-spec-write` エントリ自身が「steady stream of retro/verify Issues (`#1049`, `#1094`, `#1150`, `#1152`, `#1153`, `#1155`)」として本 Issue番号を旧設計の問題事例として引用しており、本 Issue はその同型の経路が新設計下でも再来した事例である。

これは「`skills/auto/SKILL.md:1084` の可視性が低い」という Issue 本文の当初仮説より一段深い構造的ギャップである。仮に 1084 行目の hand-off 指示の可視性を上げても、実際の復旧作業中に何らかの理由で見落とされるケースは今後も起こり得る。Step 12 が「検知はするが是正はしない」設計である限り、そのたびに Spec への直接記述という同型の bypass が再発する。

### `_write_manual_recovery_to_recoveries_log()` / `emit_event` の呼び出し順序再確認 (`#1224` 適用後)

`scripts/run-auto-sub.sh` の `--write-manual-recovery` ディスパッチ (`if [[ "${1:-}" == "--write-manual-recovery" ]]; then ... fi` ブロック) を再読した結果:

- `_write_manual_recovery_to_recoveries_log()` の呼び出しは `emit_event "manual_intervention" ...` より前に実行されるが、同関数内の全パス (ファイル不在時の early `return 0`、`_is_duplicate` によるログ追記スキップ、`_pull_ff_only`/`git commit`/`push` 失敗時の `if ! ...; then ... fi` ガード) はいずれも非 fatal であり、後続の `emit_event` 呼び出しをブロックしない。スクリプトが実際に起動されさえすれば `manual_intervention` event の emit は無条件に実行される
- `session 97764` の 2 件はいずれも `--write-manual-recovery` 自体が呼ばれていない (前項) ため、この emission path 自体の再現性を肯定・否定する直接の材料にはならないが、コードレベルでは `#1224` 適用後も新たな silent skip 候補は見つからなかった
- `#1224` (2026-08-07 CLOSED) が撤去した `restore_auto_session_pointer()` の危険なフォールバック (`.tmp/auto-session-current` への無条件フォールバック) は、当初の 4→3 under-counting (`session 30985-1784807775`, `#1224` 適用前) の妥当な説明候補である: 呼び出しは実際に行われたが、フォールバックが別セッションの stale pointer を拾って `session_id` を誤帰属させ、`session_id` でフィルタする L3 metrics 集計 (`get-auto-session-report.sh --metrics-only`) からその 1 件が漏れて見えた、という機序が成立する (event 自体は `.tmp/auto-events.jsonl` に書き込まれているが、誤った/空の `session_id` で書かれるため正しいセッションからは見えなくなる)。この機序は `#1224` で該当フォールバックが削除されたことで解消しており、`tests/emit-event.bats` の `"restore_auto_session_pointer does not fall back to auto-session-current when no session-specific pointer resolves (Issue #1224...)"` が既に回帰防止テストとして存在する
- **結論**: `#1224` 適用後に「呼び出しは行われたが event 数が一致しない」という当初と同型の実地事例は観測されていない (`session 97764`/`1497` はいずれも「呼び出しの有無」自体が分岐点であり、emission path 側の問題ではない)。コードレベルの再検証では新たな silent skip 機序は見つからず、当初観測の説明候補だった機序は `#1224` で解消済みと判断する。実地での完全な再確認は、下記 Post-merge の観察 AC に委ねる

## Changed Files

- `skills/verify/SKILL.md`: Step 12「Tier 2/3/Manual automatic recovery handling」規定を編集 — Manual recovery 未記録ケースの bullet を Tier 2/Tier 3 と分離し、Verify Retrospective への記述前に `run-auto-sub.sh --write-manual-recovery` を遡って呼び出す (backfill) 指示を追加。同時に frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*` を追加 (現状未許可 — 下記 Notes 参照)
- `modules/orchestration-fallbacks.md`: `manual-recovery-spec-write` エントリの `### Rationale` (`#1181` 簡略化の記述の直後) に、`/verify` Step 12 からの retroactive backfill 呼び出しを 2 つ目の呼び出し元として追記
- `tests/run-auto-sub.bats`: 既存の `@test "run-auto-sub: manual recovery: emits manual_intervention event with intervention_type"` の直後に、`--write-manual-recovery` を 4 回連続呼び出し `manual_intervention` event が 4 件記録されることを assert する新規 `@test` を追加
- `docs/tech.md` [Steering Docs sync candidate]: `## Architecture Decisions` 内の "Parent-session manual respawn" 段落は `--write-manual-recovery` の呼び出し元を `/auto` 側のみ記述している。`/verify` Step 12 からの backfill 呼び出しを追記するか要確認 (`/code` が判断)
- `docs/workflow.md` [Steering Docs sync candidate]: "External kill respawn" 段落も同様に `/auto` 側の呼び出しのみ記述。同上の追記要否を確認 (`/code` が判断)
- `docs/ja/tech.md`, `docs/ja/workflow.md` [Steering Docs sync candidate]: 上記 2 ファイルを更新する場合、`docs/translation-workflow.md` の同期手順に従い対応する ja ミラーの更新要否も確認

## Implementation Steps

1. `skills/verify/SKILL.md` Step 12 の該当 bullet を編集する (→ 受入基準2)
   - 現行の "If a Tier 2, Tier 3, or Manual recovery occurred but is recorded in neither `orchestration-recoveries.md` nor a pre-existing Spec entry, it qualifies as notable content. Do not skip; record it in the verify retrospective." を、(a) Tier 2/Tier 3 向けの記述はそのまま維持し、(b) Manual recovery 向けに新しい bullet を追加する形へ分割する
   - 新 bullet の内容: 未記録の Manual recovery を検知した場合、まず `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh --write-manual-recovery $NUMBER PHASE RECOVERY_TYPE` (EXIT_CODE は省略 — 事後のため観測不能。PHASE/RECOVERY_TYPE は Step 12 の Steps 1 で収集済みの git log / Spec / Issue 本文から特定する) を呼び出して `orchestration-recoveries.md` と `manual_intervention` event を遡って補完し、その後に従来通り Verify Retrospective へ記述する、という 2 段の手順を明記する。呼び出し済みで recoveries.md にエントリがある場合は本 bullet の対象外 (既存の "already recorded" 判定を維持)
   - 同じ編集の一部として、frontmatter `allowed-tools` の Bash パターン列に `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*` を追加する (現状 `skills/verify/SKILL.md` の `allowed-tools` に本スクリプトへの明示的な許可がないため)
2. `modules/orchestration-fallbacks.md` の `manual-recovery-spec-write` エントリの `### Rationale` に、Issue #1049 として新しい bullet を追加する (after 1) (→ 受入基準2)
   - `/verify` Step 12 が未記録の Manual recovery を検知した際に同じ `--write-manual-recovery` コマンドを遡って呼び出すようになったこと、およびこれが `/auto` の real-time hand-off (`skills/auto/SKILL.md` 該当箇所) の見落としに対する backstop であることを記録する
3. `tests/run-auto-sub.bats` に新規 bats テストを追加する (parallel with 1, 2) (→ 受入基準4)
   - 既存の `@test "run-auto-sub: manual recovery: emits manual_intervention event with intervention_type"` と同じモック構成 (mocked `emit-event.sh` が `emit_event` 呼び出しを `$EMIT_LOG` に記録) を使用
   - `--write-manual-recovery 42 code push-only` を 4 回連続実行し、`grep -c manual_intervention "$EMIT_LOG"` が `4` と一致することを assert する

## Verification

### Pre-merge

- <!-- verify: rubric "session 97764-1786198856 において、skills/auto/SKILL.md の既存の Manual recovery hand-off 規定 (--write-manual-recovery 呼び出し) がなぜ遵守されなかったかの調査結果が Spec の Root Cause セクションに記録されている" --> `skills/auto/SKILL.md` の既存規定が session 97764 で遵守されなかった原因が調査され、Spec に記録されている
- <!-- verify: rubric "手動復旧時に --write-manual-recovery の呼び出しを確実にするための手順強化 (skills/auto/SKILL.md の視認性向上、または modules/orchestration-fallbacks.md への記録先明記) が実装されている、または実装しない場合はその判断理由が Spec に記録されている" --> 呼び出し側のコンプライアンスを強化する修正が実装されている (または非実装の判断理由が記録されている)
- <!-- verify: rubric "Issue #1224 適用後の状態で、_write_manual_recovery() の N 回呼び出しに対し N 件の manual_intervention event が記録されるか (当初観測の 4→3 under-counting が再現するか) の再検証結果が Spec に記録されている" --> #1224 適用後に当初の 4→3 under-counting が再現するかどうかが再検証され、結果が Spec に記録されている
- <!-- verify: rubric "tests/run-auto-sub.bats または tests/auto-sub-observability.bats に、N (例: 4) 回の --write-manual-recovery 呼び出しで auto-events.jsonl に N 件の manual_intervention event が記録されることを assert する test が追加され、PASS することが確認されている" --> 修正が実装されている場合、N 回連続の `--write-manual-recovery` 呼び出しで N 件の `manual_intervention` event が確実に記録されることを検証する bats テストが追加されている

### Post-merge

- 次に親セッションの手動復旧が発生した session で、`manual_intervention` event 数が実際の復旧回数と一致することを確認する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- 本 Issue は `#875` (session.md Metrics 一本化, CLOSED) の `## Out of Scope` で明示的に委譲された「manual recovery 未計上の根本解決」に該当する (`#875` との重複ではなく、`#875` が意図して切り出した範囲)
- `#1181` (CLOSED, 2026-08-05) は `_write_manual_recovery_to_spec()` という bash 自動化を撤去したが、本調査により `skills/verify/SKILL.md` Step 12 の "record it in the verify retrospective" 規定が、同型の Spec 直接記述を LLM の判断で再現させる経路として存置されていたことが判明した。`modules/orchestration-fallbacks.md` の `manual-recovery-spec-write` エントリ自身が挙げる「steady stream of retro/verify Issues」のリストに本 Issue 番号が含まれており、本 Issue はその経路の再来である
- 修正は `/verify` Step 12 の backfill 追加に限定し、`skills/auto/SKILL.md` の real-time hand-off 自体の文言は変更しない — hand-off 文言の可視性改善は効果測定が難しい一方、Step 12 側の backfill は「検知した時点で機械的に是正される」ため確実性が高く、real-time hand-off が何らかの理由で見落とされた場合の backstop として機能する
- Size は Issue 側 Project field で M と判定されているため SPEC_DEPTH=light を適用した (Implementation Steps 3件・Pre-merge Verification 4件はいずれも light の上限 5件以内)
- `docs/spec/issue-1304-nonpipe-negation-audit.md` および `docs/spec/issue-1305-known-events-firing-check.md` の実 Spec ファイルを一次資料として Root Cause の調査に使用した (両ファイルとも `### Manual recovery (parent session)` 節に `skills/verify/SKILL.md` Step 12 を明示的に引用している)

## Consumed Comments

| login | authorAssociation | trust tier | 意図要約 | URL |
|-------|-------------------|-----------|---------|-----|
| saito | MEMBER | first-class | `/issue` フェーズの Issue Retrospective。session 97764 (`manual_intervention` 0件) と session 1497 (同 2件) の対照実験結果を踏まえ、Purpose/AC を「呼び出し側コンプライアンス確保 (主)」「emission path 再検証 (従)」の二段構成へ改訂した経緯の記録。本 Spec 作成前に Issue 本文へ統合済みのため、本文を一次資料として直接使用した | https://github.com/saitoco/wholework/issues/1049#issuecomment-5240768609 |

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜3 を Spec の記述どおりに実装した

### Design Gaps/Ambiguities
- Notes の Steering Docs sync candidate (`docs/tech.md`/`docs/workflow.md` の Parent-session manual respawn / External kill respawn 段落) は「`/code` が判断」とされていたため、両段落に `/verify` Step 12 からの backfill 呼び出しが第二の呼び出し元であることを 1 文追記する判断を下した。`docs/ja/tech.md`/`docs/ja/workflow.md` も `docs/translation-workflow.md` の同期手順に従い同内容を追記し、code fence 数の一致を確認した

### Rework
- N/A

### Smoke Test
- Spec に `## Smoke Test` セクションが存在しないためスキップ (no-op)

### Test Suite Note
- Behavioral Change Detection の結果、`modules/orchestration-fallbacks.md` と `skills/verify/SKILL.md` を追加参照するテストファイルが直接対応ファイル以外に存在したため `bats --jobs 18 tests/` でフルスイートを実行した。`tests/post_merge_check.bats` の 2 件 (`fail: gh issue reopen called when FAIL input given` / `multiple issues: processed sequentially`) が並列実行時のみ FAIL したが、変更前のコード (`git stash` で本 Issue の diff を除去した状態) でも同じ 2 件が `bats --jobs 18 tests/post_merge_check.bats` で同様に FAIL し、単体実行では両状態とも PASS することを確認した — 本 Issue の変更とは無関係な既存の並列実行時 flaky test であり、既に Issue #1308 (open) がこの解消を追跡している。本 PR に関連するテスト (`tests/run-auto-sub.bats`, `tests/orchestration-fallbacks.bats`) は単体実行・フルスイート実行のいずれでも PASS した

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC gate は `unchecked_count=0` かつ `review_incomplete_fallback` 非該当 (`reconcile-phase-state.sh --check-completion` が organic な Review Response Summary を検出) だったため、override マーカーなしでそのまま squash merge を実行した
- `mergeable=true`/`reason=clean` だったため Step 3 (Resolve Conflicts) は不要 — 直接 Step 4 (Execute Squash Merge) に進行した

### Deferred Items
- Post-merge observation AC (次に手動復旧が発生した session での `manual_intervention` event 数一致確認) は引き続き未検証 (変更なし、`/verify` へ引き継ぐ)
- `tests/post_merge_check.bats` の並列実行 flaky test 解消は Issue #1308 に委譲 (本 Issue のスコープ外、変更なし)

### Notes for Next Phase
- `/verify` は Post-merge observation AC (`verify-type: observation event=auto-run session=next`) をそのまま未確定として扱ってよい — 次回の手動復旧発生を待つ性質の AC のため、今回の `/verify` 実行で確定させる必要はない

## review retrospective

### Spec vs. implementation divergence patterns
- 乖離なし。review-light エージェントが Spec の Implementation Steps 1〜3 / Changed Files と diff を突き合わせ、全項目が一致することを確認した。

### Recurring issues
- `skills/verify/SKILL.md:866` の新 bullet に対し、独立した 2 回のレビュー観点 (`_validate_recovery_args` の入力形式制約、`emit_event` の session pointer 依存による no-op) がいずれも「新規追加した指示文が、呼び出し先スクリプトの前提条件・失敗モードを書ききれていない」という同型のギャップを指摘した。新しい bash script 呼び出しを SKILL.md の自然言語手順に組み込む際は、呼び出し先の引数バリデーション規則 (`_validate_recovery_args` の正規表現等) と、呼び出し先が持つ暗黙の前提条件 (session pointer の解決可否等) の両方を、追加する bullet 自体に明記するかどうかを都度確認する価値がある。単発の Issue で汎用ルール化するには時期尚早だが、今後同種の指摘が別 PR でも出た場合は review checklist 化を検討する。

### Acceptance criteria verification difficulty
- 困難なし。4件の Pre-merge AC (rubric) はいずれも Spec の `## Root Cause` セクションと直接対応しており、機械的に PASS 判定できた。bats テスト AC も `bats --filter` で一意に実行・確認可能だった。
