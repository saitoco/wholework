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
