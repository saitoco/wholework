# Issue #293: skill-dev 処理を Core から Domain へ抽出 + frontmatter 駆動登録 (Core/Domain 分離 Phase 2)

## Auto Retrospective

### Execution Summary

| # | Title | Route | Result | Notes |
|---|-------|-------|--------|-------|
| #334 | Sub 2A: Domain file frontmatter スキーマ定義 + 9 本遡及適用 | pr (L, review --full) | SUCCESS | PR #353 merged, CI all green |
| #335 | Sub 2B: domain-loader の load_when 評価対応 + bats | pr (M, review --light) | SUCCESS | PR #354 merged, CI all green |
| #336 | Sub 2C: MUST/SHOULD Constraint Checklist → skill-dev-constraints.md | patch (S) | SUCCESS | main commit 11478d3 |
| #337 | Sub 2D: skill-dev 固有 Change Types → skill-dev-doc-impact.md | patch (S) | SUCCESS | main commit 7ab6175 |
| #338 | Sub 2F: skill-dev-checks.md 呼び出し gate 条件明示化 | patch (XS) | SUCCESS | main commit 992f0d2 |
| #339 | Sub 2G: Phase 1 gate 5 箇所の Domain file 委譲移行 | patch (S) | SUCCESS | main commit 255b1fd |

### Execution Timeline

- Level 1 (#334): 2026-04-22 10:43 → 11:07 (~24 min)
- Level 2 (#335): 2026-04-22 11:08 → 12:04 (~56 min)
- Level 3 並列 (#336-#339): 2026-04-22 12:05 → 12:46 (~41 min、最長 #339)
  - #337 12:34 完了（最速）
  - #338 12:34 完了
  - #336 12:44 完了
  - #339 12:46 完了（最遅）

Total wall-clock: 約 2 時間

### Parallel Execution Issues

- None

4 並列 Level 3 (#336-#339) で conflict / race / patch-lock timeout / wrapper failure は発生せず。#303 の patch-lock スコープ縮小（worktree-merge-push.sh の最終 push のみ）の効果を確認。

### Orchestration Anomalies

- None

6 sub-issue 全てが happy path で完走。3-tier recovery (Tier 1 reconciler / Tier 2 fallback catalog / Tier 3 recovery sub-agent) は発火せず。wrapper anomaly detector も反応なし。

### Improvement Proposals

1. **`/verify` が patch route sub-issue で直前 PR の CI を参照する挙動**: Level 3 の 4 本（#336/#337/#338/#339、全て patch route）の `/verify` phase が "Waiting for CI checks on PR #354" と出力していた。PR #354 は Level 2 (#335) の merged PR であり、patch route sub-issue には PR が存在しないはず。CI wait 対象の PR 決定ロジックが stale state を参照している可能性。main 直 commit の patch route では CI wait 対象を main branch の最新 workflow run に切り替えるべき。
   - 影響: 今回は CI が既に成功済みの PR #354 を参照したため無害だったが、実態と乖離した wait 対象選択は将来のトラブル源。
   - 提案: `skills/verify/SKILL.md` の CI wait 対象選択ロジックを調査し、patch route では main 直近の workflow run を参照するよう分岐を追加。

### Recovery Events Appended

None — 本 run では orchestration-fallbacks catalog (#315), recovery sub-agent (#316), wrapper anomaly detector (#313) のいずれも発火せず、`docs/reports/orchestration-recoveries.md` への append はスキップ。

## Issue Retrospective

(/issue phase 実施時の retrospective を #293 コメントから転記)

### Ambiguity 解決の判断根拠

並列調査 (Scope/Risk/Precedent) の結果、Issue 初稿に対する重要な乖離と判断事項を以下のように整理・解決した。

#### User 確認 (3 件)

1. **2E (verify-patterns.md Section 6) の扱い** → **抽出対象から除外**
   - 根拠: Section 6 の Module-Delegated Processing は `worktree-lifecycle.md` など skill-dev 非依存の module でも適用される汎用パターンであり、Scope agent の分析で skill-dev 固有ではないと確認。Issue 初稿の「skill-dev プロジェクト判定 gate」前提と不一致のため、Phase 2 では扱わず別 Phase で再評価する。

2. **`load_when:` スキーマ設計** → **定型フィールド採用 (自由記述 bash 式は不採用)**
   - 根拠: Precedent agent が抽出した #71 失敗先例 (frontmatter key:value 記法と検証文字列の齟齬) を踏まえ、定型キー (`file_exists_any` / `marker` / `capability` / `arg_starts_with` / `spec_depth`) のみを受け付ける形に決定。自由記述は検証困難・セキュリティリスクが高いため不採用。既存 Extraction Patterns 3 種 + SPEC_DEPTH 条件に 1:1 写像する設計。

3. **2C-2G の並列実行戦略** → **並列実行 OK (patch-lock 問題は #303 で解決済み)**
   - 根拠: Phase 1 (#292) では patch-lock timeout 300s により 3 件並列中 2 件が失敗した先例があるが、#303 で lock スコープが `worktree-merge-push.sh` の最終 push のみに縮小されたため、Phase 2 の 4 件並列 (2C/2D/2F/2G) は安全。

#### Auto-Resolve Log (3 件)

- **Phase 1 gate 実箇所数**: 選択 = **5 箇所** (Issue 初稿「3 箇所」→ 訂正)
  - 理由: Scope agent の実ファイル確認により `skills/code/SKILL.md` 2 箇所 + `skills/doc/SKILL.md` 3 箇所 = 計 5 箇所が判明。2G の対象を 5 箇所に修正。

- **「既存 9 本の Domain file」の所在**: 選択 = **bundled 配置** (`skills/{skill}/*.md` + `skills/doc/translate-phase.md`)
  - 理由: Risk agent の Glob 検証で `.wholework/domains/` に bundled Domain file は存在せず、9 本は bundled 配置であると確認。

- **Domain Files 表の SSoT 位置**: 選択 = **`docs/environment-adaptation.md` 単一 SSoT 維持**
  - 理由: Scope agent が `docs/structure.md` に Domain Files 表が存在しないことを確認。二重 SSoT 問題は発生していない。

### 作成した sub-issue

| Sub | # | Size | blocked_by |
|-----|---|------|-----------|
| 2A | #334 | L | なし |
| 2B | #335 | M | 2A |
| 2C | #336 | S | 2A, 2B |
| 2D | #337 | S | 2A, 2B |
| 2F | #338 | XS | 2A, 2B |
| 2G | #339 | S | 2A, 2B |

(2E は抽出対象から除外のため sub-issue 化なし。2A→2B の直列先行後、2C/2D/2F/2G を並列実行可。#334 Size は /issue retro 時点の M から /spec 時に L に昇格。)
