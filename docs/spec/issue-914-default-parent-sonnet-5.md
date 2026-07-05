# Issue #914: tech: default parent を Sonnet 4.6 → Sonnet 5 に切替 (matrix 表本体更新、#877/#878 完了後の C1)

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective — Triage 結果 (Type=Task, Priority=high, Size=M, Value=3) と AC3 への `file_contains` 併記追加の判断根拠を確認。曖昧点0件・重複/停滞/依存関係異常なしとの記録で、新規アクションなし / https://github.com/saitoco/wholework/issues/914#issuecomment-4884574807

## Overview

`docs/reports/claude-sonnet-5-impact-strategy.md` §8 の候補 Issue **C1**。ブロッカーだった #877 (`/verify` interactive 摩擦の Sonnet 5 再測定、判定 NO-GO=再設計不要) と #878 (tokenizer 変更の watchdog/context budget 影響測定、判定「有意」) が両方 CLOSED、前提の #903 (watchdog timeout 再校正: `WATCHDOG_TIMEOUT_CODE_DEFAULT` 3600→4680、`WATCHDOG_TIMEOUT_REVIEW_DEFAULT` 2000→2600) も着地済み。

ランタイムは全 `run-*.sh` が bare `sonnet` CLI エイリアス (`ANTHROPIC_MODEL=sonnet` 含む) を使っているため、2026-06-30 以降は実行時点で既に Sonnet 5 が稼働している。一方 `docs/tech.md` §Phase-specific model and effort matrix (`ssot_for: model-effort-matrix`) は Sonnet 4.6 を default parent とした記載を維持し、Sonnet 5 の段落も「note only」表記のままになっている。

本 Issue は実態 (Sonnet 5 稼働) にドキュメントを整合させる**ドキュメント更新のみ**の作業であり、スクリプトや frontmatter の model 文字列変更は行わない。具体的には (1) matrix 表本体で default parent = Sonnet 5 を明記し、(2) Sonnet 5 段落を swap 確定済みの内容に更新し、(3) bare alias 継続 vs `claude-sonnet-5` 明示 pin のどちらを採るか方針を決定し根拠を記録する。

## Changed Files

