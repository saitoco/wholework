# Issue #1010: workflow-guidance: review workflow の adversarial-verify ステージが実行されないバグを修正

## Consumed Comments

No new comments since last phase.

## Overview

PR #1008 (Issue #1005) の `/review --full` 実行時、`capabilities.workflow: true` 設定下の Step 10 Workflow パス (`skills/review/workflow-guidance.md` のインライン workflow スクリプト) で、finder → adversarial-verify パイプラインの verify ステージが一度も実行されないバグが観測された。pipeline の第2ステージが thunk (未実行の関数) の配列を返すだけで、それを実行する `parallel()` 呼び出しがスクリプト内に存在しないことが原因。`skills/review/workflow-guidance.md` を修正し、finder の検出結果が adversarial-verify ステージで実際に検証されてから `confirmed` に集約されるようにする。

## Reproduction Steps

1. `.wholework.yml` に `capabilities.workflow: true` を設定したプロジェクトで `/review --full` を実行する
2. Step 10 で `skills/review/workflow-guidance.md` の Workflow パスが選択され、finder (`review-spec` + `review-bug` ×2) が並列実行される
3. finder が SHOULD/CONSIDER 等の findings を返しても、pipeline 第2ステージ (`finderResult => {...}`) が `finderResult.findings.map(finding => () => agent(...))` という thunk 配列を `return` するだけで、それを実行する `parallel()`/await 呼び出しが存在しないため、verify エージェントが一度も起動されない
4. 返り値が関数を含みシリアライズ不能なため `null` に落ち、`finderResults.flat().filter(Boolean)` で消えて `confirmed: []` / `totalFound: 0` (「0件検出」) という結果になる
5. 実際には PR #1008 で review-bug エージェント×2 が SHOULD 1件・CONSIDER 1件を検出していたが、上記の理由で verify 未実行のまま握りつぶされ、実行エージェントが手動で直接検証して救済する事態となった (workflow 診断: agent_count=3 = finder 3件のみ、verify agent 0件)

## Root Cause

`skills/review/workflow-guidance.md` の Inline Workflow Script、pipeline 第2ステージ (136-144行目) が以下の構造になっている (測定: `grep -n "parallel(" skills/review/workflow-guidance.md` は実装前0件):

```javascript
finderResult => {
  if (!finderResult) return []
  return finderResult.findings.map(finding =>
    () => agent(...).then(verdict => ({ ...finding, refuted: ... }))
  )
},
```

`pipeline()` の各ステージコールバックは返り値をそのまま次段階/最終結果として扱う設計であり、関数 (thunk) の配列を実際に実行するには呼び出し側で `parallel(thunks)` を await する必要があるが、このスクリプトにはそれが欠落している。関数を含む返り値はシリアライズできず `null`相当に落ち、後続の `finderResults.flat().filter(Boolean)` でフィルタされて消える。

