# Issue #1174: review: fallback Response Summary による review 完了誤判定と未対応 MUST 指摘の merge 通過を防ぐ

## Overview

`post-fallback-review-summary.sh` は `/review` が silent no-op で終了した際に `<!-- review-summary -->` マーカー付きのフォールバック Response Summary を投稿するが、このマーカーは `reconcile-phase-state.sh` の review completion check がそのまま「review 完了」と読む完了シグナルでもある。そのため、review が MUST 指摘を残したまま silent no-op で終了しても、fallback 投稿だけで下流 (`/merge` の pre-merge ゲート) が完了と誤判定し、未対応の MUST 指摘が merge を通過し得る。

本 Issue では、fallback 経由の完了と `/review` 自身による organic な完了を機械的に区別できるシグナルを追加し、`/merge` の pre-merge ゲートがそのシグナルを検出して停止・警告できるようにする (Issue 本文の対応方針候補 A を採用。理由は Root Cause 節と Notes 節を参照)。

あわせて、姉妹 Issue #1175 (PR #1187) のレビューが検出した3件の既知の欠陥のうち、本 Issue の検出経路そのものを直接損ないうる1件 (`LATEST_STATE` の author filter 欠如) を本スコープで修正する。残り2件は対応方針を Notes 節に記録した上で本 Issue のスコープ外とする。

## Reproduction Steps

Issue #1168 の `/auto 1168` review フェーズ (2026-08-05) で実測された経路:

1. `run-review.sh` が 1 回目の review セッションを実行するが、Step 14 (Response Summary 投稿) の前に silent no-op で終了する。
2. `reconcile-phase-state.sh review --check-completion` が `matches_expected:false` を返す。
3. `post-fallback-review-summary.sh` が先行レビュー (`Acceptance Criteria Verification Results` を含む) を検出し、最新レビュー state が `CHANGES_REQUESTED` でなければ `<!-- review-summary -->` マーカー付きの定型 fallback コメントを投稿する。
4. `reconcile-phase-state.sh` の再チェックが `matches_expected:true` を返し、`run-review.sh` は exit 0 で終了する。
5. `/auto` は `/merge` に進む。`/merge` の pre-merge AC ゲート (`check-pre-merge-ac.sh`) は Issue body のチェックボックス (Step 8 で既に更新済み) のみを見ており、コードレビューで検出された MUST/SHOULD/CONSIDER 指摘の解消状態は一切参照しない。
6. MUST 指摘が未修正のまま PR が merge され得る。

## Root Cause

`<!-- review-summary -->` は単一の完了シグナルとして `reconcile-phase-state.sh` (および間接的に `/merge` のワークフロー) から一様に消費されているが、実際には由来の異なる2つの完了モードを区別せず表している。

- **organic 完了** (`/review` Step 14 が自力で投稿): AC 検証・MUST 修正コミットまで含むパイプライン全体が完走したことを含意する。
- **fallback 完了** (`post-fallback-review-summary.sh` が投稿): 「以前に review が存在したこと」だけを確認しており、その後 MUST 指摘が修正されたかどうかには一切触れない。

どちらの由来であってもマーカー文字列は同一であるため、下流の唯一のゲート地点である `/merge` がこの2つを区別できず、fallback で救済されただけの (=MUST 未解決の可能性がある) review を organic 完了と同様に通過させてしまう。

## Changed Files

