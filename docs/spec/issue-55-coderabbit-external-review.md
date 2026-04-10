# Issue #55: review: Copilot code review の再サポート

## Overview

移植時に live 動作確認まで踏み込めなかった Copilot code review 連携を改めて end-to-end で確認し、同じ reviewer type switch + `.wholework.yml` marker パターンで CodeRabbit を第 3 のリビュアーとして新規サポートする。既存の Copilot / Claude Code Review の実装コードはそのまま活用し、CodeRabbit は同型のケース追加のみで実装する。動作確認（live）は post-merge フェーズで manual verify により実施する。

## Changed Files

- `scripts/wait-external-review.sh`: `REVIEWER_TYPE` の case 文に `coderabbit` 分岐を追加（REVIEWER_LOGIN / REVIEWER_LOGIN_SHORT / REVIEWER_DISPLAY_NAME を定義）
- `modules/detect-config-markers.md`: marker 定義表に `coderabbit-review` → `HAS_CODERABBIT_REVIEW` 行を追加、Output Format セクションに `HAS_CODERABBIT_REVIEW` を追加
- `skills/review/external-review-phase.md`: CodeRabbit 用の待機・対応ステップ（Step 7.5 / 7.6）を Copilot パターンと同型で追加、Prerequisites の skip 条件を 3 tools 対応に更新、Step 14 テンプレートに `CodeRabbit Review Response` セクションを追加
- `skills/review/SKILL.md`: Step 7.0 の検出結果に `HAS_CODERABBIT_REVIEW` を追加、3 tools すべて false のときに Step 7 全体を skip する条件に更新
- `tests/wait-external-review.bats`: CodeRabbit 用の mock テスト（success / timeout の 2 ケース）を追加
- `docs/workflow.md`: `.wholework.yml` 設定例に `coderabbit-review: true` を追加
- `docs/environment-adaptation.md`: Layer 1 の宣言例に `coderabbit-review` を追加、Domain Files 表の load 条件を 3 tools 対応に更新、レイヤー間関係図に `coderabbit-review` を追加
- `docs/tech.md`: Architecture Decisions のマーカー検出例を 3 tools 対応に更新
- `docs/ja/workflow.md`: 英語版と同期して `coderabbit-review` を追加
- `docs/ja/environment-adaptation.md`: 英語版と同期（宣言例、Domain Files、レイヤー間関係図）
- `docs/ja/tech.md`: 英語版と同期してマーカー検出例を更新

## Implementation Steps

**Step recording rules:**
- Step 番号は整数のみ
- 依存は「(after N)」で表記
- 受入条件マッピングは「(→ A1, A2, …)」で表記

A1–A11 は `## Verification > Pre-merge` の項目番号、P1–P4 は `## Verification > Post-merge` の項目番号。

1. **`scripts/wait-external-review.sh` に CodeRabbit ケース追加**: REVIEWER_TYPE の case 文（現在 `copilot` / `claude-code-review` の 2 分岐）に `coderabbit)` 分岐を追加する。`REVIEWER_LOGIN="coderabbitai[bot]"`、`REVIEWER_LOGIN_SHORT="coderabbitai"`、`REVIEWER_DISPLAY_NAME="CodeRabbit"` を設定する。これにより `wait-external-review.sh $PR coderabbit` が使用可能になる (→ A1, P3)

2. **`modules/detect-config-markers.md` に marker 定義追加**: Marker Definition Table に `coderabbit-review` → `HAS_CODERABBIT_REVIEW` 行を `claude-code-review` 行の直下に追加。Output Format セクションに `HAS_CODERABBIT_REVIEW: true if coderabbit-review: true is set (default: false)` 行を追加する (→ A2, A3)

3. **`skills/review/external-review-phase.md` に CodeRabbit ステップ追加** (after 1, 2): Step 7 Prerequisites の検出結果列挙に `HAS_CODERABBIT_REVIEW` を追加し、skip 条件を「3 tools すべて false なら Step 7 全体（7.1–7.6）を skip」に更新する。Copilot (7.1/7.2) / Claude Code Review (7.3/7.4) の直後に Step 7.5「Wait for CodeRabbit Review」と Step 7.6「Apply CodeRabbit Issues」を同型で追加する。コミットメッセージは `"Address CodeRabbit review: {fix summary}"` 形式。Step 14 テンプレートに `### CodeRabbit Review Response` セクションを Copilot / Claude Code Review と同じ表形式で追加する (→ A4)

