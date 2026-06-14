# Issue #591: XL Sub-issue Bulk Creation Helper (`--from-decomposition-file <yaml>`)

## Overview

XL 親 Issue の sub-issue を 50+ 件一括起票するためのヘルパーを実装する。`/issue --from-decomposition-file <path>` を `skills/issue/SKILL.md` に追加し、ユーザーが YAML で定義した decomposition から sub-issue を自動起票・関係設定する。

実装スコープ:
1. `--from-decomposition-file` 引数検出 → YAML 読み込み → schema 検証 → 循環依存 DFS 検出 → sub-issue 一括起票 + GraphQL 関係設定
2. ガイド文書 `docs/guide/xl-decomposition.md` + サンプル YAML `examples/decomposition/nuxt-to-next.yml`
3. bats 構造テスト `tests/xl-decomposition.bats`

## Changed Files

- `skills/issue/SKILL.md`: `## Decomposition File Mode` セクションを "Standard Format" セクションの直前に追加。引数検出・YAML スキーマ検証・DFS 循環検出・skeleton 生成・issue create・addSubIssue・addBlockedBy・サマリー出力を記述
- `docs/guide/xl-decomposition.md`: 新規ファイル。YAML スキーマ仕様（`parent:`, `sub_issues:`, `id`, `title`, `background`, `purpose`, `acceptance_criteria`, `blocked_by:`）・コマンド構文・skeleton 形式・ワークフロー統合ガイドを文書化
- `examples/decomposition/nuxt-to-next.yml`: 新規ファイル（新規ディレクトリ `examples/decomposition/`）。Issue 本文から foundation/theme/page-home の 3 sub-issue サンプルを配置
- `tests/xl-decomposition.bats`: 新規ファイル。`skills/issue/SKILL.md` 構造テスト 4 ケース（bash 3.2+ 互換）
- `docs/structure.md`: Directory Layout ツリーに `examples/` ディレクトリエントリ追加
- `docs/ja/structure.md`: `docs/structure.md` 変更の翻訳同期
- `docs/ja/guide/xl-decomposition.md`: `docs/guide/xl-decomposition.md` の日本語翻訳

## Implementation Steps

1. `skills/issue/SKILL.md` に `## Decomposition File Mode` セクションを追加（"Standard Format" セクションの直前に挿入）:
   - 先頭判定: `If ARGUMENTS contains '--from-decomposition-file', extract the path and run this section only.`
   - **Step 1 Read and Validate YAML**: Read ツールで YAML ファイル読み込み。schema 検証: `parent`（整数・必須）、`sub_issues`（1件以上のリスト・必須）、各 entry: `id`（文字列・必須・YAML内 unique）・`title`（必須）。`blocked_by` 参照先 id が全て `sub_issues` 内に存在するか確認。エラー時はメッセージ出力して停止（Issue 起票なし）
   - **Step 2 Detect Circular Dependencies**: `blocked_by` 依存グラフを構築し DFS で循環を検出。循環検出時はパスを出力して停止
   - **Step 3 Create Issues**: 各 sub_issue について順次: (a) skeleton body 生成（`background`/`purpose` 未指定なら TBD skeleton、`acceptance_criteria` 未指定なら "- [ ] TBD"）→ Write ツールで `.tmp/decomp-issue-{id}.md` に書き込み → `gh issue create --title "{title}" --body-file .tmp/decomp-issue-{id}.md` → temp 削除 → issue 番号記録、(b) `gh-graphql.sh --query add-sub-issue` で親子関係設定、(c) `blocked_by` 各参照について `gh-graphql.sh --query add-blocked-by` で依存設定
   - **Step 4 Output Summary**: 作成 issue 番号・タイトル・依存関係のテキスト形式サマリーを出力
   - (→ AC 1, 7, 8, 9)