- `scripts/post-fallback-review-summary.sh`: fallback 投稿本文に `<!-- wholework-event: type=review-incomplete phase=review pr=<N> -->` を追加行として付与する。あわせて `LATEST_STATE` 算出を認証済みアクター (`gh api user`) の投稿に絞り込むよう修正する (bash 3.2+ 互換)。
- `scripts/reconcile-phase-state.sh`: `_completion_review()` が completion 一致を検出した際、`combined` 中に `type=review-incomplete` マーカーが含まれるかを追加判定し、含まれる場合は `actual_json` に `"review_incomplete_fallback":true` を追加する (bash 3.2+ 互換)。
- `modules/phase-state.md`: JSON Schema (v1) の Field contract テーブルに `actual.review_incomplete_fallback` の行を追加。Phase Table の review 行の完了シグネチャ説明を更新。
- `modules/l0-surfaces.md`: Machine-Readable Event Marker セクションに `type=review-incomplete` の新規エントリを追加 (属性・意味・「任意出現でブロック」というトレードオフの明記)。既存の `type=pre-merge-ac-gate` エントリに、新しい任意属性 `fallback=true` の説明を追記する。
- `skills/merge/SKILL.md`: frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*` を追加。Step 1 item 2 (pre-merge AC ゲート) を拡張し、`reconcile-phase-state.sh review $ISSUE_NUMBER --pr $NUMBER --check-completion` を追加実行して `review_incomplete_fallback:true` を検出した場合、既存の未チェック AC 条件と同じ block (非対話)/ask (対話) フローで扱う。Recorded decision check は `type=pre-merge-ac-gate` マーカーの `fallback=true` 属性の有無で、この条件が override 済みかを独立に判定する。
- `docs/structure.md`: Key Files の `scripts/post-fallback-review-summary.sh` の説明 (226行目) を、新マーカー付与と author filter 追加を反映するよう更新。
- `docs/ja/structure.md`: `docs/translation-workflow.md` の同期手順に従い、上記 `docs/structure.md` の変更をミラー反映。
- `tests/post-fallback-review-summary.bats`: 既存の「fallback 投稿あり」テストに `type=review-incomplete` マーカーが本文に含まれることのアサーションを追加。author filter の回帰テスト (第三者レビューが `LATEST_STATE` を上書きしないこと) を新規追加。
- `tests/reconcile-phase-state.bats`: review completion チェックに、`review_incomplete_fallback:true` が付与されるケース (マーカーあり) と付与されないケース (マーカーなし、fallback 投稿なし) の2経路を検証するテストを追加。

## Implementation Steps

1. `scripts/post-fallback-review-summary.sh` を修正する: (a) `FALLBACK_BODY` の `<!-- review-summary -->` 行の直後に `<!-- wholework-event: type=review-incomplete phase=review pr=${PR_NUMBER} -->` を追加する。(b) `gh api user -q '.login'` で認証済みアクターの login を取得し (失敗時は空文字にフォールバックしてフィルタなしの既存挙動を維持)、取得できた場合は `LATEST_STATE` 算出前に `REVIEWS_JSON` を `.author.login` がそのログインと一致するレビューのみに絞り込む。`REVIEW_BODIES` (evidence 判定用) は絞り込まない (既存の "Acceptance Criteria Verification Results" 文字列一致で十分に自己限定されているため)。(→ 受入条件 A1, 既知の欠陥1)
2. `scripts/reconcile-phase-state.sh` の `_completion_review()` を修正する: completion パターンが `combined` に一致した場合、追加で `combined` が `wholework-event:[[:space:]]*type=review-incomplete` を含むかを判定し、含む場合は `actual_json` に `"review_incomplete_fallback":true` を追加する (マーカーが無い場合は既存どおり `pr_number` のみ)。あわせて `modules/phase-state.md` の JSON Schema (v1) Field contract テーブルに `actual.review_incomplete_fallback` の行を追加し、Phase Table の review 行の完了シグネチャ説明に一文加える。(after 1) (→ 受入条件 A1)
3. `modules/l0-surfaces.md` を更新する: Machine-Readable Event Marker セクションに `type=review-incomplete` の新規エントリ (属性: `pr=<N>` のみ、`ac=`/`decision=` は持たない。意味と「PR コメント履歴中の任意出現でブロックし、latest-wins によるタイムスタンプ解決は行わない」というトレードオフを明記し、クリアには override マーカーが必要である旨を記載) を追加する。既存の `type=pre-merge-ac-gate` エントリに、任意属性 `fallback=true` (この条件の override 済みを示す) の説明を追記する。(parallel with 1, 2) (→ 受入条件 A1)
4. `skills/merge/SKILL.md` を修正する: frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*` を追加する。Step 1 item 2 を拡張し、`reconcile-phase-state.sh review $ISSUE_NUMBER --pr $NUMBER --check-completion` を追加実行、出力に `"review_incomplete_fallback":true` が含まれる場合は既存の未チェック AC 件数と同列の追加ゲート条件として扱う (非対話モード: block してマーカー投稿・exit 非ゼロ、対話モード: 既存の3択 AskUserQuestion で提示)。Recorded decision check は、現在有効な `type=pre-merge-ac-gate` マーカーが `decision=override` かつ (unchecked AC がある場合は `ac=` が現在の unchecked_indices のスーパーセットであること) かつ (review_incomplete_fallback が真の場合は `fallback=true` が付与されていること) の両方を満たす場合のみ、それぞれの条件をクリアする (どちらか一方のみ満たす場合は、満たされない方の条件のみ再提示する)。あわせて `docs/structure.md` の `scripts/post-fallback-review-summary.sh` 説明 (226行目) を更新し、`docs/translation-workflow.md` の手順に従って `docs/ja/structure.md` に同じ変更をミラーする。(after 2) (→ 受入条件 A1)
5. テストを追加する: `tests/post-fallback-review-summary.bats` の既存「AC Verification Results review exists: posts marker comment」テストに `type=review-incomplete` マーカーが投稿本文に含まれることの表明を追加する。新規テストとして、`REVIEWS_JSON` に (a) 自アクターの `CHANGES_REQUESTED` レビューと (b) それより新しい第三者アクターの `APPROVED`/`COMMENTED` レビューを含むケースで、`gh api user` モックの login と一致させたフィルタ後に `LATEST_STATE` が `CHANGES_REQUESTED` のまま判定される (fallback を投稿しない) ことを検証するテストを追加する。`tests/reconcile-phase-state.bats` には、review completion チェックの `combined` に `type=review-incomplete` マーカーを含む PR コメントがあるケースで `"review_incomplete_fallback":true` が出力されること、含まないケース (既存の completion 系テストと同様、マーカー無しで `matches_expected:true` のみ) で当該フィールドが出力されないことを検証する2経路のテストを追加する。(after 1, 2) (→ 受入条件 A4, A5)

