# Issue #1113: append-consumed-comments: jq エラーの空配列フォールバックを観測可能にする

## Overview

`scripts/append-consumed-comments-section.sh` は `/verify` フェーズの comment consumption 安全網である。同スクリプトは5箇所の jq / `gh --jq` 呼び出しをすべて `2>/dev/null || echo "[]"` で受けており、jq が実行エラーになった場合と「新規コメント0件」の正常系が区別できない。エラーは空配列にフォールバックして exit 0 するため、呼び出し側 (`skills/verify/SKILL.md` Step 4) も安全網が機能していないことを検知できない。本 Issue では、フェイルセーフ性 (エラー時に安全網呼び出し全体を落とさない) を維持したまま、各 jq 呼び出しの失敗を stderr への警告として観測可能にする。

## Reproduction Steps

1. `/spec` または `/code` の post-processor フォールバック、あるいは `/verify` の明示呼び出しから `scripts/append-consumed-comments-section.sh` が実行される
2. GitHub API のレスポンス形状変化、または jq フィルタのスコープ誤り (実際に #1107 の実装中に発生: `select(($body | contains(.url // "")) | not)` が `.url` を `$body` コンテキストに対して評価してしまい `Cannot index string with string ("url")` エラーとなった) などにより、5箇所の jq / `gh --jq` 呼び出しのいずれかが失敗する
3. 各呼び出しは `2>/dev/null || echo "[]"` により空配列にフォールバックし、スクリプトは exit 0 で終了する
4. Spec には "No new comments since last phase." が記録される (または既存セクションが無変更のまま) — 「新規コメント0件」の正常系とビット単位で同じ出力になり、stderr にも何も出力されない
5. 呼び出し側は exit 0 を成功として扱うため、安全網が機能していないことを誰も検知できない

## Root Cause

5箇所の jq / `gh --jq` 呼び出し (`RAW_COMMENTS` L67 / `SINCE_CUTOFF` L72 / `VERIFYFAIL` L80 / `ALL_COMMENTS` L86 / `NEW_COMMENTS` L125 — いずれも現行コードの実際の行番号と一致することを確認済み) が、jq 自身の診断出力を `2>/dev/null` で握りつぶし、失敗時に `|| echo "[]"` で空配列にフォールバックしている。これはフェイルセーフのために必要な設計だが、「jq が失敗した」状態と「jq が正常終了して結果が空配列だった」状態が同一の観測結果 (空配列・exit 0・stderr 無出力) に収束してしまう。同じ症状クラスは #1107 の実装中にも実際に発生しており (jq スコープエラーが `2>/dev/null` に隠蔽され新規 bats テストが無言で FAIL していた)、そのときは bats テストの存在によって発覚したが、本番実行 (`/verify` からの呼び出し) では発覚しない。

なお `CUTOFF` (`gh api .../timeline`、L61-63) は `|| true` によるフォールバックで空文字列を許容する別系統の設計であり、Issue Background が列挙する5箇所にも含まれないため、本 Issue のスコープ外とする (空 CUTOFF は「全コメントを新規扱い」という意図された分岐であり、「0件」への誤った収束ではない)。

## Changed Files

- `scripts/append-consumed-comments-section.sh`: `warn_jq_failed()` ヘルパーを追加し、`RAW_COMMENTS` / `SINCE_CUTOFF` / `VERIFYFAIL` / `ALL_COMMENTS` / `NEW_COMMENTS` の5箇所の jq / `gh --jq` 呼び出しを明示的な成否判定 + 警告出力に書き換える。フェイルセーフ (jq エラー時も exit 0) は変更なし — bash 3.2+ compatible
- `tests/append-consumed-comments-section.bats`: jq 失敗ケース (`gh` モックが不正な JSON を返す) の bats テストケースを追加

## Implementation Steps

1. `scripts/append-consumed-comments-section.sh` に `warn_jq_failed()` ヘルパー関数を追加する。既存の `WARNING —` 文言規約 (L16 / L95 / L140 / L152) に倣い、`"append-consumed-comments-section.sh: WARNING — jq failed at <step>; consumed comments not recorded"` を stderr に出力する (→ acceptance criteria AC1, AC2)
2. `RAW_COMMENTS` (L67) / `SINCE_CUTOFF` (L72) / `VERIFYFAIL` (L80) / `ALL_COMMENTS` (L86) / `NEW_COMMENTS` (L125) の5箇所を、`VAR=$(... 2>/dev/null || echo "[]")` 形式から `if ! VAR=$(... 2>/dev/null); then warn_jq_failed "<変数名>"; VAR="[]"; fi` 形式に書き換える。フォールバック先が空配列である点、および `set -uo pipefail` (`set -e` は不使用) によるフェイルセーフ性は変更しない (→ AC1, AC2, AC3)
3. `tests/append-consumed-comments-section.bats` に、`gh` モックが不正な JSON (プレーンテキスト) を返すケースを追加し、(a) スクリプトが exit 0 のまま終了すること、(b) stderr (bats の `$output`) に `jq failed` を含む警告が出力されること、(c) Spec ファイルへのフォールバック追記 (`## Consumed Comments` 見出し) が行われることを検証するテストケースを追加する (→ AC4)

## Verification

### Pre-merge

- <!-- verify: grep "jq failed" "scripts/append-consumed-comments-section.sh" --> jq 失敗時に警告を出す経路が追加されている
- <!-- verify: rubric "scripts/append-consumed-comments-section.sh の各 jq 呼び出しが、エラー時に空配列へフォールバックしつつ stderr へ観測可能な警告を出す (または jq の stderr を素通しする) 形に変更されており、エラーと『新規コメント 0 件』が区別できる" --> jq エラーが正常系と区別できる
- <!-- verify: rubric "変更後もスクリプトはフェイルセーフのまま (jq エラー時も非ゼロ終了せず exit 0 する) であり、呼び出し側 skills/verify/SKILL.md の best-effort 前提を壊していない" --> フェイルセーフ性が維持されている
- <!-- verify: rubric "tests/append-consumed-comments-section.bats に、jq が失敗するケースで警告が stderr に出力されることを検証するテストケースが追加されており、bats 実行が通る" --> jq 失敗時の警告を検証するテストが追加されている

### Post-merge

- 次回 `/verify` 実行時に jq エラーが発生した場合、stderr の警告から安全網が機能していないことを判別できることを観察 <!-- verify-type: observation event=auto-run -->
  - 期待する出力構造:
    - `scripts/append-consumed-comments-section.sh` の stderr に `jq failed at <変数名>` 形式の警告が出力されている
    - 警告メッセージから、どの jq 呼び出し (`RAW_COMMENTS` / `SINCE_CUTOFF` / `VERIFYFAIL` / `ALL_COMMENTS` / `NEW_COMMENTS` のいずれか) が失敗したかを特定できる

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: Option A を必須実装採用・gh失敗とjqエラーは区別しない・`<step>`は変数名を使用・AC4のbatsファイルは既存確認済み / https://github.com/saitoco/wholework/issues/1113#issuecomment-5138294160

## Notes

- **Scope confirmation**: Issue Background に記載された5箇所 (L67/72/80/86/125) は、現行コードの実際の行番号と完全に一致することを確認済み (ズレなし)。実装は行番号ではなく変数名 (`RAW_COMMENTS` 等) で特定する。
- **CUTOFF (L61-63) はスコープ外**: `gh api .../timeline` の jq 呼び出しは `|| true` による空文字列フォールバックであり、Issue Background が列挙する5箇所には含まれない。空 CUTOFF は「全コメントを新規扱い」という既存の意図された分岐であり、本 Issue が修正対象とする「エラーと0件正常系の混同」とは異なる設計のため対象外とした。
- **Steering Docs sync candidate check**: `append-consumed-comments-section.sh` で `docs/` `tests/` `scripts/` を横断 grep した結果、`docs/structure.md` / `docs/ja/structure.md` の役割説明、`scripts/emit-event.sh` の呼び出し (`|| true` による best-effort 呼び出しのまま) はいずれも内容確認済みで変更不要と判断した。`tests/run-verify.bats` は同スクリプトを別シナリオ (verify フェーズの決定的書き戻し) でテストする既存ファイルだが、AC4 が `tests/append-consumed-comments-section.bats` を明示的に対象指定しているため (Issue Retrospective コメントでも既存ファイルであることを確認済み)、新規テストはそちらにのみ追加し `tests/run-verify.bats` は変更しない。
- **doc-checker Impact Assessment**: 本 Issue はスクリプト内部のエラー可観測性追加のみであり、ワークフローフェーズ変更・プロジェクト構造変更・新規スクリプト追加のいずれにも該当しない (`modules/skill-dev-doc-impact.md` の Change Type 表と照合済み)。`README.md` / `README.ja.md` / `docs/workflow.md` に本スクリプト名の言及がないことを grep で確認済み。ドキュメント変更は不要と判断した。
- **Auto-Resolved Ambiguity Points は Issue body に記載済み**: `/issue --non-interactive` で解決済みの3点 (Option A を必須実装とする、`gh` 失敗と jq エラーを区別しない、`<step>` は変数名を使用する) は Issue body の `## Auto-Resolved Ambiguity Points` に記載済みであり、`/spec` (light) での追加解決は不要と判断した。

## Auto Retrospective

### Manual recovery (code-patch)
- **Date**: 2026-07-31 02:58 UTC
- **Issue**: #1113, phase: code-patch
- **Source**: parent session manual recovery
- **Recovery type**: commit-push
- **Wrapper exit code**: 1
- **Outcome**: success

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `triaged` / Size=S は事前設定済みだったため triage をスキップし、曖昧点 3 件 (Option A/B の選択、`gh` 失敗と jq エラーの区別要否、警告の `<step>` 内容) を非対話 3-Tier Policy でモデル判断し `## Auto-Resolved Ambiguity Points` に記録した。この 3 件が `/spec` 段階での再議論を防いでいる

#### spec
- Implementation Steps が「5 箇所の変数名 (RAW_COMMENTS / SINCE_CUTOFF / VERIFYFAIL / ALL_COMMENTS / NEW_COMMENTS) を列挙し、`if ! VAR=$(...); then warn_jq_failed "<変数名>"; VAR="[]"; fi` 形式に書き換える」と具体的だったため、実装乖離ゼロで 5/5 が変換された。verify 側も `grep -c 'warn_jq_failed "'` = 5 と `|| echo "[]"` の残存 0 件で機械確認できた
- spec フェーズ自身が main 先行による ff マージ失敗をリベースで自己復旧している (wrapper 内で完結、exit 0)

#### code
- **silent no-op を 2 回連続で起こした**。いずれも同一原因: `/code` セッションがフルテストスイートをバックグラウンド実行し「完了通知を待ちます」としてターンを終えたが、`claude -p` (headless) には harness の再呼び出しが存在せず通知が原理的に届かない。ログの決定的証拠: 「バックグラウンドのフルテストスイート実行完了を待ちます。完了通知が届き次第、結果を確認してコミット・プッシュに進みます。」→ `matches_expected: false` → `auto-retry: code phase silent no-op, retry 2/3`
- **auto-retry 2/3 が dirty-tree precondition で停止した**。先行試行が実装編集を worktree ではなく parent main の作業ツリーに残していたため、`check-verify-dirty` が `classify=parent-main` で 2 ファイルを検出し `Error: parent main has uncommitted changes. Resolve before proceeding.` で中断。実装は完成していたが、コミットされないまま宙に浮いた
- 親セッションが diff を Spec の Implementation Steps と突き合わせ、`bats tests/append-consumed-comments-section.bats` 7/7 とフルスイート 1294 件 failure 0 を確認したうえでコミット・push する manual recovery (`commit-push`) を実施 (`## Auto Retrospective` に記録済み)

#### review
- patch route のため `/review` は実行されていない

#### merge
- patch route のため `/merge` は実行されていない。push は親セッションの manual recovery で完了

#### verify
- Pre-merge 4/4 PASS。`|| echo "[]"` によるエラー隠蔽が 5 箇所 → 0 箇所になったことを機械確認できた点が決定的だった
- Post-merge observation AC は、本 `/verify` 自身が修正後スクリプトを実行したものの jq がすべて正常終了したため警告経路に入らず未観測。警告経路自体は bats の jq 失敗ケースで検証済み

### Improvement Proposals

- **`/code` が headless 実行でテストをバックグラウンド実行し通知待ちでターンを終える silent no-op — #1097 の code フェーズ版**: `#1097` は同一の根本原因 (`claude -p` には background task の完了通知を運ぶ harness 再呼び出しが存在しないため、「通知待ちでターンを終える」選択は headless では必ず silent no-op になる) を扱っているが、Background・実例・復旧の議論 (`post-fallback-review-summary.sh` / Response Summary / Review Retrospective) がいずれも `/review` 専用スコープで、`/code` は対象外。本 Issue の code フェーズは 2 回連続でこれを踏み、`#1074` でも 1 回発生している (計 3 回)。code フェーズ固有の帰結として、**先行試行が parent main の作業ツリーに実装編集を残すと、auto-retry が `check-verify-dirty` の dirty-tree precondition (`Error: parent main has uncommitted changes`) で停止し、完成済み実装がコミットされないまま宙に浮く**。review 側の `post-fallback-review-summary.sh` に相当する自動復旧経路が code 側には無く、親セッションが diff とテストを検証して手動コミットするしかない。対応候補: (a) `#1097` の対策を全 headless フェーズ (`run-code.sh` / `run-spec.sh` / `run-review.sh` / `run-merge.sh`) に一般化し、SKILL.md に「headless 実行ではテストを foreground で実行し、background + 通知待ちでターンを終えない」旨を明記する、(b) `/code` SKILL.md のテスト実行手順を foreground 固定にする、(c) 加えて `modules/orchestration-fallbacks.md` に「parent main の作業ツリーに実装が未コミットで残った状態」の復旧エントリ (diff と Spec の突き合わせ → テスト実行 → commit-push) を追加し、`#1081` (patch route の worktree 未 push コミット) と対になる形で catalog を揃える