4. **`skills/review/SKILL.md` Step 7.0 更新** (after 2): 検出結果ブロックに `HAS_CODERABBIT_REVIEW: true if coderabbit-review: true is set (default: false)` を追加する。既存の skip 条件「`HAS_COPILOT_REVIEW=false` かつ `HAS_CLAUDE_CODE_REVIEW=false` → Step 7 skip」を「3 tools すべて false → Step 7 skip」に更新する (→ A5)

5. **`tests/wait-external-review.bats` に CodeRabbit テスト追加** (after 1): `create_gh_mock_with_review` ヘルパを使って以下の 2 ケースを追加する:
   - `@test "coderabbit: review found with explicit PR number"`: `create_gh_mock_with_review "coderabbitai" "coderabbitai[bot]"` + `run bash "$SCRIPT" 88 coderabbit` → status 0 + output に `"CodeRabbit Review Complete"` を含む
   - `@test "coderabbit: timeout when no review arrives"`: `create_gh_mock_no_review` + `COPILOT_REVIEW_TIMEOUT=1` → status 1 + `"CodeRabbit"` と `"Timeout"` を含む (→ A6, A7)

6. **`docs/workflow.md` 設定例更新** (after 2, 3): L87 付近の `.wholework.yml` コードブロックに `coderabbit-review: true        # Enable CodeRabbit AI review (wait and handle findings in Step 6)` 行を `claude-code-review: true` の直下に追加する (→ A8)

7. **`docs/environment-adaptation.md` 更新** (after 2, 3): Layer 1 の `.wholework.yml` 宣言例に `coderabbit-review: true` 行を追加する（`copilot-review: true` の直下）。Domain Files 表の `skills/review/external-review-phase.md` 行の Load Condition を `copilot-review`, `claude-code-review`, or `coderabbit-review` is true に更新する。Layer 関係図（L268 付近）に `coderabbit-review` 矢印を追加する (→ A9)

8. **`docs/tech.md` Architecture Decisions 更新** (after 2): L52 のマーカー検出例を 3 tools 対応に更新: `review/external-review-phase.md (read when copilot-review: true, claude-code-review: true, or coderabbit-review: true)` (→ A9 [tech.md は environment-adaptation.md と統合して A9 でカバー])

9. **`docs/ja/workflow.md` / `docs/ja/environment-adaptation.md` / `docs/ja/tech.md` 同期更新** (after 6, 7, 8): Step 6/7/8 で行った英語版の変更を対応する日本語ドキュメントに同期する（`.wholework.yml` 設定例、Domain Files 表、レイヤー関係図、マーカー検出例）。翻訳は既存の日本語表現パターンに倣う (→ A10, A11)

## Alternatives Considered

### Plugin 機構による抽象化

CodeRabbit を追加する際に、将来的なツール追加を容易にするためにプラグイン機構（`adapters/{reviewer}-adapter.md` + resolver）を導入する案。**却下**: 現行の「reviewer type 引数 + marker + case 文」パターンは既に 2 ツールで実証済みで、新規追加は 9 ステップ（上記）のみで完結する。プラグイン機構を導入するとオーバーエンジニアリングとなり、保守負債を増やす。

### `EXTERNAL_REVIEW_TIMEOUT` 環境変数への改名

Timeout 環境変数 `COPILOT_REVIEW_TIMEOUT` は現在 Claude Code Review にも流用されており、命名が実態と乖離している。これを `EXTERNAL_REVIEW_TIMEOUT` に改名する案。**却下**: breaking change となり、既存 `.claude/settings.json` や CI 環境変数を破壊する。backward-compat のためのエイリアス追加もスコープ外。本 Issue では命名のまま流用し、将来の別 Issue で整理する余地を残す。

### Timeout を reviewer ごとに個別設定可能にする

`CODERABBIT_REVIEW_TIMEOUT` 等のリビュアー固有 timeout。**却下**: 現状 3 ツールとも同じ `TIMEOUT=300` で十分動作しており、個別化する需要が確認されていない。必要になった時点で後発 Issue で対応。

## Verification

### Pre-merge