## Verification

### Pre-merge

- <!-- verify: rubric "採用した方針が実装され、fallback 投稿が review 未完了であることを下流 (/merge のゲートまたは /auto の completion check) が機械的に検出できる経路が存在する" --> fallback 経由の review 未完了が下流で機械検出できる
- <!-- verify: rubric "採用しなかった候補について不採用の判断根拠が Spec または Issue に記録されている" --> 不採用根拠が記録されている
- <!-- verify: rubric "「関連する既知の欠陥」に列挙した3件それぞれについて、本 Issue のスコープで対応するか別 Issue に切り出すかの方針が Spec に明記されている" --> 既知の欠陥3件それぞれの対応方針が Spec に記録されている
- <!-- verify: rubric "fallback 投稿があったケースと無かったケースの 2 経路を検証するテストが tests/ 配下に存在する" --> 2 経路のテストが追加されている
- <!-- verify: command "bats tests/" --> テストスイート全件が PASS する

### Post-merge

- 次回 `/review` が silent no-op で終了し fallback サマリが投稿された際、`/merge` または `/auto` が review 未完了を検出して停止または警告することを観察する <!-- verify-type: observation event=auto-run -->
  - Expected output structure:
    - fallback 投稿を含む PR に対して `/merge` を実行した際、未完了を示す警告またはゲート停止が出力される

## Notes

### 採用方針 (Issue 本文の対応方針候補 A を採用)

Issue 本文の候補 A (fallback 投稿に独立マーカーを付与する) を採用した。理由:

- 候補 B (completion check を「未対応 MUST の不在」へ拡張): PR 行コメント中の "MUST" テキストと後続 fix コミットの相関を取る必要があり、テキストマッチに依存するぶん脆弱。MUST を正当な理由で見送るケース (修正コミットを伴わない解決) も誤検出しうる。
- 候補 C (fallback 投稿時は completion を成立させない): `run-review.sh` が exit 非ゼロのままとなり Tier 2/3 リカバリ経路へ落ちる。fallback が本来担っていた「silent no-op から `/auto` のパイプライン進行を救済する」という既存の設計意図を反転させてしまう。
- 候補 A はフォールバックの発火という事実をコードが直接埋め込む構造的シグナルであり、テキストマッチに依存しない。また `/merge` という実際に不可逆な操作 (squash merge + ブランチ削除) の直前でのみ厳格にゲートし、`/auto` のフェーズ遷移自体 (review→merge) は既存どおり進行させられるため、既存の「fallback で救済して先へ進む」という設計と両立する。

