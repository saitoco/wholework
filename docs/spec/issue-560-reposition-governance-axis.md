# Issue #560: docs/product.md・guide を governance+verification 軸へリポジショニング

## Overview

`docs/product.md`（Vision / Differentiation / Future Direction）と `docs/guide/index.md` の導入文を、「issue-driven workflow のオーケストレーション」軸から「**governance + verification harness**」軸へリポジショニングする。Anthropic 第一者プロダクト Managed Agents + Outcomes を隣接オプションとして Alternatives に追加し、4 つの持続的差別化要因（① GitHub ネイティブ成果物 / ② サブスク・OAuth 認証 / ③ 段階的採用 / ④ 人間 review gate がファーストクラス）を対比形式で明示する。`docs/ja/` ミラー 2 ファイルも同期する。

内容の典拠: `docs/reports/claude-fable-5-impact-strategy.md` §2.2–§2.3、§5.1。

## Changed Files

- `docs/product.md`: Vision にテーゼ（governance-and-verification harness）を追記/再構成。Differentiation Summary に「Against Managed Agents + Outcomes」比較段落（4 差別化要因）を補完追加（既存 4 bullet は維持）。Alternatives に新サブセクション「### Anthropic-Official Agentic Development」を追加し Managed Agents + Outcomes 行を記載。Future Direction を governance+verification 軸と整合する文言に調整
- `docs/ja/product.md`: 上記の日本語同期（構造・見出しを英語版と一致させる）
- `docs/guide/index.md`: 導入文（冒頭段落〜 "Who this guide is for"）のみを governance + verification 軸へ更新（他のガイドページは対象外）
- `docs/ja/guide/index.md`: 上記の日本語同期

## Implementation Steps

1. `docs/product.md` Vision に「自律的なコーディング agent を実 GitHub リポジトリで安全に走らせるための governance-and-verification harness」テーゼを追記/再構成する（既存の Skills 構成・incremental adoption の記述は保持）（→ 受入条件 1）
2. `docs/product.md` Alternatives に「### Anthropic-Official Agentic Development」サブセクションを新設し、Managed Agents + Outcomes（第一者 / Outcome rubric ループ / API key・ホスト型）の比較行を追加。Differentiation Summary に「**Against Managed Agents + Outcomes**」比較段落として 4 差別化要因（GitHub-native artifacts / Subscription・OAuth auth / Incremental adoption / Human review gates as first-class）を追加し、既存 4 bullet は維持する。Future Direction の文言を新軸と整合させる（after 1）（→ 受入条件 2, 3）
3. `docs/guide/index.md` の導入文を governance + verification 軸へ更新する（parallel with 1, 2）（→ 受入条件 4）
4. `docs/ja/product.md`・`docs/ja/guide/index.md` を `docs/translation-workflow.md` の手順で同期する。英語版と同一コミットでコミットする（after 1, 2, 3）（→ 受入条件 5）
5. `bash scripts/check-translation-sync.sh --fail-if-outdated` と `bash scripts/check-forbidden-expressions.sh` を実行し pass を確認する（after 4）（→ 受入条件 5, 6）

## Verification

### Pre-merge

- <!-- verify: grep "governance" "docs/product.md" --> `docs/product.md` が governance + verification 軸を前面に出している
- <!-- verify: section_contains "docs/product.md" "Alternatives" "Managed Agents" --> Alternatives に Managed Agents（+ Outcomes）が追加されている
- <!-- verify: file_contains "docs/product.md" "Against Managed Agents + Outcomes" --> 4 差別化要因が Managed Agents との対比で明示されている
- <!-- verify: grep "governance|verification" "docs/guide/index.md" --> `docs/guide/index.md` の導入文が governance + verification 軸を反映している
- <!-- verify: command "bash scripts/check-translation-sync.sh --fail-if-outdated" --> ja 同期済み（translation-sync pass）
- <!-- verify: command "bash scripts/check-forbidden-expressions.sh" --> プロダクト名/禁止表現チェックが pass

### Post-merge

- `/audit drift` で product.md と実装の drift が新規検出されないこと <!-- verify-type: manual -->

## Notes

- **verify command の修正（非対話 auto-resolve）**: Issue 本文の verify command は `grep "<file>" "<pattern>"` と引数が逆順だった（規約は `grep "pattern" "path"` — `modules/verify-executor.md` 翻訳表）。さらに以下のパターンは現状の文書に既に一致し実装有無を判別できないため強化した（測定: ファイル全体を `grep -c`、worktree `main` 時点）:
  - 受入条件 1: `governance|verification|検証|統制` → `governance` のみに変更（`verification` は既存 5 hit / `governance` は 0 hit。実装後に Vision テーゼで初出する）
  - 受入条件 2: `section_contains` で Alternatives セクション内に限定（現状 "Managed Agents" は 0 hit）
  - 受入条件 3: `段階的採用|incremental|GitHub.*native|サブスク` → 固定文字列「Against Managed Agents + Outcomes」の `file_contains` に変更（`incremental` は既存 1 hit で vacuous。比較段落のリード文字列を固定文字列で検証）
  - 受入条件 5: `check-translation-sync.sh` は既定で常に exit 0（情報表示のみ）のため `--fail-if-outdated` を付与
- **ja 同期のタイミング**: `check-translation-sync.sh` は git コミットタイムスタンプ比較のため、英語版と ja ミラーは**同一コミット**に含めること（ja が先行コミットより古いと OUTDATED 判定）
- **スコープ外**: `README.md`・`docs/guide/` の index 以外のページ・`docs/workflow.md` は Issue 提案で明示的に対象外。既存 Differentiation Summary の 4 bullet は削除せず維持（Issue 自動解決済み曖昧ポイント #3）
- **用語規約**: プロダクト名は「Wholework」、名前空間は「wholework」。deprecated 用語（verify hint 等、`docs/product.md § Terms` の Formerly called 列）を新規文章で使用しない（`check-forbidden-expressions.sh` の検出対象）
- **bash 互換**: シェルスクリプト変更なし（ドキュメントのみ）
