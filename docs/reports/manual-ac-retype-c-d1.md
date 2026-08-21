# manual AC 区分 C + D1: bats テスト化・manual 維持記録 (#1167)

親 Issue #1158 の分割対応。`docs/stats/2026-08-05.md` Section 10 の分類 6 区分のうち、区分 **C (故障注入、2 件)** と区分 **D1 (UI 目視、5 件)** を対象に、区分 C は bats テスト化して `verify-type: auto` へ再型付け、区分 D1 は `manual` 維持の判断根拠を記録した結果。

## 対象・件数内訳

- 区分 C: 2 件 (#1066 #1060) — bats テスト化 + `verify-type: auto` へ再型付け
- 区分 D1: 5 件 (#1059 #709 #548 #442 #441) — `manual` のまま維持

## 区分 C: bats テスト化マッピング

| Issue | 条件文要約 | 追加したテスト | 選定根拠 |
|---|---|---|---|
| #1066 | 「preview build check の失敗を検出し fix loop に入る」— `skills/code/SKILL.md` Step 13 の fix loop Row 1 (`failed>0` → fix loop へ進む) が依存する、`gh pr checks` が `bucket: "fail"` (かつ `pending` なし) の check を返した際にポーリングループが即座に break し `ci_result:` 行が `failed=1` を報告する決定的シグナル | `tests/wait-ci-checks.bats` に `"failed check with no pending breaks on first poll without sleeping (issue #1167)"` を追加。`gh pr checks` モックが `[{"name":"Deploy preview","state":"FAILURE","bucket":"fail"}]` を返すケースで、(a) `sleep` が一度も呼ばれないこと (`sleep 60` に到達しない)、(b) `ci_result: total=1 passed=0 failed=1 pending=0 cancelled=0 zero_checks=false` を確認する | 条件文の「故障を検出して fix loop に入る」という振る舞いの決定的な核は、`scripts/wait-ci-checks.sh:71-73` の `_pending -eq 0` 早期 break パスにある。実際の preview build 環境そのもの (Amplify/Vercel/Netlify の実デプロイ) は要求しておらず、このシグナルの分岐ロジックを固定 fixture で再現すれば故障注入シナリオの機械的な核を担保できる |
| #1060 | 「pre-merge AC のうち 1 件だけ未チェックの Issue で merge がブロックされる」— `skills/merge/SKILL.md` Step 1 の pre-merge AC ゲートが依存する、Pre-merge セクションの一部だけが未チェックの場合に正しい `unchecked_count` と 1-based index を返す決定的シグナル | `tests/check-pre-merge-ac.bats` に `"(b2) pre-merge 3 items with exactly 1 unchecked excludes post-merge unchecked (issue #1167)"` を追加。Pre-merge 3 件中ちょうど 1 件未チェック (Post-merge 側の未チェックは含めない) の Issue 本文をモックし、`unchecked_count` が `"1"`、`unchecked_indices` が `"3"` (Post-merge の index 4 を含まない) であることを確認する | 既存テスト (b) は Pre-merge 3 件中 2 件未チェックのケースをカバーしており、「ちょうど 1 件未チェック」という条件文が指す境界ケースは未検証だった。`scripts/check-pre-merge-ac.sh` の Pre-merge/Post-merge 分離ロジックとインデックス採番ロジックを固定 fixture で検証すれば、故障注入シナリオ (一部だけ未チェック → merge ブロック) の機械的な核を担保できる |

## 区分 C 2 件の AC 処理

- `#1066`: post-merge manual AC 行に `<!-- verify: command "bats tests/wait-ci-checks.bats" -->` を付与し `<!-- verify-type: auto -->` へ変更 (Implementation Step 5 で `gh-issue-edit.sh` により実施)
- `#1060`: post-merge manual AC 行に `<!-- verify: command "bats tests/check-pre-merge-ac.bats" -->` を付与し `<!-- verify-type: auto -->` へ変更 (Implementation Step 5 で `gh-issue-edit.sh` により実施)

いずれも retire (phase/done への直接遷移) ではなく、テストによる担保を根拠に `verify-type: auto` へ再型付けする方式を採用した。今後 `/verify` が該当 AC を通常のコマンド実行として自動判定できるようになる。

## 区分 D1 5 件の manual 維持根拠

| Issue | 条件文要約 | manual 維持の理由 |
|---|---|---|
| #1059 | preview 環境で人間が確認する AC を含む Issue を 1 件通しで実行し、AC が pre-merge セクションに配置され merge 前に確認される流れになることを確認する | `/issue`→`/spec`→`/code`→`/review` の複数スキルにまたがる実オーケストレーションと実 preview 環境が前提。単一の決定的スクリプトで模擬しようとすると `/issue` の分類判断・実 preview URL・`/review` の提示挙動を同時にモックする必要があり、統合確認としての意味を失う |
| #709 | GitHub UI から bug_report テンプレートで Issue を新規起票し、AC セクションが入力欄として表示されることを目視確認 | GitHub の Issue Forms レンダリングは GitHub 側プラットフォームの責務であり、本リポジトリのテスト可能範囲外。ブラウザでの見た目確認が必須 |
| #548 | koganezawa-com#58 を fullPage で再走し、ページ全体の 3-panel が寸法 throw なく生成される | 実 downstream リポジトリの実 Web ページに対するブラウザ自動化と実スクリーンショット取得が前提。bats はネットワークアクセスを避けるヘルメティックなテストを原則とし、生成された合成画像自体の品質確認 (throw の有無だけでなく見た目) には目視が必要 |
| #442 | `/spec` を実行したとき、インタラクティブな UI コンポーネントを含む Issue の Spec に `aria-*` 属性の動的更新 AC が含まれることを確認する | 任意の将来 Issue に対する LLM の Spec 生成品質 (ガイドラインの適切な反映) という主観的判断が対象。固定 fixture を用いた bats アサーションでは表現できず、rubric も対象となる将来の Spec ファイルを事前に名指しできないため grader の可視範囲制約に抵触する |
| #441 | サンプル UI 再現プロジェクトで `visual_diff` を実装し、検出結果が期待通り (差分あり→FAIL、なし→PASS) | D1 区分の典型例。実ブラウザによる実ページのレンダリング・スクリーンショット取得・pixel-diff 判定の一連の流れが前提で、`pixelmatch` の数値計算のみを固定 fixture でテストしても「実環境で正しく検出できるか」という AC の主旨を代替できない |

これら 5 件は `docs/stats/2026-08-05.md` の棚卸し方針表でも「manual のまま維持 (正当)」と分類されており、本記録はその判断根拠を Issue 単位で明文化したものである。Issue 本文の post-merge AC 行自体は変更しないため、`phase/verify` の Manual waiting 集計には引き続き残り続けるのが意図した挙動である。

## #708 / #719 の残余 3 AC 処理 (#1245)

親 Issue #1158 を 2026-08-05 に 5 本の sub-issue へ分割した際、区分 C (故障注入型) の 3 AC 行 (`#708` 条件1・2、`#719` 条件1) がどの sub-issue の Acceptance Criteria にも含まれないまま残った (#1163 の全件精査で区分 A 対象外と判定され「#1167 の領域」と記録されたが、#1167 の Issue 本文自体はこの 3 行に触れていなかった)。上記の区分 C 2 件 (`#1066`・`#1060`) が採用した「bats テスト化 → `verify-type: auto` 再型付け」ではなく、この 3 行は **retire (条件取り下げ + `phase/done` 遷移)** を採用した。

理由: Issue #1245 の Pre-merge AC5 が `#708`・`#719` の `phase/done` ラベルをこの実装サイクル内で即時に要求している。「auto AC 変更」方式は verify command を付与するのみでチェックボックス自体はその場では変わらず、実際に `/verify` が再実行されて該当条件を PASS 判定するまで `phase/done` へは遷移しない (実際 `#1066`・`#1060` は #1167 のマージ後、別セッションの `/verify` 実行を経て `phase/done` に到達した)。AC5 の即時遷移要求を満たすため、3 行すべてに retire を採用した。

| Issue | 条件 | 処理 | 判断根拠 |
|---|---|---|---|
| `#719` | Post-merge 条件1: 「別 PR で意図的に Forbidden Expressions FAIL を作り、`pre-merge-check.sh` が新規 FAILURE として正しく abort することを観察」(`verify-type: manual`) | retire (行削除 + `phase/done` 遷移) | `tests/pre-merge-check.bats:111` の既存 `@test "NEW_FAILURE: base PASS / head FAIL exits 2"` が、FORBIDDEN content を含む feature ブランチに対し `pre-merge-check.sh` が exit 2 かつ出力に `NEW_FAILURE` を含むことを既に決定的に検証しており、追加実装なしでこの manual AC が確認しようとしていたシナリオを実質的に担保している |
| `#708` 条件1 | Post-merge 条件1: 「`phase/ready` のみ付与・Spec 無しの M Issue に対して `reconcile-phase-state.sh --check-precondition code-pr N` を実行すると `matches_expected: false` を返すことを観察」 | retire (行削除 + `phase/done` 遷移) | `scripts/reconcile-phase-state.sh` の `_precondition_code_patch()` / `_precondition_code_pr()` はいずれも `_precondition_code_common()` への同一の 1 行委譲であり、phase 引数 (`code-patch` / `code-pr`) を条件分岐に使うロジックはこの関数内に存在しない。既存の `code-patch`×Size=M (`tests/reconcile-phase-state.bats:1636`) と `code-pr`×Size=S (同 1685 行目) の 2 テストが同一の共有ロジック分岐 (`Size != XS` → mismatch) を実質的に二重検証しており、`code-pr`×Size=M を明示的に固定した新規テストを追加しなくても十分な根拠と判断した |
| `#708` 条件2 | Post-merge 条件2: 「XS Issue (Spec 無し) に対して同コマンドを実行すると `matches_expected: true` を返すことを観察」 | retire (行削除 + `phase/done` 遷移) | 本 Issue (#1245) Implementation Step 1 で `tests/reconcile-phase-state.bats` に新規 `@test "code-pr precondition: Spec missing but Size XS -> matches_expected true"` を追加し、`code-pr`×Size=XS の `matches_expected: true` シナリオを直接カバーした |

3 行とも、Issue 本文側には個別の breadcrumb を残さない方針を採用した (Post-merge 条件の行を完全に削除)。処理の監査証跡は本セクションと Issue #1245 自身の PR・コメント履歴に集約する。
