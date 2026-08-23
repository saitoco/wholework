# Issue #1446: verify-executor: rubric AC が Spec-only evidence を参照する場合の規約を確立

## Issue Retrospective

`--non-interactive` で `/issue 1446` (Existing Issue Refinement) を実行した。

### 調査所見

`modules/verify-executor.md` § Rubric Command Semantics を確認したところ、既に「Primary evidence outside git diff / Issue body」という近縁のガイドラインが存在した (grader のデフォルト入力外に証跡がある場合、rubric text 内でファイルパスを明示指定すれば入力範囲を拡張できる、という一般則)。ただし同セクション冒頭では「Spec files are not passed to the grader」として、Spec ファイルはこの明示指定の可否に関わらず一律に除外されている。本 Issue が扱うべき実質的なギャップは「証跡を外部ファイルに逃がす仕組みが存在しない」ことではなく、「その仕組みが Spec ファイルにだけ適用されない」という 2 つの既存ルールの相互作用である、と判明したため Background に追記した。

また姉妹 Issue `#1440` が同一パターン (retro/verify ラベル、`theme/ac-quality` は本 Issue 固有、Proposal を複数案のまま列挙し `/spec` に選定を委ねる書式) を採用していたため、本 Issue の Proposal も同じ書式を踏襲していることを明記した。

### Autonomous Auto-Resolve Log

- **AC1 の rubric 参照範囲を `modules/verify-executor.md` § Rubric Command Semantics (既存の Primary evidence outside git diff / Issue body 節) に明示的にアンカー** — 理由: 元の AC1 は「modules/verify-executor.md もしくは関連ドキュメント」という曖昧な参照先を持ち、evaluator self-sufficiency の観点で grader が判断しづらい状態だった。既存コードベース調査により当該節が実装の自然な着地点であることを確認できたため、そこを主アンカーとして明記した。関連ドキュメント (`skills/issue/SKILL.md` 等) への追記要否は HOW 側の判断として `/spec` に委ねた。
  - Other candidates: AC を分割して各ドキュメントごとに個別の verify command を割り当てる案も検討したが、Size XS の骨子を壊すため見送った。
- **Proposal 内の 3 案 (規約化 / opt-in 拡張 / 専用 verify command) のどれを採用するかは `/issue` 段階では選定しない** — 理由: 姉妹 Issue `#1440` の Proposal (Outline) が同一パターン (候補列挙のみ、選定は `/spec` に委譲) を採用しており、Issue=WHAT / Spec=HOW の責任境界 (`docs/product.md`) にも合致するため、既存 Issue 作成時の判断をそのまま踏襲した。
  - Other candidates: この場で 1 案に絞り込むことも検討したが、証跡不足の状態でオプション選定を固定すると `/spec` での再検討コストが増すと判断し見送った。
- **既存の近縁ガイドラインとの関係を Background に追記** — 理由: 調査所見なしでは `/spec` が「Primary evidence outside git diff / Issue body」節の存在に気づかず、車輪の再発明 (新規セクション追加) に向かうリスクがあったため、投資済みの調査結果をそのまま Background に転記した。
  - Other candidates: retrospective コメントのみに留める案もあったが、`/spec` が Issue body を主要な入力とするため Background に含める方が確実と判断した。

### 変更内容

- Background に調査所見 (既存「Primary evidence outside git diff / Issue body」節との関係) を追記
- Proposal に「選定は `/spec` に委ねる」旨および opt-in 案 (案2) への実装ヒントを追記
- AC1 の rubric テキストを `modules/verify-executor.md` § Rubric Command Semantics にアンカーする形に精緻化
- `## Auto-Resolved Ambiguity Points` セクションを追加

### Consumed Comments

No new comments since last phase.
