# Issue #1124: get-config-value: 対応入力形状の仕様整理と silent failure の再発防止

## Overview

`scripts/get-config-value.sh` は `.wholework.yml` を行指向の正規表現照合でパースしている。#979 (インラインコメント strip)・#1055 (単一階層 nested キー対応)・#1055 レビュー時の追加修正 (孫キー誤採用/セクションヘッダー末尾コメント取りこぼし/正規表現メタ文字混入) と、同一スクリプトへの制約の継ぎ足しが 3 件続いており、いずれも「エラーにならず無言で誤った値または default が返る」という同一クラスの failure だった。対応/非対応の入力形状の記述がスクリプトヘッダー・`--help`・`modules/detect-config-markers.md` の 3 箇所に分散しており、1 箇所で見渡せない。

本 Issue では、対応/非対応の入力形状を単一の仕様として整理し (Issue 本文の対応方針案 A: 仕様テーブル + テーブル駆動テスト)、次の拡張要求が来る前に「どこまで対応するか」の境界を明示する。現行の行指向パース実装そのものは変更しない (採用理由は Notes 参照)。

## Changed Files

- `scripts/get-config-value.sh`: ヘッダーコメントの「Notes:」箇条書きを「Supported/Unsupported Input Shapes」表に置き換え、単一の SSoT とする。`--help` の「Notes:」も同表への pointer に簡略化 — bash 3.2+ compatible
- `modules/detect-config-markers.md`: line 102 (YAML Parsing Rules 末尾) の入力形状の個別列挙を、`scripts/get-config-value.sh` ヘッダー表への pointer に置き換える。bash reader が LLM 経由の解釈より狭い範囲にしか対応していないという対比の記述のみ残す
- `tests/get-config-value.bats`: 新しい表の「非対応」行のうち、既存 27 件の `@test` (scope: `grep -c '^@test' tests/get-config-value.bats`) で検証されていない 2 件 (2 階層以上のドットキー / inline hash format) の negative case テストを追加 — bash 3.2+ compatible
- [Steering Docs sync candidate] `modules/verify-classifier.md` (L65-66): `config=` の scope 記述が既に「matching get-config-value.sh's own constraint」という pointer 形式のため内容変更は不要と見込まれるが、`/code` で新表との整合を確認する
- [Steering Docs sync candidate] `modules/observation-trigger.md` (L263): 同上

## Implementation Steps

1. `scripts/get-config-value.sh`: ヘッダーコメント (現状 L18-28 の「Notes:」箇条書き) を、以下 8 項目を行とする「Supported/Unsupported Input Shapes」表に置き換える (→ 受入条件 1)
   - flat キー (`key: value`) — 対応。値からコメント・クオートを strip
   - 単一階層 nested キー、block format (`section:\n  key: value` を `section.key` で照会) — 対応。セクション直下の子のみ照合
   - 2 階層以上の nested キー (`a.b.c`) — 非対応。default を返す (フォールバックはドット数が 1 個の場合のみ発火)
   - inline hash format (`section: { key: value }`) — 非対応。default を返す (セクションヘッダーとして認識されない)
   - セクション直下の子 vs. それより深いインデント (孫キー) — 直下の子は対応、孫は非対応 (default を返す)
   - インラインコメント、値行 (`key: value  # comment`) — 対応。返り値から strip
   - インラインコメント、セクションヘッダー行 (`section:  # comment`) — 対応。セクション認識を妨げない (この行自体に値はない)
   - キー文字種 (`[A-Za-z0-9._-]` 制限) — 範囲外の文字を含むキーは default を返す (fail-closed。正規表現として解釈されることを防ぐガード)

2. `scripts/get-config-value.sh` (after 1): `--help` ヒアドキュメントの「Notes:」節 (現状 L53-61) を、Step 1 で追加したヘッダー表への短い pointer に簡略化する (独立した内容の再列挙をやめる) (→ 受入条件 1)

3. `modules/detect-config-markers.md` (parallel with 1, 2): line 102 の「`scripts/get-config-value.sh` は... 対応しており... 非対応のままである」という個別列挙を、`scripts/get-config-value.sh` ヘッダーの新しい表への pointer に置き換える。「bash 側の reader は本モジュールの LLM 経由の解釈より狭い範囲にしか対応していない」という対比の趣旨のみ残す (→ 受入条件 1)

