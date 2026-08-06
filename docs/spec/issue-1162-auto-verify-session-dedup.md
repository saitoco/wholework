# Issue #1162: auto: observation scan の dispatch からセッション内 verify 済み Issue を除外

## Overview

`/auto` の Event-based observation scan (`observation-trigger.sh --event auto-run` → `Skill(wholework:verify)` の逐次 dispatch) が、同一 `/auto` セッション内で既に `/verify` を実行した Issue を再 dispatch してしまう問題を修正する。実測 (2026-08-04 セッション `73536-1785868487`) では、`/auto 1150` 完了時の observation scan で 5 Issue (#984 / #995 / #1009 / #1035 / #1037) が dispatch され全件 SKIPPED、直後の `/auto --batch 1157 1158 1159` 完了時の observation scan で同一の 5 件が再度 dispatch 対象に選出された。この 2 回目の選出時点で 5 件の前提状態に変化はなく、`/verify` のフルシーケンス (worktree 作成 → 設定読み込み → コメント消費 → AC 再検証 → 結果コメント投稿 → retrospective 判定 → worktree merge/push/破棄) が丸ごと空費された。

対応方針は Issue 本文の候補 A (`.tmp/auto-events.jsonl` の当該 `session_id` に `phase_start`/`phase_complete` (`phase=verify`) が記録されている Issue を dispatch 対象から除外) を採用する。判断根拠は Notes を参照。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: `/issue` フェーズの Issue Retrospective。候補 A ( セッション内 verify 済みリストによる除外 ) は `modules/event-emission.md` が既に `/verify` から `phase_start`/`phase_complete` (`phase=verify`, `session_id` 付き) を `auto-events.jsonl` に emit していることを確認済みで、新規記録機構なしに実現可能と判断した旨を記録。post-merge AC の `session=next` 付与についても言及 ( 本 Spec は Issue 本文に既に反映済みの内容として扱う ) / URL: https://github.com/saitoco/wholework/issues/1162#issuecomment-5202874766

## Changed Files

- `scripts/filter-session-verified-issues.sh`: 新規ファイル。候補 Issue 番号 (標準入力、1 行 1 番号) を受け取り、`.tmp/auto-events.jsonl` ( `$AUTO_EVENTS_LOG` で上書き可 ) の中から、現在の `/auto` セッション (`$AUTO_SESSION_ID` env var、無ければ `.tmp/auto-session-current` ポインタファイル ) に対して `phase=verify` の `phase_start`/`phase_complete` イベントが記録済みの Issue 番号を除外して標準出力へ返す。セッション ID が解決できない、または `.tmp/auto-events.jsonl` が存在しない場合は fail-open ( 候補をそのまま出力し、stderr に warning ) とする — 本フィルタが observation scan 自体をブロックしてはならないため。bash 3.2+ 互換 ( macOS system bash )、`mapfile` 不使用。
- `tests/filter-session-verified-issues.bats`: 新規ファイル。`WHOLEWORK_SCRIPT_DIR`/一時ディレクトリを使い、(a) 対象セッションの `phase=verify` イベントを持つ Issue が除外されること、(b) 該当イベントを持たない Issue は除外されないこと ( negative case )、(c) セッション ID / イベントログが解決できない場合に fail-open で候補がそのまま通過することを検証する。
- `skills/auto/SKILL.md`: (1) frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/filter-session-verified-issues.sh:*` を追加。(2) 単一 Issue 経路の Event-based observation scan 節 (`**Event-based observation scan (auto-run event, runs after Completion Report regardless of success/failure):**` 直後の L2/L3 箇条書き) に、`$NUMBER` 除外の**前段**としてセッション内 verify 済み除外の手順を追加。(3) Batch Completion Report の Event-based observation scan 節 (`**Event-based observation scan (batch, best-effort):**` 直後の L2/L3 箇条書き) に、`BATCH_LIST` 除外の**前段**として同様の手順を追加。
- `modules/observation-trigger.md`: `## scripts/observation-trigger.sh` 節の "Who invokes `/verify`" 箇条書き ( "LLM-session emitters (`/auto`, `/review`) capture stdout and..." の段落 ) に、`/auto` の dispatch ステップが `OBSERVATION_MATCHES` を `filter-session-verified-issues.sh` へ通す新フィルタの説明と、このフィルタは `/auto` 側の SKILL.md dispatch ステップにのみ適用され `observation-trigger.sh` 自体 ( および `/review` からの呼び出し ) は変更しない旨のスコープ境界を追記する。
- `docs/structure.md`: Directory Layout の `scripts/` file count コメントを `(74 files)` → `(75 files)` に更新。Key Files > Scripts > "Project utilities:" リストに `scripts/filter-session-verified-issues.sh` のエントリを `observation-trigger.sh` / `opportunistic-search.sh` の近くに追加。
- `docs/ja/structure.md`: `docs/translation-workflow.md` の Sync Procedure に従い、上記 `docs/structure.md` の変更をミラー。`（74 ファイル）` → `（75 ファイル）`、Scripts リストへ日本語説明で新規スクリプトのエントリを追加。
- `docs/guide/customization.md` / `docs/ja/guide/customization.md`: [Steering Docs sync candidate] `observation-dispatch-threshold` の説明行が `observation-trigger.sh` の挙動 ( cap・冪等性ガード ) のみを記述しており、本 Issue で追加する新フィルタ ( `filter-session-verified-issues.sh` ) はこの説明と矛盾しないと判断した ( `observation-trigger.sh` 自体は変更しないため )。/code フェーズで最終確認し、矛盾がなければ変更不要。

## Implementation Steps

1. `scripts/filter-session-verified-issues.sh` を新規作成する。標準入力から候補 Issue 番号を読み取り、空行を無視して集合を作る。`SESSION_ID` を `${AUTO_SESSION_ID:-}` → 空なら `.tmp/auto-session-current` の順で解決する ( `scripts/collect-run-facts.sh` の解決順に合わせる )。`EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"`。`SESSION_ID` が空、または `EVENTS_LOG` が存在しない場合は候補をそのまま標準出力へ ( fail-open、stderr に warning )。それ以外は `jq -r --arg sid "$SESSION_ID" 'select(.session_id == $sid and .phase == "verify" and (.event == "phase_start" or .event == "phase_complete")) | .issue' "$EVENTS_LOG" | sort -un` で除外集合を作り、候補から差分を取って標準出力へ ( 昇順を維持 )。常に exit 0 ( best-effort )。(→ 受入条件 1)
2. `tests/filter-session-verified-issues.bats` を新規作成する ( after 1 )。`tests/observation-trigger.bats` の `setup()` パターン ( `BATS_TEST_TMPDIR` 配下にモック/フィクスチャを置く ) を参考に、`.tmp/auto-events.jsonl` 相当のフィクスチャ JSONL ( `session_id`/`phase`/`event`/`issue` フィールドを持つ行 ) を用意し、`AUTO_SESSION_ID`/`AUTO_EVENTS_LOG` を export して以下を検証する: (a) 対象セッションの `phase=verify` イベント (`phase_start` または `phase_complete`) を持つ Issue が出力から除外される、(b) イベントを持たない Issue は出力にそのまま残る ( negative case )、(c) `AUTO_SESSION_ID` 未設定かつ `.tmp/auto-session-current` も存在しない場合、または `AUTO_EVENTS_LOG` が存在しない場合に候補がそのまま出力される ( fail-open )。(→ 受入条件 4)
3. `skills/auto/SKILL.md` を更新する ( after 1 )。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/filter-session-verified-issues.sh:*` を追加。単一 Issue 経路の L2/L3 箇条書きで、`exclude \`$NUMBER\`... from \`OBSERVATION_MATCHES\`` の直前に「`printf '%s\n' "$OBSERVATION_MATCHES" | "${CLAUDE_PLUGIN_ROOT}/scripts/filter-session-verified-issues.sh"` で `OBSERVATION_MATCHES` をフィルタし、このセッションで既に `phase=verify` イベントが記録済みの Issue を除外する」という手順を追加し、以降は「the filtered result」を対象に `$NUMBER` 除外・cap 適用を行うよう文言を調整する。deferred メッセージの `M` の定義を「total remaining after session-verified and `$NUMBER` exclusion」に更新する。Batch Completion Report の L2/L3 箇条書きにも同様の追加を行い ( `BATCH_LIST` 除外の前段 )、`M` の定義を「total remaining after session-verified and `BATCH_LIST` exclusion」に更新する。(→ 受入条件 3)
4. `modules/observation-trigger.md` を更新する ( after 1, parallel with 3 )。"Who invokes `/verify`" 箇条書きの LLM-session emitters の説明に、新フィルタ ( `filter-session-verified-issues.sh` ) の追記と、このフィルタは `/auto` の SKILL.md dispatch ステップにのみ組み込まれ `observation-trigger.sh` 自身の「stateless, rolling coverage」契約 ( 既存の Notes 記載 ) は変更されないこと、および `/review` からの呼び出しはスコープ外であることを明記する。(→ 受入条件 1, 受入条件 2 の根拠可視化)
5. `docs/structure.md` と `docs/ja/structure.md` を同期する ( after 1, parallel with 3, 4 )。両ファイルの `scripts/` file count コメントを 74 → 75 に更新し、Scripts リスト ( Project utilities セクション、`observation-trigger.sh`/`opportunistic-search.sh` 付近 ) に新規スクリプトのエントリを追加する ( ja 版は日本語で記述、`docs/translation-workflow.md` の Sync Procedure に従う )。あわせて `docs/guide/customization.md`/`docs/ja/guide/customization.md` の `observation-dispatch-threshold` 説明行が新フィルタと矛盾しないか確認する ( Changed Files 参照、Spec 時点の判断は「変更不要」だが最終判断は本ステップで行う )。(→ ドキュメント同期)

## Verification

### Pre-merge

- <!-- verify: rubric "同一 /auto セッション内で既に /verify を実行した Issue を observation scan の dispatch 対象から除外する仕組みが実装されている。除外判定の根拠となるデータソース (auto-events.jsonl の session_id 付き verify イベント等) が実装から確認できる" --> セッション内 verify 済み Issue の除外が実装されている
- <!-- verify: rubric "除外を解除する条件 (前回 verify 以降の状態変化を検知した場合に再評価する等) が実装されているか、または一律除外とする判断根拠が Spec に記録されている" --> 除外解除条件が実装されているか、一律除外の根拠が記録されている
- <!-- verify: rubric "skills/auto/SKILL.md の Event-based observation scan 節 (単一 Issue 経路と Batch Completion Report 経路の両方) に、セッション内重複除外の手順が反映されている。片方だけの更新になっていないことが確認できる" --> 単一 Issue 経路と batch 経路の両方が更新されている
- <!-- verify: rubric "tests/ 配下に、同一セッションで verify 済みの Issue が除外されること・未 verify の Issue は除外されないこと (negative case) の 2 経路を検証するテストが存在する" --> 2 経路を検証するテストが追加されている
- <!-- verify: command "bats tests/" --> テストスイート全件が PASS する

### Post-merge

- 1 セッション内で `/auto` を 2 回以上実行し、2 回目の observation scan が 1 回目で verify 済みの Issue を dispatch しないことを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### 候補選定の判断根拠 ( 一律除外を採用 )

Issue 本文の 4 候補のうち **候補 A ( セッション内 verify 済みリストによる除外、一律除外 )** のみを本 Spec のスコープとする。

- **候補 A を採用する理由**: `modules/event-emission.md` により `/verify` は `phase_start`/`phase_complete` (`phase=verify`, `session_id` 付き) を既に `.tmp/auto-events.jsonl` へ emit しており ( 新規記録機構が不要 )、実測インシデントの 5 件はいずれも 2 回の dispatch 間で状態変化が起きていない ( Issue 本文 Background 参照 )。最小変更で実測コストを解消できる。
- **候補 B ( 状態変化があれば除外解除 ) を採用しない理由**: Issue 本文が自ら「精度は上がるが判定コストが増える」と評価しており、実測 5 件のいずれにも状態変化がなかったため、現時点で判定コストに見合う効果が確認できない。将来、除外により見逃しが実測された場合に候補 B への拡張を検討する。
- **候補 C ( SKIPPED 理由の記録・参照 ) を採用しない理由**: Issue 本文が「実装量は最も大きい」と評価しており、Size M の light spec の範囲を超える。`#1118` の静的条件宣言 ( `when=` gate ) との接続は将来の拡張余地として残す。
- **候補 D ( oldest-first 順序見直し ) を採用しない理由**: 候補 A/B/C と直交する独立した改善であり、本 Issue の「同一セッション内の重複 dispatch」という問題を単独で解決しない。Issue 本文も「組み合わせ可能」と位置づけており、必要になった時点で別 Issue として起票する。

### スコープ境界 ( `/review` は対象外 )

`observation-trigger.sh` は `/auto` に加え `/review` からも呼び出されるが ( `modules/observation-trigger.md` Emitter Lookup Table 参照 )、`/review` は 1 Issue につき 1 回しか実行されず、本 Issue が扱う「同一 `/auto` セッション内での複数回 dispatch」( 単一 Issue 経路の 2 回目実行、または batch 内の複数 Issue 完了時の再スキャン ) には該当しない。したがって新フィルタは `skills/auto/SKILL.md` の dispatch ステップにのみ組み込み、`observation-trigger.sh` 自体は変更しない ( 既存の「stateless, rolling coverage」契約を維持し、`/review` 側の挙動に影響を与えない )。

### 括弧の表記

本 Spec 内の日本語文中の括弧は半角 `()` を使用している ( ユーザーのグローバル規約に準拠 )。ただし `docs/ja/structure.md` は既存ファイル全体で全角 `（）` を一貫して使用しているため、Implementation Steps 5 での編集はその既存の表記規約に合わせる ( 全角を維持 )。

## Code Retrospective

### Deviations from Design

N/A ( Implementation Steps 1–5 を設計通りに実装した。逸脱なし )

### Design Gaps/Ambiguities

- `scripts/filter-session-verified-issues.sh` の実装時、Spec 記載の `comm -23` による集合差分は数値の桁数が異なる Issue 番号 ( 例: `9` と `84` と `995` ) に対して意図通りに動作しないことが判明した。`comm` は入力がロケール上の辞書順にソートされていることを前提とするが、`sort -un` は数値順であり両者は一致しない ( 例: 辞書順では `"1035" < "84" < "9" < "995"` )。`comm` の代わりに `grep -Fxq` による行単位の集合差分ループに置き換えて実装した。Spec 自体は疑似コードとしての `jq | sort -un` 部分の記述であり、`comm` は Code フェーズでの実装選択だったため Spec の逸脱ではないが、同種の集合差分を扱う将来のスクリプトで同じ罠を踏まないよう記録する。

### Rework

N/A ( 上記の `comm` → `grep -Fxq` の置き換えは、シェル上でのテスト実行中に発見し実装段階で解決したため、コミット済みコードのやり直しは発生していない )

## Phase Handoff

<!-- phase: merge -->

### Key Decisions

- Pre-merge AC 5 件は全てチェック済みの状態でゲートを通過し、PR #1204 を squash merge した ( mergeable=true, ci_status=success, review_status=approved )
- マージ実行時、旧 review フェーズの残留 worktree ( `review+pr-1204`、ブランチ `worktree-code+issue-1162` を占有 ) がローカルブランチ削除をブロックしたため、worktree の unlock/remove とローカル・リモートブランチの削除を追加で実施した

### Deferred Items

- 候補 B/C/D は Code フェーズの Deferred Items から変更なし ( 将来の別 Issue 候補 )
- Post-merge AC ( `session=next` ) は `/auto` を 2 回以上実行する実セッションでの観察が必要。本 merge フェーズでは検証不可

### Notes for Next Phase

- verify フェーズでは Post-merge AC ( 1 セッション内で `/auto` を 2 回以上実行し、2 回目の observation scan が 1 回目で verify 済みの Issue を dispatch しないことを観察 ) が `session=next` 指定のため、次回以降の `/auto` 実行セッションでの実観察が必要
- レビュー完了後に review worktree を都度クリーンアップできていない運用ギャップが見つかった ( 本件は merge フェーズで応急対応済みだが、根本原因は未調査 )
