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

## Issue Retrospective

### Ambiguity Points & Auto-Resolution (non-interactive mode)

- **論点**: `SINGLE_QUOTED_PATTERN` の設計 — シングルクォートはダブルクォートと異なり、英語プロース中の短縮形 (`don't` 等) や所有格 (`user's`) にも apostrophe として現れる。単純な対称正規表現 (`'[^']*'`) を採用すると、対になっていない apostrophe 同士が誤ってペアリングされ、間の文字列を丸ごと除外区間として飲み込んでしまい、既存の規約違反検出が新たに見逃される (false negative) リスクがある。
  - **選んだ選択肢**: AC 本文を変更せず (behavior/outcome ベースの rubric のまま)、`## Proposal (Outline)` に「設計上の注意」として明記し、AC2 の回帰テスト条件に「apostrophe が誤って引用符ペアとして扱われず、既存の規約違反検出を壊さないことも検証する」旨を追記。実装方針そのもの (正規表現の詳細設計) は `/spec` に委ねる。
    - 理由: least-risk かつ既存パターン踏襲。AC1/AC2 は元々 rubric ベースで実装手段を固定していないため、正規表現の具体的な衝突回避策を Issue 側で先に決め打ちする必要がなく、リスクの存在を明文化するだけで十分。
    - 他の候補: (a) 新規 Pre-merge AC を追加してこの懸念を独立条件化する — 見送り。既存 AC2 の rubric 文言拡張で同じ検証範囲をカバーでき、AC 数を不要に増やさない方が Size=XS の変更規模に見合う。(b) Issue 側で具体的な正規表現案を指定する — 見送り。実装手段の Issue 内固定は「Do not embed implementation means in ACs」の方針に反する。

### Policy Decisions

- **Pre-merge AC3 の verify command 修正**: `<!-- verify: github_check "gh pr checks" "Run bats tests" --> ` を `<!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->` に置き換えた。
  - 理由: Size=XS (`.wholework.yml` に `always-pr: true` は未設定のため patch route) では PR が作成されず、`gh pr checks` は対応する PR が存在せず恒久的に FAIL する。Triage AC audit コメント (2026-08-22, MEMBER, saito) で指摘済みの不整合であり、同種の指摘は先行事例 #1326 の Issue Retrospective でも同じ判断 (`gh run list` 形式への差し替え) がなされている。
- `### Post-merge` セクション (「なし」) を Standard Format に合わせて追加した (内容変更なし、フォーマット補完のみ)。

### Consumed Comments

- saito / MEMBER / first-class / Triage AC audit: AC3 の `gh pr checks` が Size=XS (patch route) と不整合であり `gh run list` 形式への修復を提案 / https://github.com/saitoco/wholework/issues/1439#issuecomment-5380795833

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec なし (XS patch route)。

#### design
- N/A (XS patch route)。

#### code
- commit 1件のみで完了。apostrophe 誤ペアリング対策 (非対称ガード付き正規表現) を事前検証込みで実装しており rework なし。

#### review
- N/A (XS patch route、review フェーズなし)。

#### merge
- N/A (XS patch route、merge フェーズなし)。

#### verify
- AC3 の `github_check "gh run list ... --jq '.[0].conclusion'" "success"` verify command で、#1442・#1441 と同様に CI が in_progress の間 `.conclusion` が空文字列となり `in_progress` の文字列一致で検出できない事象を再度観測した (`.status` を別途確認して待機・再実行)。同一の構造的ギャップは #1444 で改善提案として起票済みのため、本 Issue でも新規起票せず再発事例として記録するに留める。

### Retry Count

(N/A — auto-retry は発火していない)

### Improvement Proposals
- N/A (同種の提案は既に #1444 として起票済み)