- <!-- verify: grep "coderabbit" "scripts/wait-external-review.sh" --> A1: `scripts/wait-external-review.sh` に CodeRabbit 用の reviewer type ケースが追加されている
- <!-- verify: grep "coderabbit-review" "modules/detect-config-markers.md" --> A2: `modules/detect-config-markers.md` の marker 定義表に `coderabbit-review` 行が追加されている
- <!-- verify: grep "HAS_CODERABBIT_REVIEW" "modules/detect-config-markers.md" --> A3: `modules/detect-config-markers.md` の Output Format に `HAS_CODERABBIT_REVIEW` が追加されている
- <!-- verify: grep "CodeRabbit" "skills/review/external-review-phase.md" --> A4: `skills/review/external-review-phase.md` に CodeRabbit 用の待機・対応ステップが追加されている
- <!-- verify: grep "HAS_CODERABBIT_REVIEW" "skills/review/SKILL.md" --> A5: `skills/review/SKILL.md` Step 7.0 の検出結果に `HAS_CODERABBIT_REVIEW` が含まれている
- <!-- verify: grep "coderabbit" "tests/wait-external-review.bats" --> A6: `tests/wait-external-review.bats` に CodeRabbit 用 mock テストが追加されている
- <!-- verify: github_check "gh pr checks" "bats" --> A7: 既存 bats テスト + 追加した CodeRabbit テストがすべてパスする
- <!-- verify: grep "coderabbit-review" "docs/workflow.md" --> A8: `docs/workflow.md` の `.wholework.yml` 設定例に `coderabbit-review` が記載されている
- <!-- verify: grep "coderabbit" "docs/environment-adaptation.md" --> A9: `docs/environment-adaptation.md` に CodeRabbit の marker 連携が記載されている
- <!-- verify: grep "coderabbit-review" "docs/ja/workflow.md" --> A10: `docs/ja/workflow.md` が `docs/workflow.md` と同期して更新されている
- <!-- verify: grep "coderabbit" "docs/ja/environment-adaptation.md" --> A11: `docs/ja/environment-adaptation.md` が `docs/environment-adaptation.md` と同期して更新されている

### Post-merge

- P1: wholework の `.wholework.yml` に `copilot-review: true` を設定した実 PR を作成し、`/review` 経由で Copilot レビューが待機 → コメントが取得されることを確認
- P2: 同様に `claude-code-review: true` を設定した PR で Claude Code Review の待機・取得が行われることを確認
- P3: `coderabbit-review: true` を設定した PR で CodeRabbit の待機・取得が行われることを確認
- P4: 3 つの marker を同時に有効化した場合でも `/review` が各リビュアーを順次待機・処理し、いずれかが timeout しても後続に進むことを確認

## Tool Dependencies

### Bash Command Patterns

none（既存の allowed-tools で十分: `${CLAUDE_PLUGIN_ROOT}/scripts/wait-external-review.sh:*` は既に含まれる）

### Built-in Tools

none（既存の Read / Write / Edit / Grep / Glob で十分）

### MCP Tools

none

## Uncertainty

- **CodeRabbit bot author login の正確な形式**: `wait-external-review.sh` の既存 2 ケースでは `REVIEWER_LOGIN="xxx[bot]"`（GitHub API レスポンス用）と `REVIEWER_LOGIN_SHORT="xxx"`（`gh pr view --json latestReviews` レスポンス用）の 2 形式を併記する必要がある。CodeRabbit は `coderabbitai[bot]` / `coderabbitai` と想定するが、実装時に検証が必要。
  - **検証方法**: (1) CodeRabbit 公式ドキュメント（<https://docs.coderabbit.ai/>）を確認する、または (2) CodeRabbit が有効な任意の公開 PR で `gh api repos/{owner}/{repo}/pulls/{n}/reviews --jq '.[] | .user.login'` を実行して author login を取得する。`/code` フェーズの最初で検証を行い、想定と異なる場合は Step 1 の REVIEWER_LOGIN 定数を調整する。
  - **影響範囲**: Implementation Step 1（`wait-external-review.sh` の case 文）、Step 5（bats mock テストの reviewer login 名）

## Notes

### 自動解決した曖昧点

- **Timeout 環境変数戦略**: 現行 `COPILOT_REVIEW_TIMEOUT` が Claude Code Review にも流用されている既存パターンを踏襲し、CodeRabbit でもそのまま使用する（命名整理は別 Issue）
- **3 リビュアー同時有効時の実行順序**: `external-review-phase.md` 内の記述順（Copilot 7.1/7.2 → Claude Code Review 7.3/7.4 → CodeRabbit 7.5/7.6）を実行順とする。既存 2 リビュアー構造をそのまま拡張
- **`external-review-phase.md` の Load 条件**: `copilot-review: true` OR `claude-code-review: true` OR `coderabbit-review: true` のいずれかで Read。現行パターンの素直な拡張
- **コミットメッセージ形式**: Copilot / Claude Code Review の既存パターン (`"Address {name} review: {fix summary}"`) を踏襲し `"Address CodeRabbit review: {fix summary}"` を採用
- **Step 14 section 名**: 既存の `Copilot Review Response` / `Claude Code Review Response` と同じ命名規則で `CodeRabbit Review Response`

