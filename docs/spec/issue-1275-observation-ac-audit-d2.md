# Issue #1275: verify: #1164 由来の observation AC 12 行を実査し判定不能分を retire

## Overview

親 Issue #1270 (XL、由来 sub-issue 単位で #1274/#1275/#1276 に 3 分割) の sub-issue。#1164 が区分 D2 (実行シナリオ型) として `verify-type: manual` から `verify-type: observation event=auto-run` へ再型付けした **12 AC 行 / 11 Issue** (#1109 #1106 #1101 #1097 #1031 #954 #529 #515 #511 #486 #446) を対象に、親 #1270 が定める A/B/C/D/E 判定基準 (本 Issue 本文「判定基準」節に verbatim 継承済み) に従って 1 行ずつ「どの event が発火したとき何を根拠に PASS 判定できるか」を実査する。

- **A (判定可能)**: 維持し判定根拠を記録
- **B (条件文の書き換えで判定可能)**: #1251 の規約 (rubric の参照ファイル明示・数値 AC の母集団定義・observation AC の発火見込み明示) に従い書き換え
- **C (event 選択の誤り)**: `event=` を他の有効値に差し替え
- **D (判定不能)**: #1166 方式 (AC 行は編集せず、retire 理由を Issue コメントに記録し `phase/verify` → `phase/done` へ遷移) で retire
- **E (`/verify` 実行時の判定に戻すべき)**: `verify-type: manual` へ差し戻す。装備 (capability) 不足のみが理由の場合は D にせず E とし `capability=<key>` を併記する (#1278 の語彙)

親 Pre-merge AC 1 の baseline 計測 (`docs/reports/observation-ac-audit-summary.md`、2026-08-08、母集団 82 Issue / 85 AC 行) は完了済みであり、本 Issue の着手前提は充足されている。分類結果は `docs/reports/observation-ac-audit-d2.md` に記録する。3 sub-issue の記録ファイルを集約レポートへ統合するのは親 #1270 自身の責務であり、本 Issue のスコープ外。

## Changed Files

- `docs/reports/observation-ac-audit-d2.md`: 新規作成 — 12 AC 行 (11 Issue) の A/B/C/D/E 分類・判断根拠・処理結果を Issue 単位・AC 行単位で記録

対象 11 Issue (#1109 #1106 #1101 #1097 #1031 #954 #529 #515 #511 #486 #446) 自体は GitHub Issue (本文編集・コメント投稿・ラベル遷移) であり、リポジトリファイルではないため本節には含めない。詳細は Implementation Steps を参照。

## Implementation Steps

**AC 番号の対応 (Verification > Pre-merge の記載順)**: AC1 = 12 AC 行の分類・判断根拠の記載、AC2 = 記録ファイルの作成、AC3 = #446/#486 の分類・処理、AC4 = 分類 D の #1166 方式 retire、AC5 = 分類 D retire による `phase/done` 遷移、AC6 = 分類 B/C 変更後のマッチ集合確認。以下の各ステップの `(→ ACn)` はこの番号を指す (本文中で多用する分類ラベル A/B/C/D/E とは別の体系)。

1. 12 AC 行すべて (#1109 #1106 #1101 #1097 #1031 #954 #529 #515 #511 #486 #446 条件 1・条件 2) について、本 Issue 本文「判定基準」節の A/B/C/D/E 基準に従い分類する。各 Issue の `### Post-merge` 節を `gh issue view <N> --json body` で取得し、判定対象の条件文とイベント発火時に参照可能な情報源 (実行事実・リポジトリ状態・GitHub 状態) を突き合わせる。親 #1270 が名指しした #446 (条件 1・条件 2 とも) と #486 は「D と決め打ちしない」(親 Sub-issues 節: いずれも E の候補) — 個別に実査して分類する (→ AC1, AC3 の分類方針を決定)

2. (after 1) 分類 D の AC 行について #1166 方式で retire する: AC 行は編集しない。`.tmp/retire-comment-<N>.md` に retire 理由 (判断根拠・本 Issue #1275 への参照) を書き Write ツールで作成し、`scripts/gh-issue-comment.sh <N> .tmp/retire-comment-<N>.md` で投稿後、一時ファイルを削除する。投稿後、対象 Issue の `### Post-merge` 節に他の未チェック条件が残っていないかを確認する (例: #529 は D2 対象行以外に `verify-type: auto` の条件が既に `[x]` チェック済みのため retire のみで完了、#511 は D2 対象行以外に `verify-type: opportunistic` の未チェック条件が残るため retire だけでは完了しない)。未チェック条件がゼロになった Issue のみ `scripts/gh-label-transition.sh <N> done` で `phase/verify` → `phase/done` へ遷移する (→ AC4, AC5)

3. (after 1, parallel with 2, 4) 分類 B (条件文の書き換え) の AC 行について、対象 Issue 本文を `.tmp/issue-body-<N>.md` に取得し、#1251 の規約 (rubric なら参照ファイルを明示、数値条件なら母集団定義を条件文に含める、observation AC なら発火 event と判定根拠を条件文自身に書く) に従って該当行を書き換える。分類 C (event 選択の誤り) の AC 行は `event=<name>` を有効な 5 値 (`pr-review-full`/`pr-review-light`/`auto-run`/`watchdog-kill`/`fix-cycle`) の中から該当するものへ差し替える (`fix-cycle` は emitter 未実装のため選択候補から除外する)。編集後、`### Pre-merge`/`### Post-merge` 配下が `- [ ]`/`- [x]` 形式のみであることを確認する — `scripts/check-ac-checkbox-format.sh` は `/code` の `allowed-tools` に未登録 (#1165 が同じ制約に遭遇し、allowed-tools への追加をスコープ外とした precedent に倣い、本 Issue でも追加しない) のため、同スクリプトの awk ロジック (`### Pre-merge`/`### Post-merge` 配下で `^- ` かつ `^- \[[ xX]\]` に一致しない行を検出) を再現する `python3` ワンライナー、または目視確認で代替する。確認後 `scripts/gh-issue-edit.sh <N> .tmp/issue-body-<N>.md` で書き戻す (→ AC6)

4. (after 1, parallel with 2, 3) 分類 E (`/verify` 実行時の判定に戻すべき) の AC 行について、対象 Issue 本文を手順 3 と同じ方法で取得・書き換える: `<!-- verify-type: observation event=... -->` を `<!-- verify-type: manual -->` に置き換え、書き戻す。装備 (capability) 不足のみが実行不能の理由である場合は `docs/reports/observation-ac-audit-d2.md` に差し戻し理由と共に `capability=<key>` (#1278 の語彙) を併記する。それ以外は「`/verify` 実行時に何を確認すれば判定できるか」を具体的に記録する (→ AC1 の一部)

5. (after 2, 3, 4) `docs/reports/observation-ac-audit-d2.md` を作成する: 11 Issue × 12 AC 行それぞれについて分類 (A/B/C/D/E)・判断根拠・処理結果 (A: 判定根拠となる情報源、B/C: 変更内容、D: retire 理由と `phase/done` 遷移の有無、E: 差し戻し理由と `/verify` 実行時の確認手順) を記載する。#446/#486 の分類・処理結果を明示する。分類 B/C で書き換えた行は `scripts/opportunistic-search.sh --event <name> --dry-run` を再実行し、書き換え後のマッチ集合への含有 (または意図的な除外) を個別に確認して記録する。`docs/reports/observation-ac-audit-summary.md` の集約テーブルへの統合は親 #1270 が担うため本 Issue では行わない旨を明記する (→ AC1, AC2, AC3, AC4, AC5, AC6)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/observation-ac-audit-d2.md に 12 AC 行すべての分類 (A/B/C/D/E) と、A については判定根拠 (どの情報源で PASS/FAIL が決まるか)、B/C については変更内容、D については retire 理由、E については差し戻し理由と /verify 実行時の判定手順が Issue 番号・AC 行単位で記載されている" --> 担当する 12 AC 行すべてについて、A/B/C/D/E の分類と判断根拠が `docs/reports/observation-ac-audit-d2.md` に Issue 単位・AC 行単位で記載されている
- <!-- verify: file_exists "docs/reports/observation-ac-audit-d2.md" --> 記録ファイル `docs/reports/observation-ac-audit-d2.md` が作成されている
- <!-- verify: rubric "docs/reports/observation-ac-audit-d2.md に #446 と #486 の分類結果と処理内容が記載されている" --> 親 Issue が名指しした #446 / #486 の 2 件が A/B/C/D/E のいずれかに分類され処理されている
- <!-- verify: rubric "分類 D と判定した AC 行について、retire 理由が対象 Issue のコメントとして投稿され、かつ対象 Issue 本文の ### Post-merge 節が編集されていないことが docs/reports/observation-ac-audit-d2.md に Issue 単位で記載されている" --> 分類 D の AC 行が #1166 方式で retire され、対象 Issue 本文の `### Post-merge` は編集されていない
- <!-- verify: rubric "retire 完了により未チェック条件がゼロになった Issue が phase/done へ遷移していることが docs/reports/observation-ac-audit-d2.md に Issue 単位で記載され、GitHub 上の実状態と一致している" --> 分類 D の retire により未チェック post-merge 条件が残らなくなった Issue が `phase/done` へ遷移している
- <!-- verify: rubric "条件文を変更した AC について、変更後のマッチ集合への含有が個別に確認され docs/reports/observation-ac-audit-d2.md に記録されている" --> 分類 B/C で条件文を変更した AC 行が、変更後も `opportunistic-search.sh --event <name> --dry-run` のマッチ集合に含まれる (または意図的に外れたことが記録されている)

### Post-merge

なし (効果測定は親 #1270 に集約)

## Notes

- **対象 11 Issue の Post-merge 構成 (実査で判明した事実)**: ほとんどが D2 対象行 1 本のみの単一条件 Issue だが、#529 は D2 対象行に加えて `verify-type: auto` の条件が既に `[x]` チェック済み、#511 は D2 対象行に加えて `verify-type: opportunistic` の未チェック条件が別途残る。Implementation Steps 2 の `phase/done` 遷移判断は「D2 対象行の retire で Post-merge 全体が解消するか」を個別に確認する必要があり、単純な「D 分類なら即遷移」ではない
- **`check-ac-checkbox-format.sh` の allowed-tools 未登録は本 Issue のスコープ外**: 同スクリプトは `/code` の `allowed-tools` に登録されていない (実確認済み)。sibling #1165 (`docs/spec/issue-1165-manual-ac-retype-d3.md` Notes/Tool Dependencies) が同じ制約に遭遇し、「allowed-tools への追加は spec のスコープ外、python3 の同等判定または目視確認で代替する」と判断した precedent に倣う。本 Issue も同じ方針を採る
- **`fix-cycle` イベントは emitter 未実装**: `modules/verify-classifier.md` は `event=` の有効値として 5 値を定義するが、`fix-cycle` は「Not yet implemented — emitter is a follow-up (#650 child Issue)」と明記されている。分類 C で `event=` を差し替える場合、`fix-cycle` は実質的に発火しないため選択候補としない
- **`docs/reports/observation-ac-audit-summary.md` の更新は本 Issue のスコープ外**: 親 #1270 の実行順序 (baseline 計測 → 3 sub-issue 並列実行 → 親が集約) により、集約テーブルへの統合は親 #1270 自身が行う。本 Issue は `docs/reports/observation-ac-audit-d2.md` の作成までを担当する
- **ドキュメント更新は不要と判断した**: `modules/doc-checker.md` の Impact Determination Criteria (ワークフローフェーズ変更・プロジェクト構造変更・skill/agent/module/script の追加変更削除) のいずれにも該当しない。既存の `docs/reports/` ディレクトリ配下への 1 ファイル追加であり、`docs/structure.md` の Directory Layout は既に `reports/` を汎用エントリとして持つため更新不要
- 本 Issue 自体は Task 種別・Size M。`docs/reports/observation-ac-audit-d2.md` という実ファイル変更を伴うため diff-less な operate route ではなく、通常の pr route を想定する

## Consumed Comments

- saito / MEMBER / first-class / triage フェーズの Issue Retrospective (Size=M の判断根拠、Background 表の対象 Issue 件数 13→11 修正の auto-resolve 記録、AC/Post-merge への変更なし) / https://github.com/saitoco/wholework/issues/1275#issuecomment-5226504642
