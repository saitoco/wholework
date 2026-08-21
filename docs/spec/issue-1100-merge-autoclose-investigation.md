# Issue #1100: merge: closes キーワードによる Issue 自動クローズが発火しないケースを調査する

## Overview

`/merge` 実行時、PR body の `closes #<downstream-issue>` による GitHub の Issue 自動クローズが発火せず、`/merge` Step 6 (Verify Issue State) のフォールバック (`gh issue close`) で閉じられるケースが連続 2 件観測された。いずれも squash merge・base branch=default branch・PR body に `closes #<downstream-issue>` を含む、という同一条件。フォールバック自体は正しく機能しており実害はないが、原因は未特定。本 Spec は原因の切り分けと、切り分け結果に基づく対応の設計を行う (緊急度は低い)。

## Changed Files

- `skills/merge/SKILL.md`: Step 6 (Verify Issue State) に短いリトライ / バックオフを追加。既存のフォールバック (`gh issue close`) はそのまま維持し、その手前に 2 回までの再チェック (5 秒 → 10 秒待機) を挟む
- [Steering Docs sync candidate] keyword "merge" skipped: matched 1121 files (no discriminating power)
- (検討済み・変更不要) `docs/workflow.md` § "When Auto-close is Disabled" (L253-269): `/verify` が担当する「リポジトリ設定が恒久的に無効」ケースの記述であり、`/merge` Step 6 (今回リトライを追加する箇所) とは別の経路を説明している。今回の変更はこの記述と矛盾しないため更新不要と判断 (Read で内容確認済み)

## Implementation Steps

1. `skills/merge/SKILL.md` Step 6 を編集し、現在の「不一致検出 → 即フォールバック」の間に、GitHub 側の非同期処理 (closes 反映の伝播遅延) を考慮した短いリトライ (5 秒待機して再チェック、なお不一致なら 10 秒待機して再チェック) を挿入する。いずれかのリトライで一致すればフォールバックを適用せず Step 7 に進む。両方とも不一致の場合のみ既存のフォールバックに進む。`scripts/gh-pr-merge-status.sh` の "GitHub metadata sync delay" リトライパターン (`RETRY_DELAYS=(30 60)`、コメントで「本物の失敗ではなく同期遅延」と明記) と同じ設計思想を踏襲する (→ AC2)
2. 原因切り分けの結果 (下記 Notes 参照) を本 Spec の Notes セクションに記録し、Step 15 の Issue コメント (Design Complete) にも要約を含める (→ AC1)

## Verification

### Pre-merge

- <!-- verify: rubric "自動クローズ未発火の原因が (a) 状態検証のタイミング、(b) squash merge 時の commit message 整形、(c) その他 のいずれか、または複数の組み合わせであるか切り分けた結果が Issue コメントまたは Spec に記録されている" --> 原因の切り分け結果が記録されている
- <!-- verify: rubric "切り分け結果に基づく対応 (merge skill の状態検証へのリトライ追加、commit message への closes 参照保持、または対応不要の判断とその根拠) が実装またはドキュメント化されている" --> 切り分け結果に基づく対応が入っている

### Post-merge

- 対応後の `/merge` 実行で、Issue 状態検証のフォールバックに依存せず自動クローズが発火することを確認 <!-- verify-type: opportunistic -->

## Notes

### 原因の切り分け結果 (AC1)

GitHub 公式ドキュメント・`gh` cli/cli や GitHub Community Discussions の既知報告・本リポジトリの実設定を突き合わせた結果は以下の通り (非対話モードのため、この切り分け自体を Uncertainty 確認プロセスの代わりとして本セクションに記録する)。

- **(a) 状態検証のタイミング + (c) その他 (API 伝播遅延) — 主要因として support**: GitHub 公式ドキュメント (Linking a pull request to an issue) によれば、closing keyword は PR description から解釈され、PR が default branch に対してマージされたときに issue をクローズする。一方 `gh pr merge` はマージ API 呼び出しが成功を返した後も GitHub 側の後続処理 (issue オートクローズを含む) が非同期に進行することが `cli/cli` の Issue や GitHub Community Discussions で複数報告されている (eventual consistency)。`/merge` Step 6 は squash merge 直後の状態確認に専用のリトライを持たず、この伝播遅延を吸収できていなかった。2 件とも「稀に発生」というパターンであり、恒久的な設定不備であれば毎回発生するはずなので、タイミング起因という説明と整合する。
- **(b) squash merge 時の commit message 整形 — 主要因からは除外**: 公式ドキュメントによれば closing keyword は PR description (PR body) から解釈され、squash commit 本文の内容には依存しない。本リポジトリの実設定 (`gh api repos/saitoco/wholework` で確認: `squash_merge_commit_message=COMMIT_MESSAGES`、`squash_merge_commit_title=COMMIT_OR_PR_TITLE`) では squash commit 本文に PR body がそのまま転記されないが、これは公式ドキュメントの仕組み (PR body から直接解釈、squash commit 本文とは独立) と矛盾しない。2 件とも base branch=default branch かつ PR body に `closes #<downstream-issue>` を含む前提が満たされていることは Issue 本文に明記されている。
- **リポジトリ設定 "Auto-close issues with merged linked pull requests" が無効という可能性**: この設定は GitHub REST/GraphQL API では公開されておらず (WebSearch で確認)、本セッションから機械的に確認できない。ただし、もしこの設定が無効なら `/merge` Step 6 のフォールバックは (タイミングに関係なく) 毎回発火するはずであり、「連続 2 件」という Issue 本文の記述 (それ以外の大多数のマージでは `closes #N` の自動クローズが成功している含意) と整合しない。恒久的な設定無効の可能性は低いと判断し、対応の優先度は下げる (人手によるスポットチェックは安価な追加確認として推奨するが、今回の対応の前提にはしない)。

参考: `docs/workflow.md` § "When Auto-close is Disabled" (L253-269) は上記の「設定が恒久的に無効」ケースを `/verify` 側の責務として既に文書化している。今回の 2 件は `/merge` Step 6 (異なるフェーズ・異なる経路) で観測されており、上記の理由からこの既存フローとは別の (タイミング起因の) 事象と判断した。

### 対応 (AC2)

(a)/(c) が主要因という判断に基づき、`/merge` Step 6 の状態検証に短いリトライ / バックオフを追加する (Implementation Steps 参照)。既存のフォールバック (`gh issue close`) はそのまま維持し、稀な伝播遅延ケースでフォールバックに依存する頻度を下げることを狙う。リトライ幅 (5 秒 / 10 秒) は `scripts/gh-pr-merge-status.sh` の既存パターンを参考にした暫定値であり、Post-merge 条件の opportunistic 観測で効果が不十分と分かった場合は値を見直す。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: `/issue` フェーズの Issue Retrospective コメント。非対話モードでの 2 件のあいまいさ自動解決 (調査着手タイミングの現状維持判断、AC1 rubric 文言の「単一要因」読み取れる表現の微修正) を記録したもの。本 Spec の設計判断に影響する新規指示は含まれない / URL: https://github.com/saitoco/wholework/issues/1100#issuecomment-5368853136
