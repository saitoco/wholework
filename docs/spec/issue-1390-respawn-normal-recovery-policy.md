# Issue #1390: recoveries: respawn を補償層の正常な復旧として扱う運用方針を明文化

## Overview

Symptom `manual-recovery-respawn` が `docs/reports/orchestration-recoveries.md` に 18 件記録され、閾値 (3) を超過している。この症状は #1014 (2026-07-13 起票 → 2026-07-14 CLOSED) で一度対応済みだが、クローズ後も再発が継続している。

本 Issue 起票後に着地した #1146 (external-kill 調査) の結論により、「なぜ respawn が止まらないか」への答えは既に出ている: external kill は harness 側の episodic な background task supervision (H-a) によるもので wholework 側では制御・ローカル検証ともに不可能であり、決着は上流 Issue 待ち。一方、補償層 (親セッションによる respawn) は 17/17 で一度も失敗しておらず、作業ロスは発生していない。

したがって本 Issue のスコープは「恒久対策の検討」から「respawn を補償層による正常な復旧として扱う運用方針の明文化」に絞り込まれている (2026-08-18 Issue 本文改訂)。あわせて、`collect-recovery-candidates.sh` の閾値検出が今後も `manual-recovery-respawn` を繰り返し候補として挙げ続ける扱いをどう判断するかを、本 Spec の調査 (#1014 タイトルリネームによる「起票済み」紐付けの構造的失敗の発見を含む) に基づいて決定する。

## Changed Files

- `modules/orchestration-fallbacks.md`: `external-kill-parent-respawn` エントリを拡張 — Rationale 末尾の記述更新、`### Operational Policy: respawn as expected recovery` 節の新設、`### Threshold Detection Handling` 節の新設

## Implementation Steps

1. `modules/orchestration-fallbacks.md` の `external-kill-parent-respawn` エントリ § Rationale で、最後の箇条書き (`Root cause of the external kill itself remains an open hypothesis...`) を、#1146 の結論 (H-a が最有力仮説、ローカル検証不能、決着は上流 [#76974](https://github.com/anthropics/claude-code/issues/76974) / [#76942](https://github.com/anthropics/claude-code/issues/76942) / [#83814](https://github.com/anthropics/claude-code/issues/83814) 待ち) を反映した英語の記述に置き換え、続けて #1014 クローズ後も respawn が継続している理由の判定 (対応不足でも別原因でもなく、補償層が想定どおり機能している証跡 = 想定通りの動作) を記録する新規箇条書きを追加する (→ acceptance criteria A)
2. Rationale セクション直後 (`## review-pending-not-failure` の直前にある `---` 区切り線の手前) に `### Operational Policy: respawn as expected recovery` 節を英語で新設し、(a) `manual-recovery-respawn` の累積は補償層の作動記録であり障害ではないこと、(b) 作業ロスは発生しないこと (実績 17/17)、(c) 根本原因の解消は上流待ちであり wholework 側の対処対象ではないこと の 3 点を記載する (→ acceptance criteria B。この節が `modules/orchestration-fallbacks.md#external-kill-parent-respawn` に置かれること自体が acceptance criteria C を満たす)
3. Step 2 で追加した `### Operational Policy` 節の直後に `### Threshold Detection Handling` 節を英語で新設し、`collect-recovery-candidates.sh` の閾値検出を当面変更しない (現状維持でも除外でもない「別扱い」) 判断と、その根拠となる 2 つの構造的ギャップ — (i) 「Issue closed = 原因解消」を前提とする除外モデルが `manual-recovery-respawn` には当てはまらないこと、(ii) `_find_known_recoveries_issue()` (`scripts/run-auto-sub.sh`) のタイトル完全一致リンクが、#1014 の 2026-07-14T17:50:15Z のタイトルリネーム (`recoveries: manual-recovery-respawn` → `recoveries: manual-recovery-respawn の再発原因を特定・解消`) 以降サイレントに機能しなくなっている実測結果 (`docs/reports/orchestration-recoveries.md` で 2026-08-07 以降の全エントリが `未起票` になっている) — を記録し、恒久修正 (リネーム耐性のあるリンク機構、または Issue の open/closed に依存しない「許容済み」除外区分の追加) は別 Issue への切り出し候補として記録するに留め、今回は実装しない旨を明記する (→ acceptance criteria D)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/orchestration-fallbacks.md の external-kill-parent-respawn エントリ (またはそこから参照される記載先) に、#1014 のクローズ内容の確認結果と、respawn が継続している理由の判定 (対応不足 / 別原因 / 想定通りの動作のいずれか) が、#1146 の結論を根拠として記録されている" --> `#1014` のクローズ理由と対応内容を確認し、その後も respawn が継続している理由が記録されている。#1146 の結論 (external kill は harness 側の episodic な現象で wholework からは制御不能、補償層は 17/17 で機能) を入力として、「対応不足 / 別原因 / 想定通りの動作」のいずれであるかを明示する
- <!-- verify: rubric "modules/orchestration-fallbacks.md の external-kill-parent-respawn エントリ (またはそこから参照される記載先) に、respawn を補償層による正常な復旧として扱う運用方針が文書化されており、累積が障害ではないこと・作業ロスがないこと・根本原因が上流待ちであることの3点が記載されている" --> respawn を補償層による正常な復旧として扱う運用方針が明文化されている。最低限、(a) `manual-recovery-respawn` の累積は障害ではなく補償層の作動記録であること、(b) 作業ロスは発生しないこと (実績 17/17)、(c) 根本原因の解消は上流待ちであり wholework 側の対処対象ではないこと の 3 点を含む
- <!-- verify: rubric "運用方針の記載先が modules/orchestration-fallbacks.md の external-kill-parent-respawn エントリ、または同等に到達しやすい場所に置かれている" --> 明文化の記載先が、`manual-recovery-respawn` の扱いを調べる人が最初に到達する場所になっている (`modules/orchestration-fallbacks.md#external-kill-parent-respawn` を第一候補とし、別の場所を選ぶ場合はその理由を記録する)
- <!-- verify: rubric "manual-recovery-respawn が閾値検出で繰り返し候補に挙がる扱いについて、現状維持・除外・別扱いのいずれかの判断とその理由が記録されている" --> `collect-recovery-candidates.sh` の閾値検出が `manual-recovery-respawn` を繰り返し候補として挙げ続ける扱いについて、判断が記録されている (現状維持 / 除外 / 別扱い のいずれか + 理由)。実装を伴う場合は別 Issue に切り出してよい

### Post-merge

- 次回 `/verify` Step 15 で `manual-recovery-respawn` が閾値超過の候補として表示された際、明文化された運用方針に従って処理される (再度の Issue 起票が抑制される、または起票された Issue が方針を参照して即座に判断できる) ことを確認

## Consumed Comments

| login | authorAssociation | trust tier | 要旨 | URL |
|-------|-------------------|-----------|------|-----|
| saito | MEMBER | first-class | Triage AC audit: AC1・AC2 の rubric verify command が対象ファイルを明示しておらず、Issue body の Background 記述のみで常時 PASS 判定されうるリスクを指摘。AC3 と同じパターンでファイルパスを明示する修正案を提示 | https://github.com/saitoco/wholework/issues/1390#issuecomment-5326256592 |
| saito | MEMBER | first-class | `/issue` 実行の Issue Retrospective。本文は起票者により改訂済みのため新規曖昧性抽出は未実施。`modules/orchestration-fallbacks.md#external-kill-parent-respawn` の実在確認と、AC3・AC4 が実装を要する正当な差分であることの確認、および上記 triage audit コメントの参照を記録 | https://github.com/saitoco/wholework/issues/1390#issuecomment-5326261576 |

いずれも起票者本人 (MEMBER) による first-class input。1 件目の指摘を受け、`/spec` 実行時に Issue 本文の AC1・AC2 rubric verify command を `modules/orchestration-fallbacks.md` の `external-kill-parent-respawn` エントリを明示的な評価対象とする形に修正済み (本 Spec の Verification セクションは修正後の内容を反映している)。

## Notes

### Autonomous Auto-Resolve Log (non-interactive mode)

- **Issue 本文 AC1・AC2 の rubric verify command にファイルパスを明示** — reason: `/issue` の triage AC audit コメント (first-class, MEMBER) が「Background の既存記述のみで常時 PASS しうる」リスクを具体的な修正案付きで指摘しており、AC3 に既存する「対象ファイル明示」パターンへ揃える低リスクな修正のため、`modules/ambiguity-detector.md` の Non-Interactive Mode Handling 三層方針における High-Stakes Decisions のいずれにも該当しない。Auto-resolve として `/spec` 実行中に Issue 本文を編集し、Spec の Verification には更新後の verify command を verbatim で反映した
  - Other candidates: Issue 本文を変更せず Spec の Notes に懸念のみ記録する案 (却下 — 常時 PASS リスクを実際には低減しないため)

### AC4 判断の根拠 (#1014 タイトルリネーム調査)

`gh api repos/saitoco/wholework/issues/1014/timeline` で `_find_known_recoveries_issue()` (`scripts/run-auto-sub.sh`) の紐付け失敗を実測確認した。

- #1014 は `recoveries: manual-recovery-respawn` という完全一致可能なタイトルで起票されたが、クローズ直前の 2026-07-14T17:50:15Z に `recoveries: manual-recovery-respawn の再発原因を特定・解消` へリネームされている
- `docs/reports/orchestration-recoveries.md` の実データでも、2026-07-29 以前のエントリは `起票済み #1014` だが、2026-08-07 以降の全エントリが `未起票` になっており、リネーム後は紐付けが機能していないことと整合する
- `_search_recoveries_issue()` は `item.get('title', '') == target` という完全一致判定であり、部分一致や Issue 番号ベースの永続的なリンクを持たない。#1390 自身も同じ日本語記述タイトル規約 (`recoveries: respawn を補償層の正常な復旧として扱う運用方針を明文化`) を採用しているため、将来のエントリに対しても同じ理由で `起票済み #1390` へは自動的に紐付かない
- この発見が AC4 の「別扱い」判断 (現状維持でも除外でもなく、構造的ギャップを記録した上で当面は運用方針の明文化で対処する) の直接的根拠である

### allowed-tools impact chain check

`modules/orchestration-fallbacks.md` は `skills/auto/SKILL.md` と `skills/verify/SKILL.md` から読み込まれる (`grep -rl "modules/orchestration-fallbacks\.md" skills/*/SKILL.md` で確認)。本 Issue の追加内容は `collect-recovery-candidates.sh` に言及するが、これは既存の説明的な参照であり、モジュール内から当該スクリプトを新規に呼び出す指示を追加するものではない (実際の呼び出しは `/verify` Step 15 に既存)。したがって新規の `allowed-tools` 追加は不要と判断した。

### Steering Docs sync candidate check

`grep -rl "external-kill-parent-respawn"` を `docs/` `tests/` `scripts/` `modules/` に対して実行し、`docs/structure.md` / `docs/workflow.md` / `docs/tech.md` / `docs/ja/*` / `scripts/detect-external-kill.sh` / `scripts/run-auto-sub.sh` / `docs/reports/external-kill-investigation.md` がヒットすることを確認した。いずれも本エントリの検出メカニズム (Symptom / Fallback Steps) を参照するのみで、本 Issue が更新する Rationale・運用方針・閾値検出方針とは独立した記述のため、更新不要と判断した。`docs/translation-workflow.md` の同期対象は top-level `docs/*.md` に限定されており `modules/` 配下は対象外のため、`docs/ja/` 同期も不要と判断した。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜3 を Spec の記述順どおりに実装した。追加した英語記述の具体的な文言は Spec には書かれていなかったため実装時に起こしたが、これは Spec が意図的に「反映内容」を要約指定し文言化は実装フェーズに委ねる形だったための想定内の作業であり、逸脱ではない

### Design Gaps/Ambiguities
- N/A — Implementation Steps 3 か所とも 1 対 1 で `modules/orchestration-fallbacks.md` の該当箇所に対応しており、曖昧な判断を要する箇所はなかった

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implementation Step 1 の置換対象だった最終箇条書きを、#1146 結論を反映した文へ書き換えると同時に、respawn 継続理由の判定 (想定通りの動作) を新規箇条書きとして追加した — AC1 の rubric が「クローズ内容の確認結果」と「継続理由の判定」の両方を明示的に求めていたため、1 つの箇条書きに詰め込まず 2 つに分けて書いた
- `### Threshold Detection Handling` の記述は、Spec Notes の「AC4 判断の根拠」セクション (#1014 タイトルリネーム調査) をほぼそのまま英訳・再構成する形で書いた — 調査の事実関係は `/spec` フェーズで既に確定していたため、`/code` フェーズでの追加調査は行っていない
- Follow-up Issue は起票しなかった — Spec 本文が「別 Issue への切り出し候補として記録するに留め、今回は実装しない旨を明記する」と明示しており、AC4 の verify command も「判断とその理由が記録されている」ことのみを要求 (起票を必須としていない) ため

### Deferred Items
- 恒久修正 (rename-resistant なリンク機構、または Issue の open/closed に依存しない「許容済み」除外区分の追加) — `### Threshold Detection Handling` に follow-up Issue 候補として記録済み。実装は本 Issue のスコープ外

### Notes for Next Phase
- Pre-merge AC 4 件は全て rubric type — `/review` での再評価時、AC1 の「#1014 クローズ内容の確認結果」が Rationale の新規 2 箇条書き (root cause 確定 + #1014 以降の継続理由判定) に分散して書かれている点に注意 (1 箇所にまとまっていない)
- Post-merge AC (`<!-- verify-type: opportunistic -->`) は次回 `/verify` Step 15 で `manual-recovery-respawn` が閾値超過候補として再度挙がったタイミングで確認される想定 — 本 PR のマージ直後には検証されない
