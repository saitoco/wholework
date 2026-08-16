# Issue #1381: respawn 補償層の縮退可否を判断する (external-kill 調査決着を入力として)

## Overview

`#1146` の external-kill 調査は `docs/reports/external-kill-investigation.md` § 2026-08-16 Update ("the decisive observation") で決着した: 289 dispatch (host uptime 0.25h→145.28h) で 0 kill、うち baseline kill (uptime 131.6h) と同じ uptime band (120–144h) だけでも 111 dispatch 0 kill。rule of three による現在の kill 率上限は **< 1.04%/dispatch** (289 dispatch, 0 kill) で、上流 [#76974](https://github.com/anthropics/claude-code/issues/76974) 実測の 1.45%/dispatch を下回る。host uptime (H-b')・並行度・batch route の 3 変数はいずれも否定され、残る仮説は H-a (harness 側の episodic な background task supervision) のみで、これはローカルからは検証不能。一方で respawn 補償層 (parent session による respawn) は 12/12 で一度も失敗していない。

本 Issue は、この決着を入力として、Icebox の `#1070` (外部 kill 検出時に Step 4 completion check を先行させる手順の明文化)・`#1081` (patch route の外部 kill respawn で worktree の未 push コミットを保全)・`#1093` (`detect-external-kill.sh` の判定を連結ログでも phase 単位にスコープ) の 3 件について、それぞれ「維持 / 縮退 / クローズ」を判断し、根拠 (kill 率上限・補償層実績・episodic 仮説の未解決性) とともに `docs/reports/external-kill-investigation.md` に記録する。論点は補償層の信頼性 (一度も失敗していない) ではなく、この発生率に対してどれだけの補償機構を維持し続ける価値があるかという維持コストである。判断が「維持」に留まった Issue は、Post-merge で再評価トリガーを新しい baseline 数値に更新する。

## Changed Files

- `docs/reports/external-kill-investigation.md`: 新規 Update セクションを追記 (#1070/#1081/#1093 それぞれの維持/縮退/クローズ判断+根拠、縮退時は `detect-external-kill.sh`・`--write-manual-recovery`・`retry-on-kill.sh`・親セッション respawn 手順のうち残す/落とすものの明示、本 Issue #1381 への参照)

## Implementation Steps

1. `docs/reports/external-kill-investigation.md` § 2026-08-16 Update ("the decisive observation") と #1070 / #1081 / #1093 それぞれの現行 `## 凍結理由` / `## 再評価トリガー` を突き合わせ、次の 3 点を判断材料として確認する: 現在の kill 率上限 (rule of three, 289 dispatch / 0 kill → < 1.04%/dispatch)、補償層の実績 (12/12)、H-a (harness episodic lifecycle) が唯一残る未解決仮説であること。(→ acceptance criteria AC2)
2. #1070 / #1081 / #1093 のそれぞれについて、(a) 各 Issue 自身が定める再評価トリガーが現時点で発火しているか、(b) 提案の実装コスト (文言修正のみ / `orchestration-fallbacks.md` への新規パターン追加+テストのような新規機構) と、ステップ1で確認した低い発生率とのバランス、(c) 提案が全体の kill 発生率とは独立した正しさ・安全性上の懸念 (例: 完了済み非冪等フェーズへの誤 respawn) を防ぐものか、発生実績ゼロのエッジケース向けの新規能力追加かを踏まえ、「維持 / 縮退 / クローズ」を判断し、1 段落の根拠とともに記録する。(after 1) (→ AC1, AC2)
3. ステップ2で #1070/#1081/#1093 のいずれかが「縮退」と判断された場合、既存の補償層を構成する 4 要素 — `detect-external-kill.sh` / `--write-manual-recovery` / `retry-on-kill.sh` / 親セッション respawn 手順 (`skills/auto/SKILL.md` Step 6 External kill pre-check) — のうち何を残し何を落とすかを、その縮退判断に紐づけて明示する。いずれも縮退と判断されなかった場合は、この条件は該当なし (N/A) と明記する。(after 2) (→ AC3)
4. ステップ2〜3の判断を、`docs/reports/external-kill-investigation.md` に新規の日付付き `## ... Update` セクションとして追記する。見出しまたは本文中で Issue #1381 を明示的に参照する。(after 1, 2, 3) (→ AC1, AC2, AC3, AC4, AC5)
5. ステップ2で「維持」と判断された #1070 / #1081 / #1093 それぞれについて (「縮退」「クローズ」と判断された Issue は対象外)、`gh issue view <N> --json body --jq .body` で現在の本文を取得し (取得失敗時は本文を上書きせず中断する)、`## 再評価トリガー` 節を新しい baseline (kill 率上限 < 1.04%/dispatch、補償層実績 12/12、episodic 仮説の未解決性) を踏まえた具体的な条件文に更新する。既存の凍結理由・再評価トリガー形式に準拠させる。更新後の本文は `.tmp/` に Write ツールで書き出し、`scripts/gh-issue-edit.sh <N> <file>` で反映する。(after 4) (→ Post-merge AC)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/external-kill-investigation.md に追記された Update セクションに、#1070・#1081・#1093 のそれぞれについて「維持/縮退/クローズ」のいずれかの判断とその根拠が記録されている" --> #1070 / #1081 / #1093 のそれぞれについて「維持 / 縮退 / クローズ」の判断と根拠が記録されている
- <!-- verify: rubric "同 Update セクションの判断根拠に、現在の kill 率上限 (1.04%/dispatch 相当の値)、補償層の実績 (12/12 相当の値)、episodic 仮説が未解決である旨の 3 点がすべて含まれている" --> 判断根拠に現在の kill 率上限 (< 1.04%/dispatch)、補償層の実績 (12/12)、episodic 仮説の未解決性が含まれている
- <!-- verify: rubric "縮退の判断がなされた場合、docs/reports/external-kill-investigation.md の Update セクションに detect-external-kill.sh・--write-manual-recovery・retry-on-kill.sh・親セッション respawn 手順のうちどれを残しどれを落とすかが明示されている。#1070/#1081/#1093のいずれも縮退と判断されなかった場合、本条件は該当なし (N/A) として扱う" --> 縮退する場合、`detect-external-kill.sh` / `--write-manual-recovery` / `retry-on-kill.sh` / 親セッション respawn 手順のうち何を残し何を落とすかが明示されている
- <!-- verify: rubric "docs/reports/external-kill-investigation.md に、本 Issue (#1381) の補償層縮退可否判断を記録した新規 Update セクションが追記されている" --> 判断結果が `docs/reports/external-kill-investigation.md` に Update として追記されている
- <!-- verify: grep "#1381" "docs/reports/external-kill-investigation.md" --> 追記セクションが本 Issue (#1381) を参照している

### Post-merge

- 「縮退」または「クローズ」と判断されず Icebox に残された #1070 / #1081 / #1093 について、それぞれの Issue 本文の「再評価トリガー」節が本判断 (kill 率上限 < 1.04%/dispatch、補償層実績 12/12、episodic 仮説の未解決性) を踏まえた具体的な条件文に、既存の凍結理由・再評価トリガー形式 (#1070/#1081/#1093 に現存する形式) に準拠して更新されている。「縮退」または「クローズ」と判断された Issue はこの条件の対象外とする <!-- verify-type: manual -->

## Notes

- Post-merge AC の `verify-type: manual` は妥当: 評価対象が GitHub Issue 本文 (#1070/#1081/#1093 側) というリポジトリ外の状態であり、`rubric` のグレーダー入力範囲 (Issue 本文 + git diff + rubric 文中で明示したファイル、`modules/verify-executor.md` § Rubric Command Semantics) に含まれないため `rubric` は使えない。文言が「具体的な条件文」かどうかの判定も主観的判断を要するため `github_check` 等の機械判定も不採用 (`/issue` フェーズの Issue Retrospective で既に検討済みの判断を踏襲)。
- Implementation Step 5 は「維持」と判断された Issue のみを対象とする。Issue 本文の Post-merge AC 自体が「縮退」「クローズ」と判断された Issue をこの更新の対象外と明記している。「クローズ」判断について、Issue 本文の Pre-merge/Post-merge AC はいずれも対象 Issue の open/close 状態変更を要求していない — `docs/reports/external-kill-investigation.md` への判断記録のみが AC の対象であり、`gh issue close` の要否は Implementation Steps に含めていない。/code 実行時に「クローズ」と判断した場合でも、実際に Issue を close するかどうかは AC の文言上必須ではない判断であることに留意する。
- 本 Issue は監査/調査型 (既存の複数項目 (#1070/#1081/#1093) を定義済みカテゴリ (維持/縮退/クローズ) に分類し、判定根拠を将来の再評価が参照する永続的アーティファクト (`docs/reports/external-kill-investigation.md`) に記録する) と判定した。Implementation Steps で引用する 4 コンポーネントは Spec 作成時点で実在確認済み: `scripts/detect-external-kill.sh`、`scripts/retry-on-kill.sh`、`scripts/run-auto-sub.sh:357` (`--write-manual-recovery` サブコマンド)、`modules/orchestration-fallbacks.md:572` (`external-kill-parent-respawn`)、`skills/auto/SKILL.md:927,935` (Step 6 / External kill pre-check)。/code 実行時に新たな具体的識別子 (関数名・ファイルパス・行番号等) を判断根拠として引用する場合は、`grep -rn` / Read で実在確認すること。
- `#596` (XL 並列度の adaptive throttling) は本 Issue の Acceptance Criteria 対象外 (Purpose が #1070/#1081/#1093 の 3 件に限定)。判断の過程で #596 の扱いを揃えるべきと分かった場合は Update セクションに一言記録するに留め、新規 AC は追加しない。
- SPEC_DEPTH=light のため Step 7 (Ambiguity Resolution) の形式的な Auto-Resolve Log は生成していない。上記 Notes は Spec 作成時の調査に基づく判断メモである。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / [comment](https://github.com/saitoco/wholework/issues/1381#issuecomment-5306102807)
  - 内容: `/issue` フェーズの Issue Retrospective (曖昧性の自動解決ログ)。「Icebox 起票規約」の解釈 (#1070/#1081/#1093 の凍結理由・再評価トリガー形式を規約の実体として採用) と「#596 の scope 内外」(Purpose の #1070/#1081/#1093 限定に合わせ AC 対象外とした) の 2 点の Auto-Resolve 根拠を記録している。いずれも Issue 本文の「Auto-Resolved Ambiguity Points」節に既に反映済みの内容で、本 Spec に追加で取り込むべき新規情報はなし。

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1〜4 (`docs/reports/external-kill-investigation.md` への Update セクション追記) をこのセッションで実施した順序・内容は Spec の記載通り。

### Design Gaps/Ambiguities

- `/code` 実行開始時点で Issue のラベルは既に `phase/ready` ではなく `phase/code` になっており、`reconcile-phase-state.sh code-patch --check-precondition` も同じ不一致を警告した。一方で Implementation Step 5 が対象とする #1070 / #1081 / #1093 の Issue 本文 (「再評価トリガー」節) は、この Issue が求める最終的な内容 (kill 率上限 < 1.04%/dispatch・補償層実績 12/12・episodic 仮説未解決を踏まえた条件文、いずれも「維持」判断) まで既に更新済みだった。これは前回セッションが Implementation Step 5 (Step 4 の Update セクション追記より後に実行すべき手順) を Step 1〜4 より先に実行した状態で中断し、`docs/reports/external-kill-investigation.md` へのコミットと Spec retrospective が未完了のまま終了したものと判断した。Spec の実装順序を変更する必要はなく、Step 1〜4 (Update セクション追記とコミット) を完了させることで整合させた。非対話モードのため AskUserQuestion は使わず、既存の Issue 本文更新内容 (3 件とも「維持」) をそのまま採用する auto-resolve とした。
- 3 件それぞれの「維持 / 縮退 / クローズ」判断は、各 Issue 自身の再評価トリガーが未発火であること、実装コスト、kill 頻度から独立した正しさ上の懸念かどうかの 3 軸で個別に再検討した上で、結果として全て「維持」で確定した (既に Issue 本文へ反映済みの内容と一致)。AC3 (縮退時の要素別扱い) は該当なし (N/A) として明記した。

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- #1070 / #1081 / #1093 の全 3 件を「維持 (Icebox 継続)」と判断した。根拠は kill 率上限 < 1.04%/dispatch、補償層実績 12/12、H-a (harness episodic) が唯一未解決の仮説である旨の 3 点。判断は `docs/reports/external-kill-investigation.md` の新規 Update セクションに記録した。
- 3 件とも「維持」だったため AC3 (縮退時の要素別の残す/落とす判断) は該当なし (N/A) として明記した。
- #596 (kill 率ベースの adaptive throttling) は本 Issue の AC 対象外だが、確定した kill 率上限 (<1.04%/dispatch) が #596 の設計前提を弱めている可能性を Update セクションに一言記録するに留めた。

### Deferred Items
- Post-merge AC (`verify-type: manual`): #1070 / #1081 / #1093 の Issue 本文「再評価トリガー」節が本判断を踏まえた条件文になっているかの確認。3 件とも既に更新済み (前回セッションで先行実施) であることを Code Retrospective に記録済みなので、`/verify` は現在の本文をそのまま確認すればよい。

### Notes for Next Phase
- テスト実行時に `tests/code.bats` の "Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route" が FAIL したが、`skills/code/SKILL.md` を変更していない本 Issue の diff とは無関係で、origin/main 上で既に FAIL する pre-existing の問題 (追跡済み: #1377)。本 Issue のスコープでは対応不要。
- 全 bats スイート実行時、同時に他の worktree セッション (issue #1365, PR #1383) が並行して bats を走らせており、リソース競合で単一の集計コマンドが 10 分の Bash ceiling を超えてバックグラウンドに移行した。最終結果 (1802/1803 PASS、失敗は #1377 の 1 件のみ) は非同期の完了通知から確認した。
