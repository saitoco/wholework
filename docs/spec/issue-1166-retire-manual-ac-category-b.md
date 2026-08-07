# Issue #1166: verify: manual AC 区分 B (別 repo 6 件) を retire または downstream へ移管

## Overview

親 Issue #1158 (`phase/verify` に滞留する manual AC 79 件の再型付け・retire) の sub-issue。`docs/stats/2026-08-05.md` Section 10 で区分 B (別 repo 依存、6 件) に分類された以下の Issue について、Post-merge の手動確認 AC を retire (条件取り下げ + `phase/done` 遷移) または downstream リポジトリへの移管のいずれかで解消する。

対象: #1061 #1044 #1042 #1041 #962 #508

いずれも Pre-merge AC は 100% チェック済みで実装は既に main にマージ済み。残る Post-merge の手動確認のみが downstream (`saitoco/tofas` 等) の実環境を要求しており、upstream の本リポジトリからは原理的に、または実務上不釣り合いなコストなしには再現できない。

## Changed Files

なし (operate route — リポジトリ内ファイルの変更を伴わない。対象 6 Issue への GitHub Issue コメント投稿とラベル遷移のみで完結する)

## Implementation Steps

1. 対象 6 Issue (#1061 #1044 #1042 #1041 #962 #508) それぞれに retire 決定コメントを投稿し、`phase/verify` → `phase/done` のラベル遷移を行う (→ acceptance criteria A, C)。各 Issue の判断根拠は以下の表のとおり:

   | Issue | Pre-merge AC | 判断 | 根拠 |
   |---|---|---|---|
   | #1061 | 10/10 チェック済み (`tests/size-workflow-table.bats` の ALWAYS_PR Override 専用テストを含む) | retire | 実装の正しさは pre-merge の bats テストで機械的に担保済み。Post-merge AC は本リポジトリでも `always-pr: true` を一時設定すれば自己完結で再現可能だが、使い捨ての検証用 Issue 作成を要し、既にテスト済みのロジックを再確認するだけの費用対効果に見合わない |
   | #1044 | 2/2 チェック済み (skip gate 挙動を直接検証する bats テストを含む) | retire | gate ロジックは bats テストで直接カバー済み。downstream (tofas) の実環境再確認は同じ gate を実トラフィックで再検証するのみで新たな正しさのシグナルを追加しない。wholework 内で再現するには config フラグ 1 つのために実 Issue へ `/auto --batch` を実行する必要があり、リスクに見合わない |
   | #1042 | 2/2 チェック済み (bats テストを含む) | retire | #1044 と同根の修正 (同一 root cause クラスの姉妹 Issue)。同じ根拠が適用される |
   | #1041 | 4/4 チェック済み (rubric 検証済みの設計 + `/merge`・`/verify` 双方への適用が委譲構造で保証される確認を含む) | retire | メカニズム (Deferred Items と Issue AC の突き合わせ) は実装済みかつ pre-merge で設計検証済み。out-of-band タイミング (review 完了後・merge 前に AC を書き換える) を意図的に再現するのは、得られる検証価値に対して不自然なセットアップコストが大きい |
   | #962 | 6/6 チェック済み (対象 5 ファイルそれぞれで `git rev-parse --show-toplevel` の存在を機械的に確認する grep 検証 + 横断確認 rubric) | retire | 修正コードの存在は pre-merge grep で機械的に確認済み。このバグは wholework がプラグインとして「別のホストリポジトリ」から呼び出された場合にのみ発現するため、wholework 自身の設定操作では再現不可能 (真に別リポジトリを要する) |
   | #508 | 4/4 チェック済み (`file_exists` + ロジック grep/rubric) | retire | CLI 実装は pre-merge で網羅的に確認済み。Post-merge の確認は実機 API 統合 (IBKR 等) を伴う Issue が 2 件以上必要だが、wholework 自体はそのようなドメインの Issue を持たない。downstream 固有の運用確認であり、upstream 側の正しさとは独立 |

   各コメントは `scripts/gh-issue-comment.sh` (Write ツールで `.tmp/retire-comment-<N>.md` を作成 → 投稿 → 削除) で投稿する。コメント本文には次を含める: (a) 「Retire 決定」の見出し、(b) 上表該当セルの根拠、(c) 起点となった #1166 への参照。投稿後、`scripts/gh-label-transition.sh <N> done` を実行して `phase/verify` → `phase/done` に遷移する。

2. downstream への移管は 0 件 (6 件すべてが retire) であることと、その判断根拠 (全件で Pre-merge AC が完全にチェック済みであり、追加の正しさのシグナルを得るための移管が不要と判断した) を明記した `## Execution Log` コメントを Issue #1166 自身 (本 Issue) に投稿する (→ acceptance criteria A, B, C)。フォーマットは `docs/tech.md` の operate route 節および `skills/code/SKILL.md` の「Operate Route: Execution Log」に従い、1 行目に `<!-- wholework-event: type=execution-log phase=code issue=1166 -->` を付与する。

## Verification

### Pre-merge

- <!-- verify: rubric "区分 B の 6 件すべてについて、retire (条件取り下げ + phase/done 遷移) または downstream への移管のいずれかが実施され、判断根拠が Issue 単位で記録されている" --> 6 件すべてが retire または移管されている
- <!-- verify: rubric "downstream へ移管した Issue がある場合、移管先の Issue 番号またはリポジトリが記録されている" --> 移管先が記録されている
- <!-- verify: rubric "retire した Issue について、実装の正しさが Pre-merge AC やテストで担保されている旨の確認結果が記録されている" --> retire の妥当性が確認されている

### Post-merge

- 移行完了後の `/audit stats --retention` で、phase/verify の Manual waiting 件数が移行前 (79 件) から 6 件減少していることを確認する

## Notes

- **Issue body との齟齬 (SPEC_DEPTH=light、Notes 記録のみ)**: #1166 の Purpose は区分 B の 6 件すべてが「downstream での確認を要求しており、upstream からは原理的に観測不能」という前提に立つが、調査の結果 #1061 の Post-merge AC は実際には本リポジトリで `always-pr: true` を一時設定すれば自己完結で再現可能であり、厳密には「原理的に観測不能」ではないことが判明した。この 1 件についても retire を選んだ理由は、pre-merge の bats テストで実装の正しさが既に機械的に担保されており、再現コスト (使い捨て Issue 作成 + 一時設定変更) に見合う追加の検証価値がないと判断したため (Implementation Steps の表を参照)。
- 対象 6 Issue はいずれも GitHub 上で CLOSED 済み (実装は main にマージ済み) だが `phase/verify` ラベルを保持している。`scripts/gh-label-transition.sh` はラベルのみを操作し Issue の open/closed 状態を変更しないため、本対応後も 6 件は CLOSED のまま `phase/done` ラベルに置き換わる。
- 本 Issue 自体は Task 種別・Size M。`docs/stats/2026-08-05.md` Section 10 の分類および親 #1158 の記載により、対象 6 Issue への処理は operate route (リポジトリファイル変更なしの外部操作のみ) を想定している。
- ドキュメント更新は不要と判断した: 本 Issue は既存の retire/operate route パターンを 6 件の具体的な Issue に適用する一回限りの運用作業であり、`docs/workflow.md` 等のワークフロー説明や Steering Documents に影響する変更 (新しい仕組みの導入、ディレクトリ構成変更など) を含まない (`modules/doc-checker.md` Impact Determination Criteria のいずれにも該当しない)。

## Consumed Comments
No new comments since last phase.
