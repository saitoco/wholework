# Issue #1064: spec: run-spec.sh --opus の effort を Opus 5 指針で再校正する

## Overview

`docs/reports/claude-opus-5-impact-strategy.md` (#1062) §8 の候補 Issue。`run-spec.sh --opus` パスのデフォルト effort (`xhigh`、#217 で Opus 4.8 の指針に基づき設定) が、Opus 5 の effort 指針 (§3.2: coding/agentic は `xhigh` から開始し、そこから下方 sweep を推奨。`low`/`medium` は想定以上に強い。`max` は極端に困難かつ latency 非感応な場合に限定) の下でも妥当かを再評価し、維持/変更の判定と根拠を `docs/tech.md` に記録する。

`--opus` は `/auto` (`run-auto-sub.sh`) が Size L の Issue に対してのみ自動付与する経路 (XL は spec 前に分割されるため実質 L 専用)。`#922` (C3) が `run-spec.sh` の **Sonnet** パスの default effort (`max`) を Sonnet 5 の下で再評価し維持と判定した際、Opus fallback の `xhigh` は「Opus 4.8 独自の (別建ての) effort calibration ガイダンスを反映したものであり、転用可能な根拠として扱わない」と明示的にスコープ外としている。本 Issue はその「スコープ外とされた側」を Opus 5 の指針の下で評価する、#922 と対称的な位置づけの Issue。

## Changed Files

- `docs/reports/opus-5-effort-recalibration-spec.md`: new file — Opus 5 指針の下での `--opus` パス effort 再評価の全分析 (Background / Evaluation Method / Analysis / Recommendations / Notes)。構成は前例 `docs/reports/sonnet-5-effort-recalibration-spec.md` (#922) に倣う
- `docs/tech.md`: § Phase-specific model and effort matrix の既存 C-series ノート群 (#921/#922/#923、直近は "Opus 5 watch items") の後に、本 Issue の判定 (維持/変更) と根拠、新規レポートへのポインタを記録するプローズノートを追加
- `docs/ja/tech.md`: [Steering Docs sync candidate / `docs/translation-workflow.md` 同期対象] 上記 `docs/tech.md` ノート追加を日本語ミラーに反映 (`docs/reports/` 自体は同期除外だが `docs/tech.md` は対象 — #921/#922/#923 と同じ扱い)
- `scripts/run-spec.sh`: **条件付き** — 判定が「変更」の場合のみ、`--opus` パスの `EFFORT="xhigh"` (17行目) を新しい値に更新。「維持」の場合は変更なし (bash 3.2+ compatible、既存構文を維持)
- `tests/run-spec.bats`: **条件付き** — 判定が「変更」の場合のみ、`@test "success: --opus default effort is xhigh"` (246-249行目) を新しい値に整合させて更新。「維持」の場合は変更なし

## Implementation Steps

1. 前例・実装再確認: `scripts/run-spec.sh` の `--opus` パス (15-18行目: `MODEL="opus"` / `EFFORT="xhigh"`) と `scripts/run-auto-sub.sh` の Size L 限定の dispatch 条件 (845行目 `if [[ "$SIZE" == "L" ]]`) が Issue 本文の記述と一致していることを確認する (spec investigation で確認済み — 差分なし)。`docs/tech.md` の "Opus 5 effort calibration" ノートおよび `docs/reports/claude-opus-5-impact-strategy.md` §3.2/§4.4 を、Opus 4.8→Opus 5 の指針差分および本 Issue の位置づけの一次情報源として確定する (→ 受入条件 3)
2. telemetry 前提の評価: Issue コメント (2026-08-06, 2026-08-07) が指摘した spec フェーズの token telemetry 欠落が `#1228` (本リポジトリに merge 済み — `run-spec.sh` が `_EMIT_PHASE_OWNED` gate 経由で自前に `wrapper_exit`/`token_usage` を emit するようになった。`run_phase_with_recovery()` への dispatch 統一は不要だった) により解消済みであることを確認する。ただし修正が直近に着地したばかりのため `--opus` の実 token サンプルは現時点で `.tmp/auto-events.jsonl` に 0 件であることを確認し、判定はしたがって (a) Opus 4.8→5 の指針差分、(b) `#922` が確立した構造的根拠 (spec は sub-agent fan-out のない単一 19 ステップ推論チェーンで、エラーは code/review/merge の 3 フェーズに伝播する)、(c) Issue コメントが提示した wall-clock 代理指標 (`sub_start size=L` で抽出した Opus 5 世代 9 件平均 16:22 分 vs Opus 4.8 世代 5 件平均 13:22 分、+22%。ただし並行セッション負荷と交絡するため一次根拠にはできない) の組み合わせに基づくことをレポートの前提として明記する。あわせて「Size L の Issue」≠「Opus 生成の Spec」である点 (`/spec` 中の M→L 昇格は Opus/Sonnet の dispatch 判定後に起こるため対象外になりうる — 実例 #1175) と、正しい抽出方法 (`sub_start` イベントの `size=L`、または wrapper ログの `Model:` 行) を記録する (after 1) (→ 受入条件 2, 3)
3. レポート新規作成: `docs/reports/opus-5-effort-recalibration-spec.md` を作成し、Background / Evaluation Method / Analysis / Recommendations / Notes を記録する。構成は `docs/reports/sonnet-5-effort-recalibration-spec.md` (#922) に倣う。Analysis には (a) Opus 4.8→Opus 5 の指針差分 (下方 sweep の推奨、low/medium の評価変化、max の位置づけ変化) を判定の前提として明記するセクション、(b) `--max` フラグの明示指定が Opus 5 の指針 ("極端に困難かつ latency 非感応な場合に限定") の下でも妥当かの検討、(c) Step 2 で確定した telemetry 前提 (基盤は解消済みだが実サンプル 0 件) を含める (after 2) (→ 受入条件 2, 3, 5)
4. `docs/tech.md` / `docs/ja/tech.md` 更新: § Phase-specific model and effort matrix の "Sonnet 5 effort recalibration — issue (#923, C4)" ノートの直後に、本 Issue の判定・根拠・新規レポートへのポインタを #921/#922/#923 と同形式のプローズノートとして追加する (C-series の verdict-record 系列を継続する位置)。同内容を `docs/ja/tech.md` の対応箇所に日本語で反映する (after 3) (→ 受入条件 4)
5. 条件付き effort/test 更新: 判定が「変更」の場合、`scripts/run-spec.sh` の `--opus` パスの `EFFORT` 値、`docs/tech.md`/`docs/ja/tech.md` の matrix 表セル (Opus 列)、`tests/run-spec.bats` の `"success: --opus default effort is xhigh"` アサーションを SSoT として同時に整合させる。判定が「維持」の場合、これら3ファイルはいずれも変更せず、レポートにその旨を明記する (after 4) (→ 受入条件 6)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/opus-5-effort-recalibration-spec.md" --> `docs/reports/opus-5-effort-recalibration-spec.md` が作成されている
- <!-- verify: rubric "docs/reports/opus-5-effort-recalibration-spec.md に run-spec.sh --opus の default effort を維持するか変更するかの明確な判定 (verdict) と、その根拠が記載されている" --> レポートに維持・変更の判定と根拠が記載されている
- <!-- verify: rubric "docs/reports/opus-5-effort-recalibration-spec.md に、Opus 4.8 と Opus 5 の effort 指針の差分 (下方 sweep の推奨、low/medium の評価変化) が判定の前提として記述されている" --> Opus 4.8 と Opus 5 の effort 指針の差分がレポートに記述されている
- <!-- verify: file_contains "docs/tech.md" "opus-5-effort-recalibration-spec.md" --> <!-- verify: rubric "docs/tech.md の Phase-specific model and effort matrix 注記群に、run-spec.sh --opus の effort 再校正の判定結果が #921 / #922 / #923 と同じ形式で追記されており、レポートへのリンクがある" --> `docs/tech.md` の matrix 注記に判定結果が先行 3 件と同形式で追記されている
- <!-- verify: rubric "レポートまたは Issue 本文に、--max フラグの位置づけが Opus 5 の下でも成立するかの検討結果が記録されている" --> `--max` フラグの位置づけの検討結果が記録されている
- <!-- verify: rubric "run-spec.sh の default effort を変更した場合は tests/run-spec.bats に対応するアサーションが存在する。変更しなかった場合はテスト変更が不要である旨がレポートに明記されている" --> effort を変更した場合はテストが追随しており、変更しない場合はその旨が明記されている

### Post-merge

- L size の Issue に対して `/auto` を実行し、`run-spec.sh --opus` が判定後の effort で起動することを確認する <!-- verify-type: opportunistic -->

## Notes

- **CI-sensitive / Size M**: `docs/tech.md` の model-effort-matrix SSoT と (条件付きで) `run-spec.sh` の実値に触れる変更のため、PR route (Size M) で実行する。
- **品質クリティカル**: spec エラーは全下流フェーズに伝播するため、`#922` と同様に慎重な判定を要する。default の機械的切替ではなく、十分な根拠を伴う判定であることを `/code` フェーズで担保する。
- **Step 7/8 (Ambiguity/Uncertainty Resolution) はスキップ**: `SPEC_DEPTH=light` のため本 spec 実行では実施しない。
- **telemetry 前提の状態 (重要)**: Issue コメント (2026-08-06, 2026-08-07) が指摘した spec フェーズの `token_usage`/`wrapper_exit` 欠落は、`#1228` (commit `edd4cc10`、本 Issue の spec 実行と同日に merge 済み) により解消されている。`#1228` のコミットメッセージ自身が "Both phases previously never emitted either event on normal exit, which blocked #1064, #939, and #1146" と明記しており、本 Issue の前提条件として直接ひもづく。ただし本 spec 実行時点で `.tmp/auto-events.jsonl` に `--opus` の `token_usage` 実サンプルは 0 件 — 修正が直近に着地したばかりのため。レポートの判定はこの「基盤は解消済みだが実測はまだない」状態を明記した上で、代替エビデンス (指針差分の定性評価 + wall-clock 代理指標 + 構造的引数) に基づいて行う。
- **wall-clock 代理指標 (Issue コメント由来、スコープ: `sub_start` イベントの `size=L` でフィルタした spec 所要時間)**: Opus 5 世代 (2026-07-24以降) 9 件平均 16:22分、Opus 4.8 世代 5 件平均 13:22分 (+22%)。同一 `xhigh` effort での比較だが、両期間とも並行セッション負荷が濃い期間と重なり交絡する (`docs/reports/external-kill-investigation.md` 参照)。判定の一次根拠にはできない参考値として扱う。
- **サンプリングの落とし穴**: 「Size L の Issue」≠「Opus 生成の Spec」。`/spec` 実行中の Size 昇格 (M→L) は Opus/Sonnet の dispatch 判定後に起こるため、L size になった Spec が必ずしも Opus 生成とは限らない (実例: #1175、triage 時 M → Sonnet で spec 開始 → Changed Files 7件で M→L 昇格)。正しい抽出は `sub_start` イベントの `size=L`、または wrapper ログの `Model:` 行を使う。
- **前例調査で確認した事実**:
  - `scripts/run-auto-sub.sh:845` の `if [[ "$SIZE" == "L" ]]` が `--opus` 付与の唯一の条件分岐であり、Issue 本文の記述と一致 (差分なし)
  - `scripts/run-spec.sh:15-18` の `--opus` 分岐 (`MODEL="opus"` / `EFFORT="xhigh"`) は `docs/tech.md` の matrix 行と一致 (差分なし)
  - `#922` は Opus fallback の `xhigh` を「Opus 4.8 独自のガイダンスを反映したもので、Sonnet パスへの転用可能な根拠として扱わない」と明示的にスコープ外とした — 本 Issue はこの「スコープ外とされた側」を Opus 5 の指針の下で初めて正式に評価する
  - `docs/reports/claude-opus-5-impact-strategy.md` §4.4 (#1062) は「`xhigh` は依然として正しい可能性があるが、選定時の根拠は Opus 5 の実際の指針と合致しなくなっているため、単純な持ち越しではなく独立した再評価が必要」と本 Issue を位置づけている — 判定の方向性を予断するものではないが、レポート作成時の出発点として記録する
- **翻訳ミラー**: `docs/translation-workflow.md` § Exclusions により `docs/reports/` は同期対象外のため、新規レポートファイルに `docs/ja/reports/` ミラーは作成しない。`docs/tech.md` に追加するノート (同期対象) のみ `docs/ja/tech.md` に反映する。
- **Pre-merge 検証項目数について**: Issue 本文の Pre-merge 受入条件が 6 件であり、SKILL.md の light テンプレート目安 (5件) を 1 件超過するが、「Verify command sync rule」(Issue body を verbatim で転記) を優先し、そのまま維持した。
- **関連**: `docs/reports/claude-opus-5-impact-strategy.md` (#1062, §3.2/§4.4/§8, 本 Issue の候補フレーミング元)、`docs/reports/sonnet-5-effort-recalibration-spec.md` (#922, C3, レポート構成の直接の前例)、Issue #217 (Opus 4.7 導入時に `xhigh` を設定、Sonnet パスは明示スコープ外)、Issue #1228 (spec/issue フェーズの telemetry 欠落を解消、本 Issue の前提条件)

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1–5 were followed as written; no reordering, omission, or approach change occurred.

### Design Gaps/Ambiguities

- `docs/ja/tech.md` was found to already be missing the three Opus 5-related prose notes that `#1062` added to `docs/tech.md` (**Opus 5 effort calibration**, **Opus 5 default parent evaluation — deferred**, **Opus 5 watch items**) — a pre-existing translation-sync gap from `#1062`, not introduced by this Issue. `bash scripts/check-translation-sync.sh` still reports `docs/tech.md` as `IN_SYNC` because the sync checker compares last-updated dates, not per-note content coverage, so it did not surface this gap. Not fixed here (out of scope for #1064's own Changed Files, and re-litigating #1062's own translation debt risks scope creep); recorded here rather than filed as a new Issue, since it is minor, non-blocking, and better tracked as a note for the next `docs/ja/tech.md` sync pass than as a standalone Issue.

### Rework

- N/A — no rework occurred.

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: spec フェーズの token telemetry が全期間で0件であることを指摘。wall-clock 代理指標 (Opus5世代 avg 16:22 vs Opus4.8世代 avg 13:22、ただし並行負荷と交絡) を提示。「L size Spec」≠「Opus 生成 Spec」の注意点 (#1175 で M→L 昇格の実例) を記録。 / URL: https://github.com/saitoco/wholework/issues/1064#issuecomment-5199646701
- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: spec phase の telemetry 欠落の原因 (run-auto-sub.sh の spec dispatch が run_phase_with_recovery() をバイパス) を特定。silent window のみ取得可能と報告。本 Issue へのスコープ算入 (a) か別 Issue 分離+blocked-by (b) の判断を提起 — 結果的に #1228 として (b) の経路で解消済み。 / URL: https://github.com/saitoco/wholework/issues/1064#issuecomment-5211841755

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 判定は「`xhigh` を維持」。#922 (Sonnet パス) の構造的論拠 (単一 19 ステップ推論チェーン、sub-agent fan-out なし、エラーは code/review/merge の 3 フェーズに伝播) をそのまま Opus パスに適用し、加えて `--opus` が Size L (最も複雑な Issue の部分集合) 限定であることを downgrade に慎重になるべき追加根拠として明記した
- Opus 5 の下方 sweep ガイダンスは (#922 の Opus 4.8 ノートと異なり) 実際にこのパスへ直接適用されるが、「sweep して確認せよ」という探索的推奨であり特定の下位 tier を支持する主張ではないため、根拠不足のまま default を変更しない、という理由付けを採用した
- `--max` フラグの位置づけは「維持」に加えて「再確認 (reaffirmed)」— Opus 5 のより狭い "extremely difficult, latency-insensitive" という定義が、既存の opt-in・都度指定という運用実態とむしろ従来以上に整合すると判定した

### Deferred Items
- 実 telemetry サンプル (`--opus` の `token_usage`) が蓄積するまでの再評価は将来Issueに委ねる。抽出時は `sub_start` イベントの dispatch 時点 `size=L` を使うこと (Spec の最終記録 Size ではない — #1175 の落とし穴に注意)
- `docs/ja/tech.md` が `#1062` の Opus 5 関連ノート (effort calibration / default parent deferred / watch items) をまだ含んでいない、という pre-existing な翻訳同期ギャップを発見したが本 Issue のスコープ外として起票せず記録に留めた (Code Retrospective参照)

### Notes for Next Phase
- Pre-merge AC 6件はすべて `/code` フェーズで検証・チェック済み (verify-executor full mode)。Post-merge AC (opportunistic, `/auto` を L size Issue に実行して `--opus` が `xhigh` で起動することを確認) は `/verify` でオープンのまま
- 判定が「維持」のため `scripts/run-spec.sh` / `tests/run-spec.bats` / matrix テーブル本体 (Model/Effort 列) はいずれも無変更。レビューではこの「無変更が正しい実装」である点を誤って diff 不足と判断しないよう注意