### 既存実装との整合性確認

Issue 本文に「移植時にどこまでサポートしていたか曖昧にしていた」と記載があるが、コードベース調査の結果、`scripts/wait-external-review.sh`、`skills/review/external-review-phase.md`、`modules/detect-config-markers.md`、`skills/review/SKILL.md`、`tests/wait-external-review.bats` には既に Copilot と Claude Code Review 両方のサポートが実装済みで、bats mock テストもパスしている。Issue 本文と実装の矛盾はない。未検証なのは「実 PR 上での live 動作」のみで、これは post-merge の P1 / P2 で確認する。

### bats test 入力データ形式

`tests/wait-external-review.bats` の既存ヘルパ `create_gh_mock_with_review` は `(reviewer_short, reviewer_full)` を受け取る。CodeRabbit テストは以下のように呼び出す:

```bash
create_gh_mock_with_review "coderabbitai" "coderabbitai[bot]"
```

mock `gh` スクリプトは `{"author":{"login":"coderabbitai"},"state":"COMMENTED"}` を返し、`wait-external-review.sh` の `check_reviewer` 関数がこの文字列にマッチしてレビュー完了を検知する。

### 依存関係

本 Spec は Copilot と Claude Code Review のコード自体には変更を加えない。pre-merge の検証項目はすべて CodeRabbit の追加点のみを対象とする。Copilot / Claude Code Review の live 動作確認は post-merge (P1 / P2) でユーザが手動実施する。

## issue retrospective

### 曖昧点の解決根拠

- **対応範囲**: 背景の「CodeRabbit, Claude Code Review などにも対応できるよう汎用的なセットアップ」という文言を受けて、ユーザー確認で「Copilot + Claude Code Review 両方の live 確認 + CodeRabbit 新規追加」に確定。Claude Code Review は既存実装があるため新規実装は不要で、live 確認のみスコープに入れた。
- **動作確認基準**: ユーザー確認で「post-merge の live PR 確認」に確定。mock ベースの bats テスト（既存 + CodeRabbit 用追加分）を pre-merge で担保しつつ、3 リビュアーそれぞれを実 PR 上で確認する post-merge manual verify を付与。
- **汎用化の抽象化レベル**（自動解決）: 現行は既に「reviewer type 引数 + `.wholework.yml` marker + `detect-config-markers.md` 表」という汎用パターン。新規追加は case 文 + marker 行 + テストケースで完結するため、プラグイン機構等の追加抽象化は不要と判断した。

### 主要な方針決定

- Sub-issue 分割は見送り（既存パターン踏襲の単一凝集スコープ）
- 受入条件を pre-merge 機械検証（11 件）+ post-merge manual verify（4 件）に分類
- Copilot 側の設定手順書は対象外

## spec retrospective

### Minor observations

- `docs/tech.md` と `docs/ja/tech.md` のマーカー検出例は 1 行のみの変更であり、専用の pre-merge verify item を設けるほどではない。Implementation Steps では明示しているため実装漏れのリスクは低い。
- `COPILOT_REVIEW_TIMEOUT` 環境変数の命名が 3 ツール共有の実態と乖離しているが、backward compat を優先して本 Issue では触れない判断とした。

### Judgment rationale

- **Timeout 環境変数**: Plugin 機構導入を含む 3 つの代替案を検討した上で、いずれも本 Issue のスコープに対してオーバーエンジニアリングと判断。 Alternatives Considered セクションに記録済み。
- **Simplicity rule**: Pre-merge verify items が 11 件（上限 10）を 1 件超過。docs/tech.md 変更を別 verify item にせず Changed Files + Implementation Steps での網羅で十分と判断した。

### Uncertainty resolution

- **CodeRabbit bot login**: `coderabbitai[bot]` / `coderabbitai` と想定。一般知識に基づく推定だが、実装時の WebFetch または公開 PR の `gh api` 実行で確認する手順を Spec の Uncertainty セクションに明記した。影響範囲は Step 1（case 文）と Step 5（bats mock）に限定されるため、万一異なっても修正コストは低い。
