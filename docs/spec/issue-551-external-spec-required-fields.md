# Issue #551: spec: external-spec check に JSON schema 必須フィールド確認を追加

## Issue Retrospective

Nothing to note. Issue body は #549 follow-up fix の retrospective を踏まえて十分構造化されており、曖昧ポイント検出はなし。Auto-Resolved Ambiguity Points 2 件（チェックリスト挿入位置・適用範囲の例示）は spec 実装時の判断として委譲。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- XS patch route で spec phase は skip。Issue body の Auto-Resolved Ambiguity Points が spec 判断を吸収し、別 phase 不要だった

#### design
- 適用範囲が明示的 (hooks / MCP tool / GitHub API の 3 例) で、design 段階の検討は最小限で済んだ

#### code
- 実装は単一 commit (df8a2e8) で完了。fixup/amend なし、design 通り
- `## JSON I/O spec check リスト` セクションを `skills/spec/external-spec.md` の "Processing Steps" 後に追加

#### review
- XS patch route のため review phase は実施せず（直 commit）
- pre-check の `file_contains` AC 3 件が code phase 自身の self-check に相当

#### merge
- patch route で main 直接 commit。conflict なし、CI 全 pass

#### verify
- 条件 1-3 (`file_contains`) は素直に PASS
- 条件 4 の `github_check "gh run list"` form は patch-compatible だが expected_value=`bats` が run-level 出力に出ない既知の限界。display name fallback も run 名と一致しないため literal/fallback 双方で FAIL になる
- 代替検証 (`gh run view --json jobs`) で全 4 job pass を確認、実質 PASS と判定

### Improvement Proposals
- patch route 向け `github_check` AC テンプレートを `docs/templates/` or `modules/verify-patterns/*.md` に追加し、`gh run list --workflow=X --limit=1 --json conclusion --jq '.[0].conclusion'` + expected_value `"success"` の正しい form を Issue 作成時に推奨する仕組みがあると、本件のような verify command の不一致が再発しない。`/issue` skill の AC 提案ロジックに patch/PR route 別の `github_check` 雛形を組み込むのが筋。