**傍証**: `docs/ja/reports/workflow-adapter-spike.md` (Issue #575 の元スパイクレポート) の同等コード例 (97行目付近) では `parallel(findings.findings.slice(0, 10).map(f => () => agent(...)))` のように正しく `parallel()` でラップされている。Issue #575 での production 化 (`skills/review/workflow-guidance.md` への実装) の過程でこのラップが欠落したと考えられる。

## Changed Files

- `skills/review/workflow-guidance.md`: Inline Workflow Script の pipeline 第2ステージが返す thunk 配列を `parallel(...)` でラップし、verify エージェントが実際に実行 (await) されるよう修正
- `tests/workflow-guidance.bats`: 新規ファイル — Inline Workflow Script の verify ステージが `parallel(...)` でラップされていることを grep ベースで検証する構造回帰テストを追加

## Implementation Steps

1. `skills/review/workflow-guidance.md` の Inline Workflow Script、pipeline 第2ステージ (`if (!finderResult) return []` の直後にある `return finderResult.findings.map(finding => ...)`) を `return parallel(finderResult.findings.map(finding => ...))` に変更する。対応する `.map()` の閉じ括弧 (現状 `    )` の行) の直後に `parallel()` を閉じる `)` を追加する。finder 呼び出し (第1ステージ) および `allFindings`/`confirmed` の集約ロジック (147-148行目) は変更しない (→ acceptance criteria 1, 2)
2. `tests/workflow-guidance.bats` を新規作成する。`tests/visual-diff-adapter.bats` と同様の構成 (`PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` でファイルパスを解決) を用い、以下を grep ベースで検証する: (a) `## Inline Workflow Script` セクションが存在すること、(b) verify ステージの thunk 配列が `parallel(finderResult.findings.map(finding =>` の形で `parallel()` によって実行されていること。markdown 埋め込み JS はテストランナーから不可視のため (`tests/visual-diff-adapter.bats` 冒頭のコメントと同じ制約)、実行検証ではなく grep ベースの回帰ガードとする (after 1) (→ acceptance criteria 3)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/review/workflow-guidance.md のインライン workflow スクリプトで、finder の検出結果に対する adversarial-verify ステージの agent 呼び出しが実際に実行される (thunk 配列を返すだけで未実行のまま null に落ちる構造が解消されている)" --> pipeline の verify ステージが thunk を実際に実行する構造に修正されている
- <!-- verify: rubric "修正後のスクリプトで、finder が 1 件以上の findings を返したとき verify ステージの agent が必ず起動される制御フローになっている (途中の null 落ち・filter による消失がない)" --> finder が findings を返した場合に verify エージェントが 0 件になる経路が存在しない
- <!-- verify: rubric "tests/ 配下の structural テスト、または skills/review/workflow-guidance.md 内の自己検証手順により、verify ステージ実行の回帰を検出できる仕組みが存在する" --> スクリプトの構造テストまたは検証手順が追加されている

### Post-merge
- 次回 `capabilities.workflow: true` 下の `/review --full` 実行時、finder 検出件数 > 0 のケースで verify エージェントが起動されることを観察 <!-- verify-type: observation event=pr-review-full -->

## Notes

- **SPEC_DEPTH=light (Size S) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。** Issue 本文には triage 時点の Auto-Resolved Ambiguity Points (参照ファイルパスを `modules/workflow-guidance.md` → `skills/review/workflow-guidance.md` に修正) が既に記載されており、実ファイルと照合して一致を確認済み (コンフリクトなし)。
- **修正内容の具体例 (実装ガイド)**: 現状 136-145行目 (`grep -n "parallel(" skills/review/workflow-guidance.md` は実装前0件) は次の通り —
  ```javascript
  finderResult => {
    if (!finderResult) return []
    return finderResult.findings.map(finding =>
      () => agent(
        `Adversarially refute...`,
        { label: `verify:${finding.path || 'general'}:${finding.severity}`, phase: 'Verify', schema: VERDICT_SCHEMA }
      ).then(verdict => ({ ...finding, refuted: verdict ? verdict.refuted : true }))
    )
  },
  ```
  修正後は `return finderResult.findings.map(...)` を `return parallel(finderResult.findings.map(...))` とし、対応する閉じ括弧を1つ追加する (Workflow ツールの canonical パターン `review => parallel(review.findings.map(f => () => agent(...)))` と同型)。`allFindings = finderResults.flat().filter(Boolean)` (147行目) 以降のロジックは無変更で機能する。
- **CI-sensitive changes Size M 格上げルールの適用対象外と判断**: `tests/workflow-guidance.bats` は新規 bats テストの追加だが、grep ベースの静的構造チェックでありローカルで完全に再現・検証可能。テスト並列化やフィクスチャ共有構造の変更、CI実行環境固有のレース条件には該当しないため、triage 時点の Size S (patch route) を維持する。
- **verify command 補強なし**: 3件の rubric はいずれも制御フロー的な性質記述であり、数値リテラルや定数名を含まないため、`modules/verify-patterns.md` §9 の rubric+定数名補強ルール (file_contains 追加) は非該当と判断した。
- **ドキュメント同期は対象外**: `skills/review/workflow-guidance.md` の公開インターフェース (capability フラグ名、セクション見出し、Processing Steps の手順) は変更されないため、`docs/structure.md` 等の参照更新は不要と判断した。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1・2 を Spec 記載どおりの手順・差分で実施した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の実装ガイド (Notes) に記載された差分をそのまま適用: `finderResult.findings.map(...)` の戻り値を `parallel(...)` でラップし、対応する閉じ括弧を1つ追加した。`allFindings`/`confirmed` の集約ロジック (147-148行目) は無変更。
- `tests/workflow-guidance.bats` は `tests/visual-diff-adapter.bats` と同じ `PROJECT_ROOT` アンカリングパターンで作成し、grep ベースの構造回帰テスト (`## Inline Workflow Script` セクション存在 + `return parallel(finderResult.findings.map(finding =>` 形式の存在) の2件とした。

### Deferred Items
- Post-merge AC (`verify-type: observation event=pr-review-full`) は次回 `capabilities.workflow: true` 環境下での `/review --full` 実行時に自然発生的に観測される想定。追加の手動トリガーは不要。

### Notes for Next Phase
- Pre-merge の rubric 検証は3件とも `/code` Step 10 内で実行済み・PASS 判定し、Issue #1010 のチェックボックスを更新済み。`/review` フェーズでの重複判定時も同じ diff・同じ rubric 文言のため PASS が期待される。
- `tests/workflow-guidance.bats` は新規追加のためフルスイート (`bats tests/`) には未実行 (behavioral change detection の narrow-scope 判定により対象ファイルに限定実行、PASS 確認済み)。CI では `.github/workflows/test.yml` の bats ジョブでフルスイートに含まれ実行される。
