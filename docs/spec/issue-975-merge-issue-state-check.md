# Issue #975: merge: /merge 完了時の Issue 状態検証ステップを追加

## Issue Retrospective

**タイトル正規化**: `auto: /merge 完了時の Issue 状態検証ステップを追加` → `merge: /merge 完了時の Issue 状態検証ステップを追加`。変更対象が `skills/merge/SKILL.md` であるため、component prefix を `auto` から `merge` に修正した。

**Triage 結果**: Type=Feature, Size=XS (対象 1 ファイル、SKILL.md へのステップ追加)、Value=3 (Impact=0, Alignment=4 — governance-and-verification harness という product vision との高い関連性)。

**曖昧ポイントの自動解決 (非対話モード)**:
- 「`closes #N` の自動クローズ・ラベル遷移が期待どおり機能したか」の判定基準が Issue 本文からは一意でなかったため、既存の `skills/merge/SKILL.md` Step 5 (`gh-label-transition.sh $ISSUE_NUMBER verify` が Step 4 の `closes #N` 挙動と独立して無条件実行される現行パターン) から、期待状態 = `BASE_BRANCH=main` の場合は Issue `state=CLOSED` かつ `phase/verify` ラベルへの遷移、と自動推論した。AC 文言 (rubric ベース) には影響しないため、Issue 本文には「Auto-Resolved Ambiguity Points」セクションとして根拠のみ追記した。

**Acceptance Criteria の変更**: rubric AC が対象ファイル (`skills/merge/SKILL.md`) を明示している一方、キーワードレベルの機械検証が欠けていたため、`modules/verify-patterns.md` §9 の「rubric + supplementary file_contains」ガイドラインに従い、`file_contains "skills/merge/SKILL.md" "フォールバック"` を補完 AC として追加した。「フォールバック」は現行 SKILL.md に未出現のキーワードであることを確認済み (常時 PASS にならないことを確認)。

## Consumed Comments
No new comments since last phase.

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 補完 AC のキーワードに日本語「フォールバック」を選定した結果、英語ドキュメントである `skills/merge/SKILL.md` に日本語が混入した (CLAUDE.md の言語規約では skill ドキュメントは英語)。実装は「Fallback / フォールバック」併記で緩和したが、補完キーワードは対象ファイルの言語に合わせて選定すべきだった。

#### code / verify
- XS patch route。pre-merge 2 件 PASS。post-merge opportunistic AC は該当ケース (closes #N 失敗) の発生待ち。

### Improvement Proposals
- (Tier 2 memory 相当) `/issue` の補完 AC キーワード選定 (verify-patterns.md §9) では、対象ファイルの記述言語に一致するキーワードを選ぶ。英語ドキュメントに日本語キーワードを課すと言語規約違反の混入を誘発する。単発の選定ミスのため Issue 起票はせず記録のみ。
