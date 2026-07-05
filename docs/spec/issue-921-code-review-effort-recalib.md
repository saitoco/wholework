# Issue #921: code/review: run-code.sh / run-review.sh の effort 再校正 (Sonnet 5 medium 候補の A/B 評価、C2)

## Consumed Comments

- saito / MEMBER / first-class / `/issue` (トリアージ) フェーズの Issue Retrospective — Type=Task・Size=M (`[[feedback_ci_sensitive_size_m]]` 準拠の CI-sensitive 昇格)・Value=3 の判定根拠、および Auto-Resolved Ambiguity Points (記録フォーマット・A/B 評価手法) の判断根拠を確認。AC 文言への影響なし、新規アクションなし / https://github.com/saitoco/wholework/issues/921#issuecomment-4885048037

## Overview

`docs/reports/claude-sonnet-5-impact-strategy.md` §8 の候補 Issue **C2**。C1 (#914、default parent の Sonnet 5 切替) が着地し、同レポート §3.3 の effort curve widening (Sonnet 5 では `medium` がより広いタスクで `high` 相当の費用対効果を出す) を踏まえた phase-specific effort 再評価が実行可能になった。

対象は `docs/tech.md` § Phase-specific model and effort matrix で現在 `high` 固定の `run-code.sh` (code phase) / `run-review.sh` (review phase)。定量 A/B ベンチマーク基盤が未整備のため、Issue 本文の Auto-Resolved Ambiguity Points に従い、(a) `#229` (`docs/reports/sonnet-effort-recalibration.md`、2026-04-18、Sonnet 4.6 ベースラインで同じ2スクリプトを評価済み) を Sonnet 5 の観点から再評価する定性分析、(b) `#903` 方式 (`docs/reports/sonnet-5-watchdog-recalibration.md`) の実運用サンプル計測、を組み合わせて判定する。同一タスクの medium/high 二重実行比較までは要求しない。

本 Spec 作成時点の調査 (Explore sub-agent によるコードベース検証込み) で両スクリプトとも **`high` 維持**の判定に至った。詳細な根拠は本 Spec の `## Notes` に記録し、実装フェーズでは専用レポート (`docs/reports/sonnet-5-effort-recalibration-code-review.md`) の新規作成と `docs/tech.md`/`docs/ja/tech.md` への判定サマリ note 追記のみを行う (`run-*.sh` 本体・matrix 表本体・エージェント frontmatter の変更は伴わない)。

## Changed Files

- `docs/reports/sonnet-5-effort-recalibration-code-review.md`: new file — `run-code.sh` / `run-review.sh` の Sonnet 5 effort 再評価 (評価方法・両スクリプトの判定根拠・実運用サンプル・`#229` との関係を記録)
- `docs/tech.md`: change — § Phase-specific model and effort matrix の "code-side auto-retry" bullet (`## Wholework Label Management` 見出しの直前) の直後に、本 Issue (#921, C2) の判定サマリ note を追記
- `docs/ja/tech.md`: change — 上記 note の日本語ミラー同期 (`docs/translation-workflow.md` Sync Procedure 準拠。対応箇所は "code フェーズ自動リトライ (silent no-op)" bullet の直後)

## Implementation Steps

1. `docs/reports/sonnet-5-effort-recalibration-code-review.md` を新規作成する。`## Notes` の「レポート構成」「判定根拠」「実運用サンプル」の内容に従い、Background / Evaluation Method / run-code.sh 分析 / run-review.sh 分析 / Production Evidence / Recommendations / Notes の構成で両スクリプトの判定 (「maintain high」) と根拠を記録する (→ acceptance criteria 1)
2. `docs/tech.md` § Phase-specific model and effort matrix の "code-side auto-retry" bullet の直後 (`## Wholework Label Management` 見出しの直前) に、`## Notes` に記載した英語 note 文言を追記する (after 1) (→ acceptance criteria 1, 2)
3. Step 2 の note を `docs/ja/tech.md` の対応箇所 ("code フェーズ自動リトライ (silent no-op)" bullet の直後) に、`## Notes` に記載した日本語訳文言で同期する (after 2) (→ acceptance criteria 1)

## Verification

### Pre-merge

- <!-- verify: rubric "run-code.sh / run-review.sh の effort を medium 候補で A/B 評価した結果 (変更/据え置きの判定とその根拠) が docs/tech.md § Phase-specific model and effort matrix に記録されている" --> 両フェーズの effort 再校正判定と根拠が docs/tech.md に記録されている
- <!-- verify: rubric "effort を変更した場合は run-*.sh の実値と matrix 表の記述が整合している (SSoT 一致)。据え置いた場合は表に変更がない" --> 変更時は run-*.sh と matrix 表が SSoT として一致している

### Post-merge

なし

## Notes

### 判定サマリ

| Script | 現行 | 判定 | 決め手 |
|--------|------|------|--------|
| `run-code.sh` | `high` | **維持** | #229 の手戻りリスク論拠がモデル世代交代で変化しない。impact strategy レポートの `medium` 候補づけは XS/S patch-route Issue 限定 (§4.2) だが `--effort` フラグは Issue サイズ非依存のグローバル設定であり、L/XL 領域にも一律適用されてしまう |
| `run-review.sh` | `high` | **維持** | orchestrator 自身が dispatch 以外に実質的な推論作業 (レビューコメント解決の fix コミット作成) を行っており「mechanical」という impact strategy レポートの前提と矛盾する。加えて `review-bug`/`review-spec` (Opus) が orchestrator から effort を継承しており (下記「sub-agent effort 継承の検証」参照)、降格時にこれらの精度が暗黙に低下する |

両判定とも `docs/reports/sonnet-effort-recalibration.md` (#229、2026-04-18、Sonnet 4.6 ベースライン評価) の結論を再確認する形になる。Sonnet 5 の effort curve widening (impact strategy レポート §3.3) は、いずれの判定も変えるに至らなかった — 高 effort を要する理由が「モデル世代」ではなく「ワークロードの構造的性質」(code: 多段推論チェーンと手戻りコスト、review: sub-agent 継承制約と orchestrator 自身の fix 生成作業) にあるため。

### run-code.sh 分析

`skills/code/SKILL.md` は sub-agent を一切スポーンしない単一エージェント構成 (grep 確認済み)。worktree entry → spec/uncertainty 解決 → steering doc 参照 → 実装 → テスト実行 → verify command 整合性チェック → commit/PR 作成 → retrospective という14ステップの多段推論チェーンを1エージェントが担う。#229 はこの構造を根拠に「浅い推論は後工程での手戻りを誘発し、`high` の方が総所要時間を抑える」と判定した。

Sonnet 5 の effort curve widening は「深い推論を要さないタスク」で `medium` が有利になるという主旨 (impact strategy レポート §3.3) だが、同レポート自身が run-code.sh の `medium` 候補づけを「XS/S patch-route Issue」に限定している (§4.2)。しかし `run-code.sh` の `--effort` フラグは単一のグローバル設定であり、Issue サイズによる条件分岐機構は現状存在しない。グローバルに `medium` へ落とすと、#229 の手戻りリスク論拠が構造的に変わらない L/XL 領域の実装作業にも一律適用されてしまう。サイズ条件付き effort 切替は `--effort=` フラグ露出 (impact strategy レポート §8 C5、Icebox 候補、§5.5) という別のより大きな機能であり、本 Issue の二択判定のスコープ外。

### run-review.sh 分析

`skills/review/SKILL.md` の orchestrator は `review-spec` / `review-bug` (×2、いずれも `model: opus`) を `Task(subagent_type=..., ...)` でスポーンする (Step 10.2)。加えて `review-bug` の findings に対する 2 段階検証用の `general-purpose` sub-agent (Step 10.3) も同様にスポーンする。**いずれの呼び出しにも `effort` パラメータは指定されていない** (`Task(subagent_type=..., description=..., prompt=...)` のみ)。

**sub-agent effort 継承の検証 (Explore sub-agent によるコードベース + Claude Code CLI changelog 調査)**:
- `agents/review-bug.md` / `agents/review-spec.md` / `agents/review-light.md` の frontmatter は `model:` のみを設定し、`effort:` フィールドは一切設定していない (grep 確認済み、3ファイルとも)
- Claude Code CLI changelog (v2.1.198): "Subagents and context compaction now inherit the session's extended thinking configuration" — sub-agent がセッションの effort 設定を継承することは実際の CLI 挙動として確認できる
- **重要な追加発見**: CLI は v2.1.78 (skill 拡張は v2.1.80) で **agent frontmatter に `effort:` フィールドを設定するオーバーライド機構をサポート済み** (`model:` オーバーライドと並行する機構)。つまり `run-review.sh` の effort と `review-bug`/`review-spec` の effort を切り離すこと自体は技術的に可能だが、本リポジトリでは現状未採用 (`scripts/validate-skill-syntax.py` の `KNOWN_FIELDS` にも `effort` は含まれていない。ただし未知フィールドは warning のみでハードブロックではない)
- したがって「sub-agent は orchestrator の effort を継承する」という #229 の主張自体は本リポジトリの現状構成において技術的に正しいが、「変更不可能な制約」ではなく「現状のポリシー選択」である

**orchestrator 自身の推論深度について**: impact strategy レポート §4.2 は "review orchestration は mechanical (深い分析は sub-agent が担う)" と位置づけているが、この前提は不正確である。`skills/review/SKILL.md` の Non-Interactive Mode Behavior には Step 7.2/7.4/7.6 (Copilot / Claude Code Review / CodeRabbit の指摘解決) で「model judgment によりレビューコメントの意図に最も合致する修正を適用する」とあり、これは外部レビューフィードバックを解釈して実際に fix コミットを作成する作業である。これは `run-code.sh` 自身の実装推論と同種の作業であり、dispatch・集約・コメント投稿のような純粋に mechanical な処理ではない。

以上2点 (sub-agent 継承の未デカップリング、orchestrator 自身の fix 生成推論) から、`run-review.sh` は `high` 維持と判定する。

**フォローアップ (本 Issue では未実装、スコープ外)**: 将来 `run-review.sh` の effort 引き下げを再検討する場合、まず `agents/review-bug.md` / `agents/review-spec.md` に明示的な `effort: high` frontmatter を追加し、orchestrator の設定から Opus sub-agent の精度を切り離すことを前提条件とすることを推奨する。これは本 Issue の AC (docs/tech.md 記録、run-*.sh/matrix の SSoT 一致) のスコープを超える変更のため、実装しない。個別に判断すべき別 Issue として扱う (impact strategy レポート §4.3/Non-goals の "any future swap is a separate, individually-judged Issue" と同じ規律)。

### 実運用サンプル (Production Evidence、補助的・厳密な A/B ではない)

Auto-Resolved Ambiguity Points により厳密な同一タスク medium/high 二重実行比較は要求されていないため、`#903` (`docs/reports/sonnet-5-watchdog-recalibration.md`) と同様の「実測可能な範囲」のサンプル確認を補助的に実施した:

- **Scope**: 2026-06-30 (Sonnet 5 リリース) 以降にマージされた PR 15件 (`gh pr list --state merged --limit 15`)。うち8件を `gh pr view --json comments` でレビューコメント内容を抽出しスポットチェック
- **所見**: PR #901 — MUST 1件 (フォローアップ修正コミットを要した)。PR #907 — SHOULD 1件。PR #905 — "MUST issue なし" の明示的な pass 記録。残り5件のサンプルでは抽出テキスト中に MUST/SHOULD マーカーなし
- **読み方**: これは "シグナルの存在" 確認に留まり、effort 必要性の定量測定ではない。ただし Sonnet 5 リリース後も review が実際に actionable な指摘を継続して検出しているという事実は、「現行の reasoning depth に大きな余剰マージンがある」という仮説とは整合しない
- **補足**: 同じ時期の code/review wall-clock 実測は `#903` が既に取得済み (code: median 1168.5s = 旧タイムアウト3600秒の32.5%、review: median 1004s = 旧タイムアウト2000秒の50.2%)。非自明な所要時間であり、実質的な推論作業が行われていることと整合する

### docs/tech.md に追記する note (英語、Step 2 で使用)

"code-side auto-retry" bullet の直後に以下を追記する:

> - **Sonnet 5 effort recalibration — code/review (#921, C2)**: re-evaluated whether `run-code.sh`/`run-review.sh` effort could drop from `high` to `medium` under Sonnet 5's widened effort curve (impact strategy report §3.3/§4.2). **Verdict: maintain `high` for both** (full analysis: `docs/reports/sonnet-5-effort-recalibration-code-review.md`). `run-code.sh`: the impact report scoped `medium` candidacy to XS/S patch-route Issues only (§4.2), but the `--effort` flag is a single global setting with no Issue-size conditioning, and #229's rework-risk rationale (14-step reasoning chain, no sub-agent fan-out) is unchanged by the model swap. `run-review.sh`: the orchestrator performs real reasoning work beyond dispatch — Steps 7.2/7.4/7.6 interpret external review feedback and author fix commits, work comparable in kind to `run-code.sh`'s own implementation reasoning — contradicting the impact report's "mechanical" framing; additionally, `review-bug`/`review-spec` (Opus) inherit effort from the orchestrator session (confirmed via the Claude Code CLI changelog: subagents inherit the session's extended-thinking/effort configuration unless an agent-level `effort:` frontmatter override is set, which `agents/review-bug.md`/`review-spec.md` do not currently set), so a downgrade would silently reduce their accuracy-critical reasoning depth too. Both verdicts reconfirm `docs/reports/sonnet-effort-recalibration.md` (#229, 2026-04-18, Sonnet 4.6 baseline) under the Sonnet 5 lens. **Follow-up (not implemented here)**: if a future Issue revisits `run-review.sh`'s effort, first add explicit `effort: high` frontmatter to `agents/review-bug.md`/`review-spec.md` to decouple their accuracy from the orchestrator's setting (the CLI supports per-agent `effort:` override; unadopted in this repo today).

### docs/ja/tech.md に追記する note (日本語、Step 3 で使用)

"code フェーズ自動リトライ (silent no-op)" bullet の直後に以下を追記する:

> - **Sonnet 5 effort 再校正 — code/review (#921, C2)**: Sonnet 5 の effort curve widening (impact strategy レポート §3.3/§4.2) を踏まえ、`run-code.sh`/`run-review.sh` の effort を `high` から `medium` に下げられるか再評価した。**判定: 両方とも `high` を維持**（詳細分析: `docs/reports/sonnet-5-effort-recalibration-code-review.md`）。`run-code.sh`: impact strategy レポートが `medium` 候補として挙げていたのは XS/S patch-route Issue に限定されていた (§4.2) が、`--effort` フラグは Issue サイズによる条件分岐のないグローバル設定であり、#229 の手戻りリスクの論拠 (14 ステップの推論チェーン、sub-agent への fan-out なし) はモデル世代交代によって変化しない。`run-review.sh`: orchestrator は dispatch 以外にも実質的な推論作業を行っている — Step 7.2/7.4/7.6 は外部レビューのフィードバックを解釈して fix コミットを作成しており、`run-code.sh` 自身の実装推論と同種の作業である — これは impact strategy レポートの「mechanical」という位置づけと矛盾する。加えて `review-bug`/`review-spec` (Opus) は orchestrator セッションから effort を継承する (Claude Code CLI changelog で確認: エージェントレベルの `effort:` frontmatter override が未設定の場合、sub-agent はセッションの extended-thinking/effort 設定を継承する。`agents/review-bug.md`/`review-spec.md` には現状この override が設定されていない) ため、降格すると精度が重要なこれらの sub-agent の推論深度も暗黙に低下する。両判定は `docs/reports/sonnet-effort-recalibration.md` (#229、2026-04-18、Sonnet 4.6 ベースライン) を Sonnet 5 の観点から再確認するものである。**フォローアップ (本 Issue では未実装)**: 将来 `run-review.sh` の effort を再検討する場合、先に `agents/review-bug.md`/`review-spec.md` に明示的な `effort: high` frontmatter を追加し、orchestrator の設定から精度を切り離すことを推奨する (CLI は per-agent の `effort:` override をサポート済みだが、本リポジトリでは未採用)。

### スコープ外

- `run-spec.sh` (C3)・`run-issue.sh` (C4): impact strategy レポート §8 の別候補 Issue
- `--effort=` フラグ露出によるサイズ条件付き effort tiering (C5): Icebox 候補 (§5.5)、本 Issue の二択判定とは別スコープ
- `agents/review-bug.md`/`agents/review-spec.md` への `effort:` frontmatter 追加: 上記フォローアップとして記録するのみで、本 Issue の Changed Files には含めない (AC のスコープ外)

### 関連 bats

判定が「両方とも維持」(`run-*.sh` の実値変更なし) のため、`tests/run-code.bats` / `tests/run-review.bats` の更新は不要。両ファイルとも現状 `--effort` 値自体を検証するアサーションを持たない (grep 確認済み: `--model` フラグの捕捉のみ)。

### docs/ja/reports/ ミラー

`docs/translation-workflow.md` § Exclusions により `docs/reports/` は翻訳同期対象外。新規レポート `docs/reports/sonnet-5-effort-recalibration-code-review.md` に ja ミラーは作成しない (`#229`/`#903` の既存レポートも ja ミラーなしで前例と整合)。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-3 を順序通りに実施し、Spec `## Notes` に記載済みの分析・判定文言をそのまま使用した。

### Design Gaps/Ambiguities
- `/code` Step 3 の `phase/ready` ラベルチェック時点で、Issue #921 は既に `phase/code` に遷移済みだった (GitHub timeline 確認: `phase/ready` 付与 06:28:17 → `phase/code` 遷移 06:33:42、いずれも本 Issue の作業当日)。ワークツリーや PR は存在せず、実装コミットも無かったため、以前の `/code` 実行が Step 4 (ラベル遷移) 到達後・実装着手前に中断したものと判断し、既存の完成済み Spec をそのまま正として実装を継続した。`reconcile-phase-state.sh --check-precondition` は `matches_expected: false` を返したが、Spec が存在し内容も完結していたため、非対話モードの auto-resolve 方針 (Spec 不在時のみ Issue 本文から読み取る) とは別扱いとして「既存 Spec を正として続行」を選択した。

### Rework
- N/A — 手戻りは発生しなかった。

## review retrospective

### Spec vs. implementation divergence patterns
- Nothing to note — 実装 (`docs/tech.md`/`docs/ja/tech.md` note 追記 + 新規レポート) は Spec の Implementation Steps 1-3 と完全に一致していた。

### Recurring issues
- Nothing to note — レビューで検出された issue はゼロ (MUST/SHOULD/CONSIDER いずれもなし)。

### Acceptance criteria verification difficulty
- Nothing to note — rubric 型 AC 2件はいずれも意味的に明確で、UNCERTAIN なく即座に PASS 判定できた。`docs/tech.md` の該当 note と `run-code.sh`/`run-review.sh` の実値 (`--effort high` 変更なし) を直接照合するだけで検証が完結し、rubric grader 呼び出しに追加の曖昧性は生じなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #925 は `mergeable=true`/`reason=clean` (CI success、review approved) だったため worktree entry / conflict resolution はスキップし、squash merge を直接実行した。
- ローカル main を `origin/main` に ff-only で追従させ、squash 後の main 上の Spec ファイルに対して Phase Handoff の rotation (review → merge) を実施した。

### Deferred Items
- `agents/review-bug.md` / `agents/review-spec.md` への明示的な `effort: high` frontmatter 追加 (将来の `run-review.sh` 再評価の前提条件) は本 Issue のスコープ外のまま。
- `--effort=` フラグ露出によるサイズ条件付き effort tiering (impact strategy レポート §8 C5) は Icebox 候補として別スコープのまま。

### Notes for Next Phase
- Post-merge AC は「なし」(Spec `## Verification` 参照)。`/verify 921` は形式的な no-op 確認のみで良い。
- 変更ファイルはすべてドキュメント (`docs/reports/`, `docs/tech.md`, `docs/ja/tech.md`, `docs/spec/`) のみで、`run-*.sh`/matrix 表本体・エージェント frontmatter への変更はなし。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- rubric 型 AC 2件は意味的に明確で、`/verify` が両者を UNCERTAIN なく即 PASS 判定できた。Issue 本文に Auto-Resolved Ambiguity Points (記録フォーマット・A/B 手法) が含まれており、実装フェーズの曖昧性を事前に潰せていた。AC 品質・検証容易性ともに良好。

#### design
- spec フェーズ時点で Explore sub-agent 併用の実質的分析を完了し「両方 high 維持」の判定まで確定させていたため、code フェーズは note 追記+レポート作成の機械的作業に縮退した。Issue=WHAT / Spec=HOW の分離が有効に機能し、code フェーズのリスクを構造的に下げた良い前例。実装は Implementation Steps 1-3 と完全一致。

#### code
- 手戻り・fixup/amend なし (git 履歴クリーン、本 Issue は squash merge 1 コミット)。
- **注目観察 (phase-state 不一致からの再開)**: `/code` Step 3 の `phase/ready` プリコンディションチェック時点で Issue #921 が既に `phase/code` へ遷移済みだった。先行 `/code` 実行が「ラベル遷移後・実装着手前」に中断したものと判断され、`reconcile-phase-state.sh --check-precondition` は `matches_expected: false` を返したが、完成済み Spec が存在し PR/worktree/実装コミットは皆無だったため「既存 Spec を正として続行」で解決した。非対話モードの auto-resolve 方針は「Spec 不在時のみ Issue 本文から読み取る」を明文化しているが、この「`phase/code` 既遷移 + 完成 Spec 存在 + 実装ゼロ」の中断リカバリケースは明示されていない。`## Auto Retrospective` に未記録のため notable として本 retro に記録。

#### review
- 検出 issue ゼロ (MUST/SHOULD/CONSIDER いずれもなし)。doc-only の低リスク差分に対し review は適切に軽量で、実際の diff (tech.md note + 新規レポート) がクリーンだった事実と整合。過検出・見逃しの兆候なし。

#### merge
- squash merge クリーン (`mergeable=true`/`reason=clean`、CI success・review approved)。コンフリクトなし。問題なし。

#### verify
- rubric 型 AC 2件とも初回 PASS、reopen サイクルなし。verify command 整合性: `run-code.sh`/`run-review.sh` の実効値 `--effort high` が matrix 表 (Effort=high) と SSoT 一致しており、「据え置き=表未変更」を機械照合できた。inconsistency なし。

### Improvement Proposals
- (candidate, 低優先度) `/code` 非対話モードの auto-resolve 方針に「`phase/code` 既遷移 + 完成 Spec 存在 + 実装 (PR/worktree/commit) 皆無 → 既存 Spec を正として再開」の中断リカバリケースを明文化する。現状は `reconcile-phase-state.sh --check-precondition` が `matches_expected: false` を返す状況での判断が個別 judgment に依存している (skill-infrastructure improvement: `/code` skill / `reconcile-phase-state.sh` / modules 系)。低頻度かつ既に妥当な挙動で解決済みのため優先度は低い。