4. `tests/get-config-value.bats` (parallel with 1, 2, 3): 以下 2 件の negative case テストを追加する (→ 受入条件 2)
   - 2 階層以上のドットキー: `capabilities:\n  mcp:\n    workflow: true` という YAML に対し `capabilities.mcp.workflow default` を呼んでも、その正確な nested path が存在するにもかかわらず `default` が返ることを確認する (nested フォールバックはドット数が 1 の場合のみ発火するため)
   - inline hash format: `capabilities: { workflow: true }` という YAML に対し `capabilities.workflow default` を呼ぶと、エラーにも部分一致にもならず `default` が返ることを確認する

5. (after 4) `bats tests/get-config-value.bats` を実行し、既存 27 件 + 新規 2 件 = 29 件全てが PASS することを確認する (→ 受入条件 3)

## Verification

### Pre-merge

- <!-- verify: rubric "get-config-value.sh の対応/非対応の入力形状が単一箇所に列挙されている。少なくとも flat キー、単一階層 nested キー (block format)、2 階層以上、inline hash format、セクション直接の子とそれより深いインデント、インラインコメント、キー文字種制限のそれぞれについて対応可否が読み取れる" --> 対応/非対応の入力形状が単一箇所に整理されている
- <!-- verify: rubric "tests/get-config-value.bats が上記の仕様と 1:1 で対応する形になっている、または非対応形状に対して fail-closed でエラーを返す実装とそのテストが存在する。いずれの場合も negative case (非対応形状を渡したときの挙動) が検証されている" --> 仕様とテストが対応し、negative case が検証されている
- <!-- verify: command "bats tests/get-config-value.bats" --> `tests/get-config-value.bats` が PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストスイートが CI で pass する

### Post-merge

- 次に `get-config-value.sh` へ入力形状の拡張要求が来た際、単一箇所への追記とテスト追加だけで対応できることを確認する <!-- verify-type: opportunistic -->

## Notes

- **allowed-tools impact chain check (Case 2, 適用外と判断)**: `modules/detect-config-markers.md` を読む SKILL.md は 10 件 (`grep -rl "modules/detect-config-markers\.md" skills/*/SKILL.md`)。lightweight gate (変更後の行が `scripts/*.sh` パス文字列を含むか) は該当するため機械的に読者一覧まで確認したが、`detect-config-markers.md` 自体は `.wholework.yml` を Read ツールで読む LLM 経由の解釈手順であり、line 102 の `get-config-value.sh` への言及は「本モジュールの外で使われる別経路」という対比のための脚注であって Bash 実行指示ではない (Step 3 の編集後も同様)。新しい Bash 呼び出しを導入しないため、10 件の読者いずれについても `allowed-tools` 追加は不要と判断した。
- **設計判断 (対応方針案 A を採用)**: Issue 本文の対応方針案 A (仕様テーブル + テーブル駆動テスト) を採用し、B (最小 YAML サブセットパーサへの一本化) と C (fail-closed 化) は採用しなかった。
  - B を採用しなかった理由: #1055 の Spec Notes (`docs/spec/issue-1055-config-nested-key-silent-fail.md`) が既に「本リポジトリを含む既知の `.wholework.yml` 実例は全て block format を使用しており、2 階層以上のネストや inline hash format への対応が必要な実例は存在しない」と結論づけている。この前提は今回のコードベース調査でも覆らなかった: `get-config-value.sh` の実呼び出し箇所は 21 件 (scope: `grep -rn '"\$SCRIPT_DIR/get-config-value\.sh"\|"\${SCRIPT_DIR}/get-config-value\.sh"\|\$("\$script_dir/get-config-value\.sh"' scripts/ --include="*.sh" | wc -l`) あるが、いずれも flat キーまたは単一階層 nested キーのみを渡している。機能的なギャップが存在しない以上、パーサ書き換えのリスクとコストに見合わない。
  - C を採用しなかった理由: 21 件の呼び出し元の多くは `2>/dev/null || echo <fallback>` のように非ゼロ終了コードを「失敗として握りつぶし fallback 値を使う」形で書かれている。fail-closed 化 (非対応形状に対して明示的にエラーを返す) は、これらの呼び出し元にとって「default 値」ではなく「fallback 値」が返ることを意味し、意図しない挙動変化を広範囲に及ぼす可能性がある。本 Issue の Purpose (対応/非対応の境界を単一箇所に明示し、次の拡張要求に備える) は A 単独で達成でき、C のリスクを取る理由がない。
