# Issue #565: workflow adapter spike

## Overview

dynamic workflow（multi-agent orchestration: fan-out / adversarial verify / loop-until-dry / budget スケーリング）を Wholework のフェーズ内実行エンジンとして搭載できるかを spike で検証し、adapter 化方針の採否を判断する。

検証対象は 3 点:
1. **headless 可否（spike 1）**: `claude -p` 非対話経路で Workflow ツールが利用可能か。opt-in 伝達方法（`.wholework.yml` `capabilities.workflow` → プロンプト指示）が成立するかを含む
2. **`/review --full` workflow 化 PoC（spike 2）**: finder（`review-bug`、#555 で find/filter 分離済み）→ adversarial verify の pipeline を workflow エンジンで実行し、現行 static Task fan-out と品質（検出数・false-positive 率）を比較
3. **コスト計測（spike 3）**: 同一 PR に対する現行 fan-out と workflow 版のトークン消費・実行時間を比較

spike の結論として、上記に加え `/auto` 子フェーズの実行基盤（headless `claude -p` / in-session）のフェーズ別ルーティング方針を提案する。

**前提条件（満足済み）**: ブロッカーの #555（`review-bug` の find/filter 分離）が 2026-06-12 にクローズ。`agents/review-bug.md` に「Role here is coverage, not filtering」が反映済み。

## Changed Files

- `docs/reports/workflow-adapter-spike.md`: new file（spike レポート、英語）
- `docs/ja/reports/workflow-adapter-spike.md`: new file（spike レポートの日本語版）

## Implementation Steps

1. **Spike 1 — headless Workflow 利用可否確認**: `claude -p` 環境で Workflow ツールが呼び出せるかを調査する。公式ドキュメント（WebFetch / WebSearch）で headless モードでの Workflow 利用可否・opt-in 制約を確認し、可能であれば実機テストで検証する。`task-budgets-spike.md`（#222 前例）の認証制約パターン（OAuth/API key 差異）を参照軸とする（→ AC2）
2. **Spike 2 — `/review --full` workflow 化 PoC**: 代表 PR 1〜2 件に対し、`review-bug`（finder）× N → adversarial verify（N-vote）の pipeline を workflow スクリプトとして実装・実行し、現行 static fan-out（`review-spec` + `review-bug`×2 + 検証 sub-agent）との検出数・false-positive 率を突き合わせる（→ AC3）
3. **Spike 3 — コスト計測**: Spike 2 と同一 PR で現行構成 vs. workflow 版のトークン消費・実行時間を計測し、Size 別適用基準案（M/L のみ等）を提示する（→ AC4）
4. **採否判断・ルーティング方針策定**: Spike 1〜3 の結果を統合し、adapter 化（`capabilities.workflow` opt-in + 現行 static fan-out への graceful fallback）の採否を根拠付きで決定する。加えて、`/auto` 子フェーズごとの実行基盤推奨（headless / in-session）をフェーズ別判断根拠付きで提案する（→ AC5, AC6）
5. **レポート作成**: Step 1〜4 の内容を `docs/reports/workflow-adapter-spike.md`（英語）に書き出す。続けて `docs/ja/reports/workflow-adapter-spike.md`（日本語訳）を作成する（→ AC1, AC7）

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/workflow-adapter-spike.md" --> spike レポートが `docs/reports/workflow-adapter-spike.md` に存在する
- <!-- verify: grep "headless|claude -p|非対話" "docs/reports/workflow-adapter-spike.md" --> headless（`claude -p`）経路での Workflow 利用可否の検証結果が記録されている
- <!-- verify: grep "PoC|比較|fan-out" "docs/reports/workflow-adapter-spike.md" --> `/review --full` workflow 化 PoC の品質比較結果が記録されている
- <!-- verify: grep "トークン|コスト|token" "docs/reports/workflow-adapter-spike.md" --> コスト計測（トークン・実行時間）の結果が記録されている
- <!-- verify: rubric "docs/reports/workflow-adapter-spike.md contains an explicit adapter strategy conclusion (adopt or reject) with supporting rationale" --> <!-- verify: grep "採否|採用|不採用" "docs/reports/workflow-adapter-spike.md" --> adapter 化方針（採用 / 不採用）が根拠付きで結論されている（不採用の場合も記録してクローズ可）
- <!-- verify: grep "ルーティング|routing|実行基盤" "docs/reports/workflow-adapter-spike.md" --> `/auto` 子フェーズの実行基盤（headless / in-session）のフェーズ別ルーティング方針が、フェーズごとの判断根拠付きで提案されている
- <!-- verify: file_exists "docs/ja/reports/workflow-adapter-spike.md" --> ja 版レポートが存在する

### Post-merge

- 採用の場合、実装 Issue（adapter 実装 + fallback）が起票されている（手動確認） <!-- verify-type: manual -->

## Notes

- `docs/reports/` は `docs/translation-workflow.md` の sync 対象外だが、AC7 が `docs/ja/reports/` の ja 版を明示要求しているため、Implementation Step 5 で明示的に作成する
- Spike 2 の PoC 実行には実際の PR（本リポジトリ内）へのアクセスが必要。実施時は適切な PR を選択する
- 前例として `docs/reports/ultrareview-spike.md`（#223）と `docs/reports/task-budgets-spike.md`（#222）が同型の spike レポート形式を採用しており、構成の参考とする
- grep 検証コマンド内の `|` は ripgrep の正規表現 OR 演算子であり、alternation として正常動作する（verify-executor.md §built-in translation table 確認済み）
- 前提: #555 は 2026-06-12 にクローズ済み。`agents/review-bug.md` の find/filter 分離（coverage-first, 「Role here is coverage, not filtering」）が反映されており、Spike 2 の PoC 対象構造が整っている
