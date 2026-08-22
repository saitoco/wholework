# Spec: check-language-convention のシングルクォート除外パターン非対称性を解消 (#1439)

No Spec existed prior to `/code` (Issue transitioned `phase/issue` → `phase/ready` without a `/spec` run; Size=XS). Requirements were read directly from the Issue body.

## Implementation Steps

1. `scripts/check-language-convention.py` に `DOUBLE_QUOTED_PATTERN` と対になる `SINGLE_QUOTED_PATTERN` を追加し、除外ロジック (`find_violations`) に組み込む。
2. `tests/check-language-convention.bats` に、(1) シングルクォートで囲んだ日本語文字列が誤検知されないこと、(2) 英語プロース中の apostrophe (縮約形・所有格) がシングルクォートの引用符ペアと誤認識されて既存の規約違反検出を妨げないこと、の両方を検証する回帰テストを追加する。

## Code Retrospective

### Deviations from Design
- N/A — Issue の Proposal に記載された方針をそのまま適用した。

### Design Gaps/Ambiguities
- Issue の Notes で懸念されていた「対になっていない apostrophe 同士の誤ペアリングによる false negative」リスクへの対策として、単純な対称パターン `'[^']*'` ではなく、開き引用符が単語文字に後続しない (`(?<!\w)`) かつ閉じ引用符が単語文字に先行されない (`(?!\w)`) 制約を課したパターン `(?<!\w)'[^']*'(?!\w)` を採用した。縮約形 (`don't`) や所有格 (`user's`) のアポストロフィは前の文字が単語文字であるため開き引用符として扱われず、誤ペアリングが起きないことを Python で実測確認した。
- 実装前の状態 (`git stash`) で新規テスト (シングルクォート除外テスト) が実際に FAIL することを確認済み。既存の非破壊テスト (contraction テスト) は実装前後どちらも PASS することも確認し、既存の規約違反検出ロジックを壊していないことを裏付けた。

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `SINGLE_QUOTED_PATTERN` は非対称ガード付き正規表現 `(?<!\w)'[^']*'(?!\w)` を採用 (Design Gaps/Ambiguities 参照)。
- 回帰テストは (1) 単純な false positive 回避、(2) 縮約形/所有格による既存検出の破壊防止、の両方を独立したテストケースとして追加した (Issue AC2 の要求どおり)。

### Deferred Items
- なし

### Notes for Next Phase
- Pre-merge AC1・AC2 (`rubric`) は `/code` 内で自己判定 PASS 済みで Issue 本文のチェックボックスも更新済み。AC3 (`github_check "gh run list"`) は patch route の branch-scoped CI AC のため本フェーズでは未チェックのまま残しており、`/verify` post-merge で評価される。

## Consumed Comments

No new comments since last phase.