- **`scripts/get-auto-session-report.sh` の awk 実装について (スコープ外)**: 同スクリプト L82-95 は `recoveries-auto-fire.threshold` を `get-config-value.sh` 経由ではなく独自の awk で読んでいる。コメント (L82) には「get-config-value.sh lacks nested key support」とあるが、`git blame` で確認したところこの awk 実装は 2026-06-27 追加であり、`get-config-value.sh` の単一階層 nested キー対応 (#1055) は 2026-07-31 マージのため、実装当時のコメントは正しかった。現在は `get-config-value.sh recoveries-auto-fire.threshold <default>` 経由でも同じ値が取得できるはずだが未検証。本 Issue は入力形状の仕様整理が目的でありこの awk 実装の置き換えはスコープ外とするが、将来の cleanup 候補として記録する。
- **inline hash format をベア (ドット無し) セクションキーで照会した場合**: 例えば `capabilities: { workflow: true }` に対して `get-config-value.sh capabilities default` (ドット無し) を呼ぶと、flat キー一致ループが `{ workflow: true }` という生文字列をそのまま返す (default にはならない)。Step 1 の表は「`section.key` のドット表記で照会した場合」を対象としており、このベアセクションキー照会の挙動は対象外とする。現在のコードベースに `capabilities` のようなベアセクションキーを照会する呼び出しは存在しない (`grep -rn "get-config-value.sh capabilities\b" scripts/ modules/ skills/` で確認、ドット付き呼び出しのみ) ため実害はなく、表への追加行は不要と判断した。

## Consumed Comments

- saito (MEMBER, first-class) — 2026-08-10T18:29:03Z — `/issue` フェーズの Issue Retrospective コメント。Background の事実記述 (行指向パース実装、キー文字種制限) をコードベースと照合し一致を確認 (警告なし)。Post-merge AC の文言を Option A 前提から approach-agnostic な表現へ自動解決した経緯を記録。Pre-merge AC / verify command は Size M (PR route) の規約に適合しており変更不要と判断、との記載。本 Spec の設計判断に対する新たな指示は含まれない。 https://github.com/saitoco/wholework/issues/1124#issuecomment-5244328957

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps を上から順に実施し、逸脱なし

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — review-light エージェントによる Spec 乖離観点の確認で、Implementation Steps 1-4 が上から順に実装されており逸脱なし。ヘッダー表の8行は実際のパースロジック (`DOT_COUNT` 単一ドット fallback ゲート、`SECTION_INDENT` による grandchild-indent ガード、セクションヘッダーのインラインコメント正規表現) と完全一致していることを確認した。

### Recurring issues

Nothing to note — review-bug 相当の観点も含め MUST/SHOULD/CONSIDER いずれも検出なし。

### Acceptance criteria verification difficulty

Nothing to note — Pre-merge AC 4件は rubric 2件・command 1件・github_check 1件のいずれも決定論的に検証でき、UNCERTAIN は発生しなかった。AC4 (`github_check "gh pr checks" "Run bats tests"`) は Step 9 の CI 全ジョブ SUCCESS 確認で解決し、Phase Handoff に記録された「/review/CI で解決される」という見立てどおりだった。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- MUST issue が0件だったため Step 12 (Issue Resolution and Fixes) は実施なし。修正コミットは発生していない
- Step 7 (External Review Integration) は `.wholework.yml` に copilot-review/claude-code-review/coderabbit-review いずれも未設定のため全面スキップ
- Base branch conflict pre-check (`git merge-tree`) は `changed in both` 該当なし。main 側との競合コンテキストなし

### Deferred Items
- Spec Notes に記録済みの 2 件のスコープ外事項 (`get-auto-session-report.sh` の awk 実装、inline hash format のベアセクションキー照会) は本 Issue のスコープ外のまま据え置き。将来の cleanup 候補として Spec に記録済み (code phase から継続)

### Notes for Next Phase
- Pre-merge AC 1-4 すべて `[x]` チェック済み。`/merge 1341` は pre-merge AC gate をブロックなく通過できる見込み
- Post-merge AC (opportunistic) は据え置きのまま。次に `get-config-value.sh` へ入力形状の拡張要求が来た際に単一箇所への追記とテスト追加だけで対応できるかを `/verify` で確認する