2. `docs/guide/xl-decomposition.md` 新規作成:
   - YAML スキーマ: `parent:` (整数)・`sub_issues:` (リスト)・各 entry の `id`, `title`, `background`, `purpose`, `acceptance_criteria` (`condition`/`verify` エントリ列)・`blocked_by:` (id 参照リスト) を YAML 例付きで文書化
   - コマンド構文: `/issue --from-decomposition-file <path>` の使用例
   - skeleton 形式: `background`/`purpose` 未指定時のデフォルト本文テンプレート
   - スコープ除外事項（LLM 自動分割・再同期は含まない）
   - (→ AC 2, 3, 4, 5)

3. `examples/decomposition/nuxt-to-next.yml` 新規作成:
   - Issue 本文の foundation/theme/page-home 3 エントリを含む完全な YAML サンプル
   - `parent: 1000`、各エントリに `id`, `title`, `background`, `purpose`, `acceptance_criteria`, `blocked_by` を配置
   - (→ AC 6)

4. `tests/xl-decomposition.bats` 新規作成（bash 3.2+ 互換）:
   - `SKILL_FILE` を `skills/issue/SKILL.md` へ指定（PROJECT_ROOT 経由）
   - 4 テストケース:
     - `@test "decomposition: SKILL.md contains --from-decomposition-file option"` — SKILL.md に `--from-decomposition-file` が存在する
     - `@test "decomposition: SKILL.md contains circular dependency DFS detection"` — SKILL.md に `DFS` または `circular` が存在する
     - `@test "decomposition: SKILL.md contains skeleton body generation for missing fields"` — SKILL.md に `skeleton` が存在する
     - `@test "decomposition: SKILL.md contains add-sub-issue and add-blocked-by GraphQL calls"` — SKILL.md に `add-sub-issue` と `add-blocked-by` が存在する
   - (→ AC 10)

5. `docs/structure.md` に `examples/` ディレクトリエントリ追加（`├── examples/` を適切な位置に挿入）。`docs/ja/structure.md` の同箇所を日本語で翻訳同期。`docs/ja/guide/xl-decomposition.md` を日本語で新規作成（ガイド文書の翻訳）。
   - (→ AC 11)

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/issue/SKILL.md" "--from-decomposition-file" --> SKILL.md に `--from-decomposition-file` オプションが追加されている
- <!-- verify: file_exists "docs/guide/xl-decomposition.md" --> ガイド文書が存在する
- <!-- verify: file_contains "docs/guide/xl-decomposition.md" "sub_issues:" --> YAML スキーマに `sub_issues:` が文書化されている
- <!-- verify: file_contains "docs/guide/xl-decomposition.md" "blocked_by:" --> YAML スキーマに `blocked_by:` が文書化されている
- <!-- verify: file_contains "docs/guide/xl-decomposition.md" "parent:" --> YAML スキーマに `parent:` が文書化されている
- <!-- verify: file_exists "examples/decomposition/nuxt-to-next.yml" --> サンプル YAML が存在する
- <!-- verify: rubric "the implementation validates YAML schema (parent/sub_issues/id/title required), detects circular dependencies via DFS before creating any Issue, generates standard-format Issue bodies with skeletons for missing fields, and uses gh-graphql.sh add-sub-issue + add-blocked-by mutations" --> 5 要件（schema validation、循環検出、skeleton、GraphQL 連携、エラー時の atomic 中断）が rubric 基準を満たす
- <!-- verify: file_contains "skills/issue/SKILL.md" "add-sub-issue" --> GraphQL mutation `add-sub-issue` が SKILL.md に記述されている
- <!-- verify: file_contains "skills/issue/SKILL.md" "add-blocked-by" --> GraphQL mutation `add-blocked-by` が SKILL.md に記述されている
- <!-- verify: command "bats tests/xl-decomposition.bats" --> bats テストが green（schema 検証・循環検出・skeleton 生成・GraphQL 連携の最小 4 ケース、`gh` モックで実行）
- <!-- verify: command "scripts/check-translation-sync.sh" --> ja 同期確認（informational; always exits 0）

### Post-merge

- 実 XL Issue（Nuxt → Next 移行）の decomposition YAML を準備して一括起票し、50+ sub-issue が 1 コマンドで作成されることを確認 <!-- verify-type: manual -->
- フル auto-decomposition（LLM 解析 → YAML 自動生成）の follow-up Issue が起票されている <!-- verify-type: manual -->

