# Issue #1389: auto: manual recovery 時に再利用 worktree を origin から再フェッチしてから commit を構築

## Issue Retrospective

### 判断根拠

- 曖昧性検出: Background / Purpose / 対応方針 (案) が既に具体的 (対象ファイル・セクション・確認手順まで明記) で、AC も rubric / file_contains で明確に verify command 済みだったため、追加の確認事項は検出されなかった (自動解決 0 件)。
- AC 変更: Post-merge の observation タグ (`<!-- verify-type: observation event=auto-run -->`) に `session=next` を追加した。本 Issue は `skills/auto/SKILL.md` の Manual recovery hand-off セクション変更を対象とするため (`modules/verify-classifier.md` § observation Type: Event Values and Syntax)、変更後のスキル本文は今回のパイプラインを処理中の会話セッションでは読み込まれず、次回の `/auto` 実行 (別セッション) で初めて反映される。`scripts/check-skill-change-observation-ac.sh` の検出 (exit 2) に基づき機械的に付与した。
- その他ポリシー判断: なし (方針は Issue 本文の「対応方針 (案)」で既に確定していたため踏襲)。

### Consumed Comments

No new comments since last phase.

## Consumed Comments
No new comments since last phase.
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1389#issuecomment-5311304038
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5313205649
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5327742015
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5341256649
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5354389932
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5369706141
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5378429156
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5384002143
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5579816424
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5653269834
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5957365664
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-5978132998
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1389#issuecomment-6073961796
