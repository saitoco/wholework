# Issue #922: spec: run-spec.sh の effort 再校正 (Sonnet 5 xhigh 候補、Opus fallback 比較、C3)

## Overview

`docs/reports/claude-sonnet-5-impact-strategy.md` §8 の候補 **C3**。C1 (#914、default parent の Sonnet 5 切替) が着地したことで、フェーズ別 effort の再校正が実行可能になった。

`run-spec.sh` は現在 Sonnet パスで `--effort max` をデフォルトとしている (`docs/tech.md` § Phase-specific model and effort matrix)。§3.3 の「Sonnet 5 の `xhigh` は Opus 4.8 に迫る」という効果曲線の議論を踏まえ、Sonnet パスを `max` から `xhigh` へ引き下げられるか、および L サイズで用意されている Opus fallback (`--opus`) との比較を評価し、判定 (変更/据え置き) と根拠を `docs/tech.md` に記録する。spec フェーズは設計品質にクリティカルで誤りが全下流フェーズに伝播するため、C2 (#921, run-code.sh/run-review.sh) より慎重な評価を要する。

## Changed Files

- `docs/reports/sonnet-5-effort-recalibration-spec.md`: new file — Sonnet path (`max`→`xhigh` 候補) と Opus fallback を含む 3-way 比較の全分析 (Background / Evaluation Method / Analysis / Recommendations / Notes)。構成は前例 `docs/reports/sonnet-5-effort-recalibration-code-review.md` (#921, C2) に倣う
- `docs/tech.md`: § Phase-specific model and effort matrix の既存 "Sonnet 5 effort recalibration — code/review (#921, C2)" ノートの直後に、C3 の判定 (変更/据え置き) と根拠、新規レポートへのポインタを記録するプローズノートを追加
- `docs/ja/tech.md`: [Steering Docs sync candidate] 上記 `docs/tech.md` ノート追加を日本語ミラーに反映 (`docs/translation-workflow.md` の同期対象。`docs/reports/` 自体は同期除外だが `docs/tech.md` は対象)
- `scripts/run-spec.sh`: **条件付き** — 判定が「変更」の場合のみ、Sonnet パスのデフォルト effort 値 (12行目 `EFFORT="max"`) を更新。「据え置き」の場合は変更なし
- `tests/run-spec.bats`: **条件付き** — 判定が「変更」の場合のみ、デフォルト effort を検証するテスト (196-199行目 `@test "success: default effort is max"`) を新しい値に整合させて更新。「据え置き」の場合は変更なし

## Implementation Steps

1. 前例調査: Issue #217 (Opus パスの `max`→`xhigh` 切替時、Sonnet パスは明示的にスコープ外とされた) と Issue #229 (`docs/reports/sonnet-effort-recalibration.md`、Sonnet 4.6 時代の run-code.sh/run-review.sh 評価で run-spec.sh は明示的に除外) を確認し、Sonnet パスの `max` デフォルトが今まで一度も評価されていないことを確定する。あわせて `scripts/run-spec.sh` の実装 (`EFFORT="max"` デフォルト、`--opus`→`xhigh`、`--fable`→`high`、`--max`→`max` 上書き) が `docs/tech.md` matrix 行の記述と一致していることを再確認する (→ 受入条件 A)
2. 専用の A/B 計装が存在しないため、Auto-Resolved Ambiguity Points に記録された方針 (#877/#921 の前例に倣った代理的根拠評価) に従い、Sonnet max (現行) / Sonnet xhigh (候補) / Opus fallback (L サイズ、xhigh デフォルト・`--max` 時は max) の 3-way 比較を実施する。定性評価 (#217/#229 の論拠が spec フェーズのワークロード構造に対して Sonnet 5 世代でも成立するか) と、直近の `/spec` 実行 (PR・Issue 記録) を対象にした補足的な本番サンプル調査 (#903/#921 の手法に倣う) を組み合わせ、判定 (変更/据え置き) を導出する (after 1) (→ 受入条件 A)
3. `docs/reports/sonnet-5-effort-recalibration-spec.md` を新規作成し、Background / Evaluation Method / Analysis (Sonnet max→xhigh 検討 と Opus fallback 比較を明確に分けて記載) / Recommendations / Notes を記録する。構成・見出しは `docs/reports/sonnet-5-effort-recalibration-code-review.md` に倣う (after 2) (→ 受入条件 A)
4. `docs/tech.md` § Phase-specific model and effort matrix の "Sonnet 5 effort recalibration — code/review (#921, C2)" ノート直後に、C3 の判定・根拠・新規レポートへのポインタを記載するプローズノートを追加する。同内容を `docs/ja/tech.md` の対応箇所にも日本語で反映する (after 3) (→ 受入条件 A)
5. 判定が「変更」の場合: `scripts/run-spec.sh` の Sonnet デフォルト effort 値、`docs/tech.md`/`docs/ja/tech.md` の matrix 表セル、`tests/run-spec.bats` のデフォルト effort アサーションを SSoT として整合するよう同時に更新する。判定が「据え置き」の場合: これら3ファイルはいずれも変更しない (after 4) (→ 受入条件 B)

## Verification

### Pre-merge
- <!-- verify: rubric "run-spec.sh の effort (Sonnet max → xhigh 候補) の評価結果と、L サイズでの Opus fallback との比較を踏まえた判定 (変更/据え置き) およびその根拠が docs/tech.md § Phase-specific model and effort matrix に記録されている" --> spec effort の再校正判定 (Opus fallback 比較を含む) と根拠が docs/tech.md に記録されている
- <!-- verify: rubric "effort を変更した場合は run-spec.sh の実値と matrix 表の記述が整合している (SSoT 一致)。据え置いた場合は表に変更がない" --> 変更時は run-spec.sh と matrix 表が SSoT として一致している

### Post-merge

なし

## Notes

- **CI-sensitive / Size M**: `docs/tech.md` の model-effort-matrix SSoT と `run-spec.sh` の実値に触れる変更のため、`[[feedback_ci_sensitive_size_m]]` に従い PR route (Size M) で実行する。triage 時点でレポート §8 の Size S 見積もりから M へ override 済み (Issue Retrospective コメント参照)
- **品質クリティカル**: spec エラーは全下流フェーズに伝播するため、C2 (#921) より慎重な評価を要する。default の機械的切替ではなく、十分な根拠を伴う判定であることを `/code` フェーズで担保する
- **Step 7 (Ambiguity Resolution) はスキップ**: `SPEC_DEPTH=light` のため本 spec 実行では実施しない。Issue 本文の「Auto-Resolved Ambiguity Points」節および Issue Retrospective コメントに、`/issue` フェーズ (非対話モード) で自動解決済みの曖昧性 3 点 (A/B 評価の方法論、Opus fallback との比較範囲、「据え置き」時の記録場所) が既に記録されており、本 spec はそれをそのまま引き継ぐ
- **前例調査で確認した事実**:
  - Issue #217 (CLOSED): Opus 4.7 の `xhigh` 導入時、`run-spec.sh` の `--opus` パスのデフォルトを `max`→`xhigh` に変更。**非 Opus (Sonnet) パスは明示的にスコープ外 (現状維持)** とされた — Sonnet パスの `max` はこれまで一度も再評価されていない
  - Issue #229 (`docs/reports/sonnet-effort-recalibration.md`, Sonnet 4.6 時代): run-code.sh/run-review.sh を評価。「`run-spec.sh` (Opus / `xhigh` path) is outside this scope — see Issue #217」と明記し、run-spec.sh 自体は対象外
  - この2件により、Issue #922 は run-spec.sh の Sonnet パス effort について初めての正式な評価となる
- **verify command は rubric 単独が意図的**: Issue Retrospective コメントの監査記録の通り、判定方向 (変更/据え置き) が spec 時点で確定できないため、`section_contains`/`file_contains` などの補助チェックを追加すると「run-spec.sh」「xhigh」が既に表内 (Opus パスの記述) に存在することによる常時 PASS を招く。したがって modules/verify-patterns.md §9 の補助チェック推奨は本件では **意図的に適用しない** — Issue body の rubric 単独構成をそのまま Spec に転記する
- **翻訳ミラー**: `docs/translation-workflow.md` § Exclusions により `docs/reports/` は同期対象外のため、新規レポートファイルに `docs/ja/reports/` ミラーは作成しない。`docs/tech.md` に追加するノート (同期対象) のみ `docs/ja/tech.md` に反映する
- **関連**: `docs/reports/claude-sonnet-5-impact-strategy.md` §3.3/§4.2/§8 (候補フレーミング)、`docs/reports/sonnet-5-effort-recalibration-code-review.md` (#921, C2, レポート構成の前例)、`docs/reports/verify-sonnet-5-remeasurement.md` (#877, 代理的根拠評価の方法論の前例)、Issue #914 (C1, default parent 切替の前提条件)

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: `/issue` フェーズ (非対話モード) の Issue Retrospective — Type=Task・Size=M (CI-sensitive override) 判定、曖昧性自動解決ログ (3点)、verify command 監査 (rubric 単独が意図的である根拠)、Scope Assessment (sub-issue 分割不要) を記録。新規の指示・要求は含まれず、本 spec はその判断根拠をそのまま引き継ぐ / URL: https://github.com/saitoco/wholework/issues/922#issuecomment-4885926702

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1〜5 をそのまま実施した (前例調査 → 3-way 比較評価 → レポート新規作成 → docs/tech.md・docs/ja/tech.md へのノート追加 → 判定「据え置き」のため run-spec.sh/tests/run-spec.bats は無変更)。

### Design Gaps/Ambiguities

- Spec 段階では言及されていなかった実施細部として、本番サンプル調査 (Implementation Step 2) の母集団を「#914 (Sonnet 5 デフォルト化) 以降にコードされた Issue」に絞り込む判断を実装時に行った。#921 (C2) が採用した「Sonnet 5 リリース日 (2026-06-30) 以降にマージされた PR」という時間軸フィルタは、本リポジトリのコミット日時がすべて同日に記録される (squash 環境の制約) ため使えなかった。Issue 番号を時系列の代理指標として用いる方が本件の目的 (Sonnet 5 max 効果の実測サンプル抽出) には適切と判断した。
- AC2 の「据え置いた場合は表に変更がない」という文言は、Issue 本文の Auto-Resolved Ambiguity Points で「表セル自体は変更せず、表下の自由記述ノートとして根拠を追記する」と事前解決済みだったため、実装時に新たな曖昧さは生じなかった。

### Rework

- N/A — 手戻りは発生しなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #936 を squash merge で main へ統合。マージ前チェック (mergeable=true, reason=clean, CI=success, review=approved) はいずれも問題なし、コンフリクト解消は不要だった。
- review フェーズで確定した判定「Sonnet デフォルトパス `max` 維持」および run-spec.sh/tests/run-spec.bats 無変更の状態をそのまま維持してマージした。

### Deferred Items
- なし。

### Notes for Next Phase
- `/verify` では2件の rubric AC (判定・根拠記録が docs/tech.md にあること、SSoT 一致) を再評価する。docs/tech.md の新規ノート段落と、run-spec.sh/tests/run-spec.bats が無変更であることを確認すれば足りる (review フェーズでの確認内容と同一)。

## review retrospective

### Spec vs. implementation divergence patterns

- N/A — Implementation Steps 1〜5 は Spec 通りに実施されており、PR diff との構造的な乖離はなかった。2件の SHOULD 指摘 (後述) はいずれも Spec の設計判断そのものではなく、新規レポート内の事実記述の精度に関するものだった。

### Recurring issues

- 2件の SHOULD 指摘は根本原因が共通していた: 新規レポート (`docs/reports/sonnet-5-effort-recalibration-spec.md`) が言及する外部情報 (Issue #217 の日付、Issue #927 の Code Retrospective 完了状況) が、レポート執筆時点でのスナップショットのまま固定され、実際にマージされるまでの間に情報が古くなった、あるいは最初から未確定のまま `xx-xx` プレースホルダとして残された。本 Issue 単体では初出だが、「並行 Issue (#921/#922/#927 の C-series) の情報を横断参照するレポートは、参照先の状態が執筆後に変化しうる」という一般的なリスクパターンとして今後の類似レポート作成時に留意する価値がある。
- 実害は軽微 (判定結果には影響なし) だったが、監査品質のレポートとしての正確性を損なう type のため、今後同様のレポートを書く際は「日付/状態を含む外部参照は生成直前に再確認する」運用を徹底するとよい。

### Acceptance criteria verification difficulty

- Nothing to note — 両 AC とも rubric 単独構成 (Spec Notes に記載の通り、意図的な設計) で UNCERTAIN なく PASS 判定できた。verify command の過不足や記述不備は見られなかった。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- rubric 型 AC 2件は意味的に明確で、`/verify` が両者を UNCERTAIN なく即 PASS 判定できた。Issue 本文の Auto-Resolved Ambiguity Points (A/B 方法論・Opus fallback 比較範囲・据え置き時の記録場所) と、rubric 単独構成の意図的採用 (補助 `section_contains` は「run-spec.sh」「xhigh」が既に Opus パス記述で表内に存在するため常時 PASS を招くとして意図的に不採用) が spec Notes に明記されており、AC 検証の曖昧性を事前に排除できていた。良好。

#### design
- Spec が前例調査 (#217: Sonnet パスは Opus xhigh 導入時にスコープ外 / #229: run-spec.sh は評価対象外) で「Sonnet パス max は初評価」であることを確定させ、判定 (maintain max) の根拠構造を spec 時点で固めていた。実装は Implementation Steps 1-5 と完全一致。品質クリティカルなフェーズに対し #921 (C2) の前例を踏襲した堅実な設計。

#### code
- 手戻り・fixup/amend なし (git 履歴クリーン、squash merge 1 コミット)。
- **注目観察 (本番サンプル母集団の time-proxy 制約)**: 本番サンプル調査で #921 (C2) が用いた「Sonnet 5 リリース日以降にマージされた PR」という時間軸フィルタが、本リポジトリの squash 環境ではコミット日時が全て同日記録されるため使えず、Issue 番号を時系列の代理指標に切り替えた。これは C4 (#923) など今後の本番サンプルベース再校正でも再発する制約であり、方法論的な知見として記録に値する。

#### review
- MUST 0件、SHOULD 2件を検出・解決 (新規レポート内の外部参照の陳腐化: #217 の日付プレースホルダと #927 の Code Retrospective 完了状況)。判定結果には影響なし。review は doc-audit 品質の精度指摘を適切に機能させた。
- **注目観察 (横断参照レポートの陳腐化リスク)**: C-series (#921/#922/#927) の状態を横断参照するレポートは、参照先の状態 (日付・retrospective 完了状況) が執筆後マージ前に変化しうる。本件は軽微 (review で修正済み) だが、C4 (#923) 以降の同型レポートで再発しうる recurring パターン。

#### merge
- squash merge クリーン (`mergeable=true`/`reason=clean`、CI success・review approved)。コンフリクトなし。問題なし。

#### verify
- rubric 型 AC 2件とも初回 PASS、reopen サイクルなし。verify command 整合性: `run-spec.sh` の Sonnet デフォルト `EFFORT="max"` (line 12) が matrix 表 (Sonnet: max) と SSoT 一致し、「据え置き=表未変更」を機械照合できた。`tests/run-spec.bats` も無変更。inconsistency なし。

### Improvement Proposals
- (candidate, convention/低優先) 並行 C-series Issue (#921/#922/#923/#927) の状態を横断参照する監査品質レポートを書く際は、「日付・retrospective 完了状況などの外部参照は生成直前に再確認する」というライティング規律 (convention/lesson) を徹底する。#922 で 2件の SHOULD (陳腐化した外部参照・未確定プレースホルダ) が review で検出された recurring パターンであり、C4 (#923) 以降で再発リスクがある。構造変更ではなく convention レベルの lesson。
