# Issue #952: auto: event-based observation scan の dispatch fan-out 制御を追加

## Overview

`/auto` の Event-based observation scan (`observation-trigger.sh --event auto-run` の matched Issue に対して `Skill(wholework:verify)` を dispatch する処理) は現在、matched Issue 数の上限なく直列 dispatch する。実運用 (`/auto --batch 938 939` セッション、および先行する #897 の `/auto 955` 実行) で 17 件の matched Issue が検出され、1 session 内で 17 件の `/verify` を回すのは非現実的なため、ユーザーが AskUserQuestion で全件 skip する対応が発生した。L3 autonomy = 「無停止で全件実行」という設計意図と、実務上の compute burn 回避要求が乖離している。

本 Issue では `.wholework.yml` に `observation-dispatch-threshold` (デフォルト 5) を新設し、`skills/auto/SKILL.md` の single-issue route・batch route 双方の Event-based observation scan ステップに、この閾値による dispatch 件数キャップを追加する。閾値超過分は dispatch しないが、`observation-trigger.sh` は引き続き全 matched Issue にコメントを投稿する (既存の無条件副作用) ため通知は失われず、`opportunistic-search.sh` が次回 `auto-run` イベント発火時に未チェックの observation AC を再スキャンする既存挙動により、超過分は次回以降のスキャンで再度 dispatch 対象になる (状態を持たない rolling deferred coverage)。

採用する実装アプローチおよび他アプローチを採用しなかった判断根拠は本 Spec の `## Notes` に記録する (Issue 本文の retrospective コメントにより、具体的アプローチの選定は `/spec` の責任範囲と明示されている)。

## Changed Files

- `modules/detect-config-markers.md`: `observation-dispatch-threshold` → `OBSERVATION_DISPATCH_THRESHOLD` (デフォルト `5`) の config marker を追加 (Marker Definition Table 行、YAML Parsing Rules 箇条書き、Output Format 行の3箇所)
- `docs/guide/customization.md`: Available Keys テーブルに `observation-dispatch-threshold` の行を追加 (config SSoT)
- `docs/ja/guide/customization.md`: 上記行を日本語で同期 (`docs/translation-workflow.md` の同期義務)
- `skills/auto/SKILL.md`: "Event-based observation scan (auto-run event, ...)" (single-issue route) と "Event-based observation scan (batch, best-effort)" (batch route) の2箇所に `OBSERVATION_DISPATCH_THRESHOLD` によるキャップ処理を追加
- `modules/observation-trigger.md`: `## scripts/observation-trigger.sh` セクションの "Who invokes `/verify`" 記述にキャップ挙動と採用根拠を追記 (実装と SSoT ドキュメントの一致)

## Implementation Steps

1. `modules/detect-config-markers.md`: 以下3箇所を追加する (→ 受入条件 C)
   - Marker Definition Table に行を追加 (`patch-lock-timeout` 行の直後など、他の integer 系キーと同じ並びの位置):
     ```
     | `observation-dispatch-threshold` | `OBSERVATION_DISPATCH_THRESHOLD` | Integer string (extract as-is; use `5` if ≤0 or non-numeric) | `5` |
     ```
   - YAML Parsing Rules の箇条書きに追加 (`verify-max-iterations` の箇条書きの近く):
     `observation-dispatch-threshold` is treated as an integer: extract the numeric string; if the value is ≤0 or non-numeric, fall back to the default `5`
   - Output Format のコードブロックに追加:
     `OBSERVATION_DISPATCH_THRESHOLD: integer from observation-dispatch-threshold (default: "5"; falls back to "5" if ≤0 or non-numeric)`

2. `docs/guide/customization.md` (after 1): Available Keys テーブルの `auto-max-concurrent` 行の直後に以下の行を追加する (→ 受入条件 C):
   ```
   | `observation-dispatch-threshold` | integer | `5` | Maximum number of Issues to dispatch `/verify` for per `/auto` Event-based observation scan run (single-issue and batch routes; `event=auto-run` only). Matched Issues beyond the cap remain comment-notified (existing `observation-trigger.sh` behavior, unconditional) and are re-evaluated on the next `auto-run` event scan. Values ≤0 or non-numeric fall back to `5`. |
   ```

3. `docs/ja/guide/customization.md` (after 2): 対応するテーブルの同じ位置に日本語で同期する (`docs/translation-workflow.md` の Sync Procedure に従う。コードフェンス数が一致することを確認する)。

4. `skills/auto/SKILL.md` (after 1, parallel with 2, 3): 以下2箇所を書き換える (→ 受入条件 A)
   - **single-issue route**: 見出し "Event-based observation scan (auto-run event, runs after Completion Report regardless of success/failure)" 配下の段落・箇条書きを次のように置き換える。

     現状:
     ```
     If `OBSERVATION_MATCHES` is non-empty, read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section to load `AUTONOMY_TIER`, then apply tier-aware dispatch:
     - **L1**: skip dispatch (advisory-only — the comment already posted by `observation-trigger.sh` is the only action)
     - **L2 / L3**: for each number in `OBSERVATION_MATCHES` other than `$NUMBER` (the Issue this `/auto` run just processed), dispatch `Skill(skill="wholework:verify", args="$N")` sequentially
     ```

     置き換え後:
     ```
     If `OBSERVATION_MATCHES` is non-empty, read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section to load `AUTONOMY_TIER` and `OBSERVATION_DISPATCH_THRESHOLD`, then apply tier-aware dispatch:
     - **L1**: skip dispatch (advisory-only — the comment already posted by `observation-trigger.sh` is the only action)
     - **L2 / L3**: exclude `$NUMBER` (the Issue this `/auto` run just processed) from `OBSERVATION_MATCHES`. From the remaining numbers (already ascending-sorted by `observation-trigger.sh`, i.e. oldest-pending Issue first), take at most the first `OBSERVATION_DISPATCH_THRESHOLD` and dispatch `Skill(skill="wholework:verify", args="$N")` sequentially for each. Numbers beyond the cap are not dispatched this run — `observation-trigger.sh` has already posted its notification comment to every matched Issue regardless of the cap, and the deferred Issues are re-matched on the next `auto-run` event scan. When at least one number was deferred, output "Observation dispatch capped at OBSERVATION_DISPATCH_THRESHOLD; deferred K of M matched Issue(s) to the next auto-run scan." (K = deferred count, M = total remaining after excluding `$NUMBER`).
     ```

   - **batch route**: 見出し "Event-based observation scan (batch, best-effort)" 配下の段落・箇条書きを次のように置き換える。

     現状:
     ```
     If `OBSERVATION_MATCHES` is non-empty, read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section to load `AUTONOMY_TIER`, then apply tier-aware dispatch:
     - **L1**: skip dispatch (advisory-only — the comment already posted by `observation-trigger.sh` is the only action)
     - **L2 / L3**: for each number in `OBSERVATION_MATCHES` not already included in `BATCH_LIST` (Issues already processed by this batch), dispatch `Skill(skill="wholework:verify", args="$N")` sequentially
     ```

     置き換え後:
     ```
     If `OBSERVATION_MATCHES` is non-empty, read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section to load `AUTONOMY_TIER` and `OBSERVATION_DISPATCH_THRESHOLD`, then apply tier-aware dispatch:
     - **L1**: skip dispatch (advisory-only — the comment already posted by `observation-trigger.sh` is the only action)
     - **L2 / L3**: exclude numbers already included in `BATCH_LIST` (Issues already processed by this batch) from `OBSERVATION_MATCHES`. From the remaining numbers (already ascending-sorted by `observation-trigger.sh`, i.e. oldest-pending Issue first), take at most the first `OBSERVATION_DISPATCH_THRESHOLD` and dispatch `Skill(skill="wholework:verify", args="$N")` sequentially for each. Numbers beyond the cap are not dispatched this run — `observation-trigger.sh` has already posted its notification comment to every matched Issue regardless of the cap, and the deferred Issues are re-matched on the next `auto-run` event scan. When at least one number was deferred, output "Observation dispatch capped at OBSERVATION_DISPATCH_THRESHOLD; deferred K of M matched Issue(s) to the next auto-run scan." (K = deferred count, M = total remaining after excluding `BATCH_LIST`).
     ```

   - 既存の Resume mode (`BATCH_LIST`/`REMAINING` 再利用に関する既知の CONSIDER 事項、#897 review retrospective 記載) には手を入れない (スコープ外)。

5. `modules/observation-trigger.md` (after 4): `## scripts/observation-trigger.sh` セクションの "**Who invokes `/verify`**" 箇条書きの、"**LLM-session emitters**" 項目の直後 ("**`scripts/claude-watchdog.sh`**" 項目の直前) に以下のサブ箇条書きを追加する (→ 受入条件 B):
   ```
     - **`/auto` dispatch cap (#952)**: `/auto`'s single-issue and batch Event-based observation
       scan steps additionally cap active dispatch to the first `OBSERVATION_DISPATCH_THRESHOLD`
       matched numbers per run (`observation-dispatch-threshold` in `.wholework.yml`, default `5`;
       see `modules/detect-config-markers.md`). `observation-trigger.sh`'s stdout is already
       ascending-sorted by Issue number (`sort -un`), so the cap naturally prioritizes the
       longest-waiting Issue first. Numbers beyond the cap are not lost: the notification comment
       above is posted to every matched Issue unconditionally regardless of the cap, and because
       `opportunistic-search.sh` re-scans all unchecked `event=auto-run` observation ACs on every
       invocation with no already-notified state, deferred Issues are re-matched (and re-attempted,
       cap permitting) on the next `auto-run` event — a stateless, rolling form of deferred coverage.
       `/review`'s Event-based observation scan (`event=pr-review-full`/`pr-review-light`) is not
       capped: it is a structurally separate emitter/event population with no `--batch`-style volume
       multiplier and no evidence of the same fan-out pattern.
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md § Event-based observation scan または関連 scripts に、dispatch fan-out 制御 (threshold / deferred / priority / parallel のいずれか) が実装されている" --> auto SKILL に fan-out 制御が実装されている
- <!-- verify: rubric "実装アプローチ (a)-(d) のうちどれを採用したか、および他を採用しなかった場合の判断根拠が記録されている" --> 採用アプローチと判断根拠が記録されている
- <!-- verify: rubric ".wholework.yml に閾値等の config 追加を行った場合、docs/guide/customization.md (該当ガイド) と modules/detect-config-markers.md の Marker Definition Table が更新されている; config 追加なしの場合はその判断が Spec に記録されている" --> config 変更の場合は SSoT が更新されている

### Post-merge

- 次回 `/auto --batch` の event-based observation scan で dispatch 数が 10 件超になった際、fan-out 制御が発火し compute burn が回避されることを観察

## Notes

- **採用アプローチ: (c) priority-based cap**。`observation-dispatch-threshold` (デフォルト `5`、Issue 本文の提示値をそのまま採用) による per-run dispatch 件数キャップを `/auto` の single-issue route・batch route 双方に適用する。「優先度」は `observation-trigger.sh` の stdout が既に `sort -un` で昇順ソート済み (= 最も長く待たされている Issue が先頭) であることをそのまま利用し、追加のスクリプト変更は不要とした。
- **(a) threshold-based user confirmation を採用しなかった理由**: `modules/autonomy-tier.md` は L3 を「Fully unattended」と明確に定義しており、`/auto --batch` は本 Spec 自身の `--non-interactive` 実行例が示す通り AskUserQuestion を使えない headless context でも実行される。confirmation gate は人間が偶然立ち会っている interactive session でのみ機能し、fan-out リスクが最も高い無人実行時にこそ無力化される構造的欠陥がある。Issue の起点となった AskUserQuestion による override も、たまたま interactive な親セッションだったため可能だった一回性の対応であり、恒常的な解決にならない。
- **(b) `.tmp/pending-observations.json` のような新規永続キューを採用しなかった理由**: 冗長なため。`opportunistic-search.sh` は `event=auto-run` の未チェック observation AC を毎回全件 re-scan しており、dispatch 済みかどうかの状態を一切保持しない。そのため今回 dispatch しなかった Issue は次回の `auto-run` イベント発火時に自動的に再マッチする。GitHub Issue の AC 状態と `observation-trigger.sh` の無条件コメント投稿が既に "deferred queue" として機能しており、別ファイルでの状態永続化は屋上屋。採用したキャップは、この既存の re-scan 挙動を利用した状態を持たない (b) の簡易版と言える。
- **(d) parallel dispatch を採用しなかった理由**: wall-clock 短縮にはなるが total compute cost は変わらず、Issue の目的である「compute burn の回避」に直接寄与しない。Issue 本文も `/verify` 内部での `/code` auto-retry と nested になるリスクを明示しており、優先度は低いと判断した。将来的に (c) と組み合わせる余地はあるが、本 Issue のスコープでは採用しない。
- **`/review` の Event-based observation scan (`skills/review/SKILL.md`) は対象外**: `/review` は `event=pr-review-full`/`pr-review-light` という `auto-run` とは別系統のイベントを発火し、PR 1件につき1回しか実行されないため `--batch` のような件数増幅要因がない。Issue 本文の Background は "`skills/auto/SKILL.md` § Batch Completion Report" に明示的にスコープしており、Acceptance Criteria も「auto SKILL」と限定して記述している。同種の暴走が実際に観測された記録もないため、本 Issue では変更しない。
- **`docs/tech.md` の Architecture Decisions は更新しない**: 同種の数値上限キー (`auto-max-concurrent`、`recoveries-auto-fire.threshold`) も `docs/guide/customization.md` の Available Keys テーブルにのみ記載され `tech.md` には個別記載がない。また `tech.md` は Event-based observation scan の仕組み自体を現状記述しておらず (`modules/observation-trigger.md` に完全に委譲済み、Shared module pattern に合致)、この前例を踏襲し `tech.md` は変更しない。
- **`skills/auto/SKILL.md` に追加する新規ステータス行の言語**: このセクション・ファイル全体の既存のターミナル出力文言 (例: "No issues pending manual confirmation.") が一貫して英語であるため、新規追加する "Observation dispatch capped..." 行も同じファイル内の既存規約に合わせて英語とした。
- **#897 との関係**: `#897` の Spec (`docs/spec/issue-897-observation-dispatch.md`) は「明示的な数値上限は採用しない、運用実績で問題が確認された場合は follow-up Issue で検討する」と明記していた。実際に 17 件の fan-out が2回 (先行する `/auto 955`、および本 Issue の起点となった `/auto --batch 938 939`) 観測されたため、本 Issue がその follow-up にあたる。
- コードベース調査の結果、Issue 本文の技術的記述 (`skills/auto/SKILL.md` の該当箇所の引用、`observation-trigger.sh` の挙動) と実装との間に相違点は見つからなかった。
- **Steering Docs sync candidate 確認**: `docs/workflow.md` の `/audit auto-session` 説明 (176行目付近) に "observation-dispatch `/verify` re-run" という記述があるが、これは dispatch された Issue のカウント方法に関する記述であり、今回のキャップ導入によって dispatch 対象になった Issue のカウント方法自体は変わらない (dispatch されなかった run ではカウントされないだけ) ため、更新不要と判断した。`docs/tech.md`・`docs/guide/autonomy.md` にも `observation-dispatch-threshold`/`OBSERVATION_MATCHES`/`Event-based observation scan` への言及はなく、他に sync 候補はなかった。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective コメント (typo 修正: Post-merge AC の `<!-- verify-type: opportunistic -->` が `<|--` という誤記になっていたのを修正。あわせて、実装アプローチ (a)-(d) のどれを採用するかは `docs/product.md` § "`/issue` (What) vs `/spec` (How) Responsibility Boundary" に従い `/issue` レベルでは解決せず `/spec` の設計判断に委ねる、という方針を明示。本 Spec の `## Notes` における採用アプローチ選定はこの方針に基づく) / https://github.com/saitoco/wholework/issues/952#issuecomment-5173461388

## Code Retrospective

### Deviations from Design
- N/A (Spec の Implementation Steps 1-5 を順序・内容ともにそのまま実装した)

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note. `review-light` の Perspective 1 (Spec Deviation) 精査の結果、Spec Implementation Steps 1-5 と PR diff は行単位で一致しており、構造的な乖離は見つからなかった。

### Recurring issues

Nothing to note. 同種の issue (severity MUST/SHOULD) の重複は観測されなかった。CONSIDER 2件 (yaml サンプル前例の選定、ステータスメッセージの `$` プレフィックス慣例) はいずれも単発のスタイル上の指摘であり、過去の `/review` で繰り返し指摘されているパターンとは合致しない。

### Acceptance criteria verification difficulty

Nothing to note。3件の pre-merge rubric AC はいずれも Spec `## Notes` に採用アプローチ・不採用理由・config 変更判断が明記されており、UNCERTAIN 判定は発生しなかった。verify command の欠落や不正確さも見当たらない。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash merge を conflict なしで実行 (`mergeable=true`, `reason=clean`, CI 全項目 SUCCESS, review approved のため Step 3 の Resolve Conflicts はスキップ)。
- pre-merge AC ゲートは 3件全て `[x]` 済みで `unchecked_count=0` を確認、override なしで通過。

### Deferred Items
- Post-merge AC (`verify-type: opportunistic`): 次回 `/auto --batch` の event-based observation scan で dispatch 数が 10 件超になった際にキャップが発火し compute burn が回避されることの観察は、実運用発生を待つ必要があるため `/verify` 以降に委ねる (review フェーズの Deferred Items を引き継ぎ)。
- CONSIDER 2件 (docs/guide/customization.md yaml サンプル前例、skills/auto/SKILL.md の `$` プレフィックス表記) は未修正のまま。将来同種の指摘が積み重なった場合のみ対応を検討。

### Notes for Next Phase
- `/verify 952` で post-merge AC (opportunistic) の観察待ちとなる。実運用で dispatch 数が閾値超過する事例が発生した際に検証すること。
- Issue #952 は `closes #952` により squash merge 時に自動クローズ済み (base branch は `main`)。
