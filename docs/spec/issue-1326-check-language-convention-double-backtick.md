# Spec: check-language-convention のインラインコード除去が二重バッククォートを飲み込む欠陥を解消 (#1326)

No Spec existed prior to `/code` (Issue transitioned `phase/issue` → `phase/ready` without a `/spec` run; Size=XS). Requirements were read directly from the Issue body.

## Implementation Steps

1. `scripts/check-language-convention.py` の `INLINE_CODE_PATTERN` を `validate-skill-syntax.py` (#1130) と同じ後方参照パターン `re.compile(r'(`+)(?:(?!\1).)+?\1', re.DOTALL)` に置き換える。
2. `tests/check-language-convention.bats` に、二重バッククォート span 中の奇数個埋め込みバッククォートが後続の規約違反 (CJK) を飲み込まないことを検証する回帰テストを追加する。修正前パターンでは当該入力が FAIL (違反を検出できない) することを実測で確認済み。

## Code Retrospective

### Deviations from Design
- N/A — Issue の「対応方針 (案)」に記載されたパターンをそのまま適用した。

### Design Gaps/Ambiguities
- Issue 本文の「``the `foo` value``」例は対称的な埋め込み (偶数個のバッククォート) であり、実際には旧パターンでも飲み込みが起きないことを実測で確認した。真の飲み込みは埋め込みバッククォートが奇数個 (閉じ二重バッククォートの片方だけが誤って単体スパンに消費される場合) のときに発生する。AC2 の回帰テストはこの奇数個ケース (`` ``he said` hello``日本語プローズ`end` ``) で構成し、修正前は exit 0 (見逃し)・修正後は exit 1 (検出) となることを実測で確認した。

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `INLINE_CODE_PATTERN` を `validate-skill-syntax.py` と同一の後方参照パターンに統一した (Issue 対応方針の通り)。
- 回帰テストは Issue 本文の対称例ではなく、実際に飲み込みが発生する奇数個埋め込みバッククォートのケースで構成した (Design Gaps/Ambiguities 参照)。

### Deferred Items
- なし

### Notes for Next Phase
- Pre-merge AC1 (`file_not_contains`)・AC2 (`rubric`) は `/code` 内で自己判定 PASS 済みで Issue 本文のチェックボックスも更新済み。AC3 (`github_check "gh run list"`) は patch route の branch-scoped CI AC のため本フェーズでは未チェックのまま残しており、`/verify` post-merge で評価される。

## Consumed Comments

No new comments since last phase.

## Issue Retrospective

### Ambiguity Points & Auto-Resolution

Pre-merge AC3 の verify command が Step 7 の検証時点で **常時 PASS の no-op** であることが判明したため、非対話モードの Auto-resolve として修正した:

- **修正前**: `command "python3 scripts/check-language-convention.py"`
- **問題**: `scripts/check-language-convention.py` の `main()` は `sys.stdin.read()` で diff を読む設計で、標準入力なしで実行すると空文字列を渡され `find_violations` が常に空を返す。つまり「検査結果が変わらない」ことを一切検証せず常に exit 0 になる。
- **選んだ選択肢**: `<!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->` に差し替え
  - 理由: `.github/workflows/test.yml` の `language-convention` ジョブが `git diff ... | python3 scripts/check-language-convention.py` の形で実際の diff を検査する設計になっており、これが真の検証経路。Size=XS (patch route) のため `docs/spec/`(Standard Format ガイド) が示す `gh run list` 形式を採用。
  - 他の候補: 検証用の固定 diff を用意して pipe する `command` 案も検討したが、diff 範囲の選び方が恣意的になり別 Issue の議論が必要になるため見送り、CI 経路への委譲を選んだ (least-risk かつ既存パターン踏襲)。

Post-merge の observation 条件 (「二重バッククォートを含むドキュメントを追加・編集した際に…確認する」`event=auto-run`) は削除した:

- **理由**: `modules/verify-classifier.md` § observation Type: Firing Likelihood Check の失格例 (「特定の未来の `/auto` 実行が該当条件を満たす保証がない」) に該当し、evidence-on-fire を条件文で明示できない。飲み込み解消の事実自体は Pre-merge AC2 のテスト追加で resolve now 済みのため、Alternative 3 (条件を削除) を適用した。

### Policy Decisions

- `### Pre-merge` の見出しを Standard Format の `### Pre-merge (auto-verified)` に正規化した (内容変更なし)。
- AC1/AC2 の verify command は既存のまま維持 (Background の実測結果と一致することを再確認済み)。

### Consumed Comments

No new comments since last phase.