## Notes

- **Pre-merge 検証項目数 (11) が SPEC_DEPTH=light 上限 (5) を超過**: Issue 本文の AC を verbatim コピーするため削減不可。実装ステップは 5 件に収めた。
- **`file_contains "skills/issue/SKILL.md" "add-sub-issue"` は既存コード検証**: SKILL.md の既存 Step 9 に `add-sub-issue` 参照が存在（line ~267）。新規 Decomposition File Mode セクション追加後も維持される。
- **Issue 本文の `blocked_by` 参照チェック**: 前方参照を許容する（後続エントリが `blocked_by` で先行エントリを参照可能）。循環検出は全エントリ登録後に実施する。
- **`examples/` は新規 top-level ディレクトリ**: `docs/structure.md` の Directory Layout ツリー更新が必要（SHOULD-level）。
- **`docs/guide/xl-decomposition.md` は `docs/guide/` 配下**: `check-translation-sync.sh` が `docs/guide/*.md` も対象にするため、`docs/ja/guide/xl-decomposition.md` 作成により MISSING_JA を解消する。
- **Issue 本文の Auto-Resolved Ambiguity Points**: `/issue` フェーズで既に 3 件解決済み（コマンドオプション名、AC YAML 検証、verify-type タグ）。追加の曖昧ポイント解決は不要。
- **WHOLEWORK_SCRIPT_DIR mock 不要**: 実装は `skills/issue/SKILL.md`（LLM ステップ）であり新規シェルスクリプトは追加しない。bats テストは構造テスト（SKILL.md 内容チェック）のみ。

## Code Retrospective

### Deviations from Design

- **`blocked_by` セカンドパスの明示化**: Spec の Step 3 には「(c) blocked_by 各参照について gh-graphql.sh --query add-blocked-by」と記述されていたが、前方参照（後続エントリが先行エントリを参照）に対応するため、SKILL.md では first pass（Issue 作成 + add-sub-issue）と second pass（blocked_by 設定）の 2 フェーズ構成を明示した。設計意図は同じだが SKILL.md では両フェーズを別ブロックとして分離した。

### Design Gaps/Ambiguities

- **`allowed-tools` の更新省略**: SKILL.md frontmatter の `allowed-tools` には既に `gh issue create:*` と `gh-graphql.sh:*` が含まれており、新規追加なし。新規ツール追加が不要だったため問題なし。
- **DFS 実装詳細**: Spec では「DFS で循環検出」とのみ記述。SKILL.md にはアルゴリズムの疑似コードを追記して LLM 実行時の実装精度を向上させた。

### Rework

- なし（実装ステップ 1〜5 をSpec順通りに完了）

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `## Decomposition File Mode` を `## Standard Format` の直前（`## Label Transition on Close` の直後）に配置した。SKILL.md の既存セクション順序（新規/既存/ラベル/フォーマット）を維持するため
- blocked_by 設定を second pass（全 Issue 作成後）に分離した。前方参照（後続エントリが先行エントリの id を参照）に対応するため
- bats テストは構造テスト（SKILL.md grep）のみ。LLM 実行ロジックのユニットテストは不可能なため、ドキュメント存在確認に留めた

### Deferred Items
- フル auto-decomposition（LLM 解析 → YAML 自動生成）: Issue 本文に明示されたスコープ除外。follow-up Issue を起票することが Post-merge AC に含まれる
- `examples/decomposition/` ディレクトリへの追加サンプル（Nuxt→Next 以外）: スコープ外

### Notes for Next Phase
- rubric AC (AC 7) はセマンティック評価: "validates YAML schema... detects circular dependencies via DFS... generates standard-format Issue bodies... uses gh-graphql.sh add-sub-issue + add-blocked-by mutations" — SKILL.md の Decomposition File Mode セクションで全要件をカバー済み
- `docs/structure.md` の `examples/` エントリは SHOULD-level: Spec Notes に記載あり。更新済み
- Post-merge AC は 2 件とも manual: 実 XL Issue での動作確認と follow-up Issue 起票
