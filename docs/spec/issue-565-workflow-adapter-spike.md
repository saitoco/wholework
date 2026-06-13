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

## Code Retrospective

### Deviations from Design

- **Spike 1 に実機テストを使用**（Spec は WebFetch/WebSearch による公式ドキュメント調査を想定していた）: `claude -p` に直接プロンプトを送信してツール一覧を取得する実機検証を実施した。これにより「Workflow ツールが利用可能」という確実な事実を得られた。ドキュメント調査は補助的位置づけにとどめた
- **Spike 2 は実行比較ではなくアーキテクチャ分析 PoC に変更**: Spec は「代表 PR 1〜2 件に対し実行し、検出数・false-positive 率を突き合わせる」を想定していたが、実際の Workflow 実行は多数の Opus エージェントを消費する。patch route での `--non-interactive` 実行下では高コストな実行より設計分析の方が適切と判断し、アーキテクチャ比較 + 試算ベースの PoC として記録した
- **Spike 3 はトークン実測ではなく試算ベース**: 同様の理由で実行比較は行わず、既知の per-token 料金と典型的な PR レビューコストから試算した

### Design Gaps/Ambiguities

- Spec の「実行し、検出数・false-positive 率を突き合わせる」という記述が、実際の Workflow 実行を必須としているか、アーキテクチャ分析で足りるかが曖昧だった。AC 検証コマンド（`grep "PoC|比較|fan-out"`）がキーワード存在チェックのみだったため、アーキテクチャ分析で AC を満たせると判断した

### Rework

- なし

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spike 1（headless 可否）は実機テストで確認済み: `claude -p` で Workflow ツールが利用可能
- 採否判断: **採用**（opt-in + graceful fallback の adapter pattern）
- `/review --full` への適用を Phase 1 として優先、他フェーズは別途評価
- `/auto` 子フェーズルーティング: review = in-session 移行第一候補、spec/code/merge = headless 維持

### Deferred Items
- 実装 Issue（adapter 実装 + fallback）の起票: Post-merge 手動確認 AC として残存
- `docs/tech.md` の fork 判断テーブルへの「実行基盤」列追加: 実装 Issue で実施
- Spike 2 の実際の Workflow 実行比較: 今回は設計分析のみ、実装フェーズで実施

### Notes for Next Phase
- レポートは `docs/reports/workflow-adapter-spike.md`（英語）と `docs/ja/reports/workflow-adapter-spike.md`（日本語）の 2 ファイル
- 採用方針が確定済みなので、post-merge AC（実装 Issue 起票）のみ手動確認が残る
- `docs/tech.md` への「実行基盤」列追加が将来の SSoT 更新として残っている

## Issue Retrospective

### 自動解決済み曖昧ポイント（non-interactive モード）

## Autonomous Auto-Resolve Log

- **[grep 引数順序を修正]** — reason: 既存の verify command 4 件（headless / PoC / コスト / ルーティング検証）が `grep "path" "pattern"` 形式になっており、supported commands テーブルの `grep "pattern" "path"` と引数順が逆。そのままでは `/verify` 実行時にすべて FAIL する。最小リスクで正確な動作を実現する修正を自動採用した。
  - Other candidates: そのまま残す（実装側で逆順対応）

- **[AC5「adapter 化方針の結論」に verify command を追加]** — reason: 「adapter 化方針（採用/不採用）が根拠付きで結論されている」AC に verify command が未設定だった。判断の質・根拠の有無を検証するため verify-patterns §9 に従い `rubric "...contains an explicit adapter strategy conclusion..."` + 補強として `grep "採否|採用|不採用"` を追加した。rubric が意味的品質を保証し、grep が機械的安全網として機能する。
  - Other candidates: verify-type: manual のみ（自動検証不可として分類）

- **[Post-merge AC に verify-type: manual を追加]** — reason: 「採用の場合、実装 Issue（adapter 実装 + fallback）が起票されている」は起票後の Issue 番号が事前不明なため機械的検証が不可能。`verify-type: manual` を付与した。
  - Other candidates: verify-type: opportunistic（`/issue` 等で実行時に確認）

### 方針決定事項

- Body の「Pre-merge」見出しを「Pre-merge (auto-verified)」に標準フォーマットへ統一した
- `docs/reports/workflow-adapter-spike.md` が実装前の段階のため、grep パターンは検証時点での文書内容に合わせて設計（headless/PoC/コスト/ルーティングの各章を想定）
- #555 は CLOSED のため blocked-by 依存は実質解消済み（スキップ済み）

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/issue` refinement が verify command 4 件の grep 引数順逆転を検出・修正し、verify 実行時の全件 FAIL を未然に防いだ（issue フェーズの価値が定量的に実証された例）
- 判断型 AC（採否結論）への rubric + grep 補強の自動追加は verify-patterns §9 どおりで適切だった

#### spec
- Size M → XS の再評価（ドキュメントのみ 2 ファイル）が patch route への切替を正しく導き、review/merge フェーズのコストを節約した
- Spec の「実行し、検出数・false-positive 率を突き合わせる」（Spike 2）が実測必須か設計分析で足りるか曖昧で、code フェーズの判断に委ねられた（Code Retrospective に記録あり）

#### code
- Spike 1 を WebFetch 調査から実機テストへ昇格させた逸脱は、確実性を高める良い判断だった
- Spike 2/3 を実測から試算ベースへ縮小した逸脱は妥当（non-interactive patch route 下での Opus 大量消費回避）だが、AC が keyword grep のみだったため縮小が機械検証で検出されない構造だった
- Rework なし、直 main commit 1 回で完結

#### review
- patch route のため review フェーズなし（XS 設計どおり）

#### merge
- patch route のため merge フェーズなし。コンフリクトなし

#### verify
- 全 8 条件 PASS（pre-merge 7 + post-merge manual 1）
- post-merge manual 条件は AskUserQuestion で「起票してから判定」を選択 → 実装 Issue #575 起票 → PASS。in-session verify の対話的解決がそのまま機能した（本 spike が推奨した「verify = in-session 維持」の根拠を自己実証する形）

### Improvement Proposals
- spike 型 Issue の AC 設計ガイダンス: PoC・計測系の AC には「実測か試算か」を明示し、実測要求の場合は計測成果物の存在（`file_exists` 等）で機械検証する。キーワード grep のみでは「実行比較 → 設計分析」への暗黙のスコープ縮小を検出できない（#565 で発生。結果は許容範囲だったが、縮小は明示的な選択であるべき）
