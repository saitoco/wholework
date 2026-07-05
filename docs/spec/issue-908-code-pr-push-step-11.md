# Issue #908: code: pr route の gh pr create 前に git push 手順を追加

## Issue Retrospective

### 曖昧点の判断根拠

- **AC2「Step 11/Step 12 の push 記述の矛盾解消」**: `skills/code/SKILL.md` を調査した結果、Step 12 (Code Retrospective) は `gh pr create` 実行後に retrospective 用の新規コミットを作成する (L612 `git commit -s -m "Add code retrospective..."`)。Step 11 で新規追加する push はこの新規コミット作成前のブランチ初回公開 (=`gh pr create` を成功させるため) が目的であり、Step 12 の push (L619-622) は同コミットを反映するための別個の push である。したがって両者は重複ではなく、それぞれ異なる時点・異なる対象コミットに対する必要な操作と判断し、**Step 12 の push 記述は削除せず維持する**方針で AC を確定した。
  - 却下した代替案: Step 12 の push 記述を削除し Step 11 の push のみに一本化する案 → Step 12 で追加される retrospective コミットが未 push のまま PR に反映されなくなるため却下。

### 主要な方針決定

- Background の技術的主張 (「Step 11 に push 記述がなく、push は Step 12 に記載されている」) はコードベース調査 (L491, L499, L619-622) で事実確認済み。

### Acceptance Criteria 変更理由

- AC1・AC2 それぞれに `section_contains` を補助チェックとして追加 (rubric のみでは狙った箇所への記載を機械的に保証できないため)。
- AC2 の文言を「重複を許容するか削除するか」の二択提示から、確定した設計判断 (Step 12 の push は維持し、別個の必要な push として矛盾なく記述する) に基づく確定的な条件に書き換えた。

### Auto-Resolve Log

- **[Step 12 の push 記述を維持]** — 理由: Step 12 で追加される retrospective コミットの反映に必須のため
  - 他候補: Step 12 の push 記述削除 (却下)