**ゲート地点を `/merge` のみに置く判断**: Issue 本文は「`/merge` のゲートまたは `/auto` の completion check」のいずれかで検出できればよいとしている。`/auto` 自身の completion check にも同じ判定を重複させる案は不採用とした。理由: `/merge` が実際の不可逆操作の直前であり、そこでゲートすれば必要十分。`/auto` 側に同じチェックを複製しても安全性上の追加効果はなく、保守対象が増えるだけである。

### 既知の欠陥3件の対応方針 (姉妹 Issue #1175 / PR #1187 のレビューで検出)

1. **`LATEST_STATE` の author filter 欠如** (`scripts/post-fallback-review-summary.sh:34`): **本 Issue のスコープで修正する** (Implementation Step 1)。第三者レビュアや bot の後続レビューが `LATEST_STATE` を上書きすると、本 Issue の AC1 が保証しようとする検出経路自体 (CHANGES_REQUESTED を正しく検出してこそ機能する fallback ガード) を直接損ないうるため、スコープに含めることが妥当と判断した。
2. **`CHANGES_REQUESTED` の sticky 性による過剰リトライ**: **本 Issue のスコープ外とし、対応を見送る (フォローアップ Issue 化を検討)**。これはコスト・効率上の懸念 (MUST 解決後も不要なフルリトライが発火する) であり、安全側 (verify し過ぎる方向) に倒れているため、見送っても本 Issue が保証する「未対応 MUST の merge 通過防止」には影響しない。修正には GitHub review state の解除/再リクエスト方針、または fix コミットとレビュー時点の相関付けという別の設計判断が必要であり、独立した Issue として扱うのが適切。
3. **継続リトライによる token usage 上書き** (`scripts/run-review.sh:245`): **本 Issue のスコープ外とし、対応を見送る (フォローアップ Issue 化を検討)**。`TOKEN_USAGE_FILE` の上書きは観測性・メトリクス精度の問題であり、未対応 MUST の merge 通過防止という本 Issue の目的とは無関係。トークン使用量の累積方針 (追記 or 合算) の設計判断が必要であり、独立した小さな Issue として切り出すのが適切。

本 Spec は上記2件の方針判断を記録するのみとし、`/spec` からの新規 Issue 起票は行わない。フォローアップ Issue 化の要否は通常の retrospective/backlog プロセスに委ねる。

### 既知の制限 (トレードオフとして許容)

`review_incomplete_fallback` の判定は、PR コメント履歴中に `type=review-incomplete` マーカーが**任意の時点で**出現するかどうかで行い、タイムスタンプに基づく latest-wins 解決は行わない (`_completion_review()` の既存実装が comments+reviews の本文をタイムスタンプなしで連結する設計になっており、latest-wins 化には呼び出し形状の変更と、それに伴う既存 bats テスト群の大幅な書き換えが必要になるため、本 Issue の Bug 修正/light スコープでは見送った)。

結果として、一度 fallback が発火した PR は、その後 `/review` を再実行して organic に完了しても `review_incomplete_fallback:true` が検出され続け、クリアには明示的な override マーカー (`decision=override` かつ `fallback=true`) が必要になる。この制限を許容する理由:

- Post-merge AC は「停止または警告」を要求するのみで、自動クリアまでは要求していない。
- fallback 発火自体が異常系であり、通常経路ではない。
- 既存の override マーカー機構がエスケープハッチとして機能する。

実運用でこの再ブロックが頻発し摩擦になる場合は、latest-wins 化をフォローアップ Issue として再検討する。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / intent: 姉妹 Issue #1175 (PR #1187) が検出した残存ギャップ3件を Background の「関連する既知の欠陥」セクションへ統合し、対応する Pre-merge AC を追加した旨の Issue Retrospective (`/issue` フェーズ由来)。内容は既に Issue body に反映済みのため、本 Spec は Issue body の現行内容をそのまま採用した。 / URL: https://github.com/saitoco/wholework/issues/1174#issuecomment-5199850290