- `docs/tech.md`: change — §Phase-specific model and effort matrix に (1) 表直前へ「default parent = Sonnet 5」を明記する一文を追加、(2) 既存の "**Sonnet 5**:" note 段落 (`**Fable 5 (Mythos class)**` 段落の直後、`SSoT note:` 行の直前) を「note only」表現を除去し #877 (NO-GO)・#878 (有意、#903 で対応済み) 着地・swap 確定済みの内容に書き換え、alias pin 方針の決定と根拠 (語 "pin" を含む) を追記
- `docs/ja/tech.md`: change — 上記 (1)(2) の日本語ミラー同期 (`docs/translation-workflow.md` Sync Procedure 準拠)。現状 ja ミラーには "Sonnet 5" 段落自体が未同期 (#876 の Spec Notes で「次回 tech.md 変更時に確認する」と明示的に持ち越されていた欠落) のため、書き換えではなく新規追加として反映する

## Implementation Steps

1. `docs/tech.md` の "### Phase-specific model and effort matrix" 節、`| Component | Phase | Model | Effort | Rationale |` テーブルヘッダーの直前に「default parent = Sonnet 5 (`claude-sonnet-5`)」を明記する一文を追加する。表内の bare `Sonnet` エイリアスが Sonnet 5 に解決されること、旧 default であった Sonnet 4.6 表記が置き換わったことを明記する (→ acceptance criteria 1)
2. 既存の "**Sonnet 5**:" note 段落 (`**Fable 5 (Mythos class)**` 段落の直後、`SSoT note:` 行の直前) を書き換える。「note only」および「matrix 表本体は依然 Sonnet 4.6 を default parent として記載」という趣旨の文言を除去し、代わりに #877 (`/verify` 摩擦再測定、判定 NO-GO=再設計不要) と #878 (tokenizer/watchdog 影響測定、判定「有意」、#903 で `WATCHDOG_TIMEOUT_CODE_DEFAULT` 3600→4680 / `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` 2000→2600 に対応済み) の両ブロッカーが着地し swap が確定・最終判断となった旨を記載する (after 1) (→ acceptance criteria 2)
3. 同じ段落内に、alias pin 方針の決定と根拠を追記する: bare `sonnet` CLI エイリアス継続を採用し `claude-sonnet-5` への明示 pin は行わない。根拠として (a) Wholework は default parent 切替を事前ゲートではなく事後の reactive recalibration として扱う運用が既に確立しており (Fable 5→Sonnet 4.6 移行 #628、および本件 Sonnet 5 移行自体の #877/#878/#903 が共にこのパターンで機能した実績)、(b) 明示 pin は `run-*.sh` (5本) と skill/sub-agent frontmatter の計約10ファイルへの協調編集を要するが、Anthropic の bare alias は意図的な大型モデルローンチ時のみ向き先を変えるため技術的な安全効果に乏しい、(c) トレードオフとして将来の Sonnet 世代移行も同様に計測 Issue 着地前にエイリアス経由で自動採用されるが、reactive recalibration SOP が2度実証されているためこれを許容する、という3点を記載する。"pin" という語を含める (after 2) (→ acceptance criteria 3)
4. Step 1-3 の内容を `docs/ja/tech.md` に同期する。ja ミラーには対応する "Sonnet 5" 段落自体が現状存在しないため、書き換えではなく新規追加として、Step 1-3 で確定した最終内容 (swap 確定・pin 方針決定込み) を日本語で追加する。`docs/translation-workflow.md` の Sync Procedure に従う (after 3)
5. Step 1-4 の編集が `review-bug` / `review-spec` / `issue-scope` / `issue-risk` / `issue-precedent` / `frontend-visual-review` の行 (Opus ルート) に一切触れていないことを確認する (after 4) (→ acceptance criteria 4)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/tech.md の model-effort matrix 表本体で default parent が Sonnet 5 として記載されている (Sonnet 4.6 の default 表記が解消されている)" --> matrix 表本体の default parent が Sonnet 5 に更新されている
- <!-- verify: rubric "docs/tech.md の Sonnet 5 note 段落が、#877/#878 完了・#903 watchdog 再校正済みを踏まえ swap 確定済みの内容に更新されている (note only ではなくなっている)" --> Sonnet 5 段落が swap 確定済みの記述に更新されている
- <!-- verify: rubric "bare sonnet alias 継続か claude-sonnet-5 明示 pin かの方針判断とその根拠 (自動追従 vs 非意図的 swap リスクのトレードオフ) が docs/tech.md に明記されている" --> pin 方針の決定と根拠が記録されている
  <!-- verify: file_contains "docs/tech.md" "pin" -->
- <!-- verify: rubric "sub-agent の Opus 4.8 ルート (review-bug/review-spec/issue-scope/issue-risk/issue-precedent/frontend-visual-review) が本 Issue で変更されていない (§4.3 の据え置き方針が維持されている)" --> 精度クリティカルな sub-agent の Opus 4.8 ルートが据え置かれている

### Post-merge

なし

## Notes

**pin 方針の決定と根拠** (AC3 対応、Implementation Step 3 の判断根拠。Non-interactive モードでの model judgment による決定):
- 決定: bare `sonnet` CLI エイリアス継続。`claude-sonnet-5` への明示 pin は不採用
- 根拠1: reactive recalibration が既に実績パターン — Fable 5→Sonnet 4.6 移行 (#628、`WATCHDOG_TIMEOUT_ISSUE_DEFAULT` 600→1200) と、今回の Sonnet 5 移行自体 (#877/#878/#903) の両方で、エイリアス切替後の watchdog/effort フォローアップのみで対応できており2度実証済み
- 根拠2: 明示 pin は `run-*.sh` 5本 (run-issue/run-spec/run-code/run-review/run-merge) と `model: sonnet` を持つ skill/sub-agent frontmatter 計約10ファイルへの協調編集を要するが、Anthropic の bare alias は意図的・大型モデルローンチ時のみ向き先を変える設計であり、"非意図的なサイレント変更を防ぐ" という pin 本来の目的に対する技術的な安全効果は薄い
- トレードオフ: 将来の Sonnet 世代 (次期メジャーモデル等) のローンチも、専用の計測 Issue が着地する前にエイリアス経由で自動的に default parent として採用されてしまう (本 Issue の Background に記載の通り、Sonnet 5 自体で既に一度発生した事象と同型)。reactive recalibration SOP が実際に機能した実績 (#628、#903) を踏まえ、Wholework はこのリスクを許容する

**docs/tech.md へ記載すべき必須事実** (Implementation Step 1-3、rubric 検証対象):
- default parent = Sonnet 5 (`claude-sonnet-5`)、旧 default Sonnet 4.6 を置き換えたことの明記
- #877 = 判定 NO-GO (再設計不要)、#878 = 判定「有意」、#903 で `WATCHDOG_TIMEOUT_CODE_DEFAULT` 3600→4680 / `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` 2000→2600 に対応済みという事実
- 両ブロッカー着地により swap は確定・最終である旨 ("note only" 表現は除去する)
- 上記 pin 方針の決定+根拠を明記し、"pin" という語を含める

**docs/ja/tech.md の同期範囲**: 現状 ja ミラーには "Sonnet 5" 段落自体が存在しない (Fable 5 段落・watchdog キャリブレーション段落は同期済みだが、その間にあるはずの Sonnet 5 段落だけが欠落している)。これは #876 (`docs/spec/issue-876-sonnet-5-impact-analysis.md` Notes: 「本 Issue のスコープを保つため、この更新は本 Spec の Implementation Steps に含めず…次回の tech.md 変更時に更新確認する」) で明示的に持ち越されていた欠落であり、本 Issue (#914) がその「次回」にあたる。よって Implementation Step 4 は既存段落の書き換えではなく新規追加として扱う。

**スコープ外の関連発見 (対応は別 Issue を推奨、本 Spec の Changed Files には含めない)**: リポジトリ全体 grep の結果、以下 10 ファイル・計約17箇所でコミットメッセージテンプレートに `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` がハードコードされている: `agents/orchestration-recovery.md`、`modules/doc-commit-push.md`、`scripts/append-consumed-comments-section.sh`、`scripts/run-auto-sub.sh` (4箇所)、`skills/auto/SKILL.md` (4箇所)、`skills/code/SKILL.md` (2箇所)、`skills/merge/SKILL.md`、`skills/review/SKILL.md` (2箇所)、`skills/verify/SKILL.md`、`skills/doc/translate-phase.md`。Overview記載の通りランタイムは既に Sonnet 5 で稼働しているため、これらのコミットは実際には Sonnet 5 が生成したにもかかわらず co-author 表記が Sonnet 4.6 のままになっている。本 Issue の Purpose は `docs/tech.md` の記述整合のみに限定されており (Background の「C1 の実質はスクリプトの model 文字列変更ではない」という明示的な記述、および AC 4件が全て `docs/tech.md` 対象であることから、本 Issue のスコープ外と判断)、本 Spec の Changed Files には含めない。別途フォローアップ Issue の起票を推奨する (`docs/migration-notes.md` に記録されている過去の類似更新「co-author tag updated to Sonnet 4.6」と同型の一括文字列更新で対応可能と見込まれる)。

**据え置き確認 (AC4)**: 表内の `review-bug` / `review-spec` / `issue-scope` / `issue-risk` / `issue-precedent` / `frontend-visual-review` の行は Opus ルートのまま変更しない。`docs/reports/claude-sonnet-5-impact-strategy.md` §4.3/§9 の据え置き推奨と一致する。

**Issue body vs 実装の整合性確認**: Issue Background の記述 (「表本体は依然 Sonnet 4.6 を default parent として記載」「note only」) は `docs/tech.md` の現行内容と一致していることを確認済み。コンフリクトなし。

**Verify command sync 確認**: 本 Spec の `## Verification > Pre-merge` は Issue 本文 `## Acceptance Criteria > Pre-merge` の4項目と verify コマンドを含め完全に一致 (件数一致: Issue側4件 / Spec側4件)。Post-merge は Issue本文どおり「なし」。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-5 を設計どおりの順序・内容で実施した (表直前の一文追加 → note 段落書き換え → pin 方針追記 → ja ミラー同期 → Opus ルート据え置き確認)。

### Design Gaps/Ambiguities
- 実装着手前の時点で、Issue 本文の Pre-merge AC 4件がすべて `[x]` 済みになっていた (直近のコミット履歴には本 Issue のコード変更や worktree の残骸がなく、以前の `/code 914` 試行が Step 10 のチェックボックス更新まで到達したものの、Step 11 のコミット前に worktree 変更が失われたことが原因と推定される)。本セッションでは実装を最初からやり直した上で、4件の rubric AC を実装済みの `docs/tech.md` に対して再評価し、いずれも PASS を再確認した。チェックボックス自体は既に正しい状態だったため上書き編集は行っていない。

### Rework
- N/A — 本セッション内での手戻りは発生していない。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- `--light --non-interactive` 指定に従い `REVIEW_DEPTH=light` で実行し、review-light エージェント1体に4観点 (spec逸脱・エッジケース・セキュリティ・ドキュメント整合性) を集約して実施した。
- Pre-merge rubric AC 4件全てを PR ブランチの `docs/tech.md` に対して独立に再評価し、いずれも PASS を再確認した (Issue のチェックボックスは既に `[x]` 済みだったため上書き編集は不要だった)。
- Code Phase Handoff の Notes 通り、AC4 (Opus ルート据え置き) を diff 上で機械的に確認し、review-bug/review-spec/issue-scope/issue-risk/issue-precedent/frontend-visual-review いずれの行も変更されていないことを確認した。
- フォローアップ Issue #918 の実在 (OPEN 状態) を `gh issue view` で確認した。

### Deferred Items
- なし — MUST/SHOULD/CONSIDER のいずれの課題も検出されなかったため、修正の持ち越しは発生していない。

### Notes for Next Phase
- `/merge 919` にそのまま進行可能 — 未解決のレビュー課題なし、CI 5ジョブ全て SUCCESS。
- フォローアップ Issue #918 (Co-Authored-By テンプレート一括更新) は未着手のまま残っている (本 PR のマージ可否とは無関係)。

## review retrospective

### Spec vs. implementation divergence patterns
- 特になし — テーブル行 (bare `Sonnet` alias 表記) は変更せず周辺の説明文のみを更新するという Spec の設計方針通りに実装されており、diff と Spec (Changed Files / Implementation Steps / Code Retrospective) の記述は完全に一致していた。

### Recurring issues
- 特になし — 同種の課題の複数発生は見られなかった。

### Acceptance criteria verification difficulty
- 4件全て rubric ベースの verify command で、文言・対象範囲が明確だったため UNCERTAIN は発生しなかった。ただし Issue のチェックボックスが実装着手前から既に `[x]` 済みという特殊な前提状態があった (Code Retrospective の Design Gaps/Ambiguities に記載の通り、以前の `/code 914` 試行が中断したことが原因と推定)。今回は rubric による独立再評価で問題なしと確認できたが、チェックボックスの事前状態を鵜呑みにせず実装内容に対して再検証する運用が有効に機能した一例として記録する。
