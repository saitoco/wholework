# Issue #1102: gh-pr-review: 自己 PR への REQUEST_CHANGES 422 を COMMENT へフォールバック

## Overview

`scripts/gh-pr-review.sh` は MUST 指摘があると無条件に `event="REQUEST_CHANGES"` を選択するが、GitHub API は自分自身の PR への `REQUEST_CHANGES` を 422 で拒否する。wholework は単一アカウントによる自己ホスト運用 (同一アカウントが Issue 起票・実装・レビュー・マージをすべて行う) が前提のため、MUST 指摘が出るたびにこの失敗を確実に踏む (#1069 / PR #1077 で実際に発生し、手動で `COMMENT` へフォールバックして投稿し直した実績あり)。

本 Issue は、`REQUEST_CHANGES` の POST が 422 (`Can not request changes on your own pull request` 相当のメッセージ) で失敗した場合を検知し、event を `COMMENT` に落として再投稿し、本文冒頭にその旨を注記することで、手動フォールバックを不要にする。422 以外の失敗はフォールバックせず従来どおりエラーとする (fail-open を広げない)。

## Reproduction Steps

1. wholework をシングルアカウントで自己ホスト運用する (Issue 起票・実装・レビュー・マージを同一 GitHub アカウントが行う)
2. `/review` が MUST 指摘を検出し、line comments 付きで `scripts/gh-pr-review.sh` を呼び出す
3. `HAS_MUST=true` により `EVENT="REQUEST_CHANGES"` が選択され、`gh api repos/$REPO/pulls/$PR_NUMBER/reviews --method POST` が実行される
4. GitHub API が「自分自身の PR への REQUEST_CHANGES」を拒否し、HTTP 422 (メッセージ例: `Review can not request changes on your own pull request`) を返す
5. スクリプトは POST 失敗を単一の `||` フォールバックでしか扱っておらず、422 か否か・メッセージ内容を区別せずに `Error: failed to post review for PR #$PR_NUMBER` を出力して `exit 1` する。レビュー投稿自体が失敗し、MUST 指摘が人手で再投稿されるまで反映されない

## Root Cause

`scripts/gh-pr-review.sh` の line comments ありパス (`EVENT="REQUEST_CHANGES"` 分岐) の POST 呼び出しは、現行 `echo "$REVIEW_PAYLOAD" | gh api ... --method POST --input - || { echo "Error: failed to post review..."; exit 1; }` という形で `gh api` の stderr を破棄しており、失敗理由を判別する材料を持たない。GitHub REST API は自分が作成した PR への `REQUEST_CHANGES` review を常に 422 で拒否する (公式ドキュメントに明記された制約というより実測で確認された挙動。#1069 / PR #1077 で実際に発生・記録済み)。単一アカウント自己ホスト運用ではこの組み合わせが構造的に毎回発生するため、修正は「422 かつ自己レビュー起因のメッセージ」の場合のみ `COMMENT` へ自動フォールバックする狭いスコープの検知ロジック追加で足りる。

## Changed Files

- `scripts/gh-pr-review.sh`: line comments ありパスの POST 呼び出し (`EVENT="REQUEST_CHANGES"` 時) で `gh api` の stderr を捕捉し、422 かつ自己レビューメッセージ一致時のみ `event: "COMMENT"` + 注記文を先頭に付与したペイロードで再送する。422 以外、またはメッセージ不一致の失敗は現行どおり `exit 1` (fail-open を広げない)。bash 3.2+ 互換。
- `tests/gh-pr-review.bats`: 422 フォールバックの positive case (自己レビュー 422 → COMMENT 再送で成功) と negative case (別理由の失敗 → フォールバックせず exit 1) を追加。

## Implementation Steps

1. `scripts/gh-pr-review.sh` の line comments ありパスにある既存の POST 呼び出し (`echo "$REVIEW_PAYLOAD" | gh api ... --method POST --input - || { echo "Error: failed to post review..."; exit 1; }`) を、stderr を捕捉できる形に置き換える:
   ```bash
   if ! API_STDERR=$(echo "$REVIEW_PAYLOAD" | gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --method POST --input - 2>&1 >/dev/null); then
       API_STATUS=$?
       # Step 2 で 422 判定とフォールバック分岐を追加
   fi
   ```
   **注意 (`set -e` との相互作用)**: このスクリプトは `set -euo pipefail` で実行される。`API_STDERR=$(cmd)` を単独の代入文として書くと、`cmd` が非 0 終了した瞬間に `set -e` がスクリプトを即終了させ、後続の分岐に到達できない。`if ! VAR=$(cmd); then ...; fi` のように「テストされているコマンド」として書くことでこれを回避する (bash 3.2 互換のイディオム)。 (→ acceptance criteria 1, 2)
2. (after 1) Step 1 の `if` ブロック内に判定を実装する: `"$EVENT" = "REQUEST_CHANGES"` かつ `$API_STDERR` が `422` (大文字小文字を区別) と `request changes on your own pull request` (大文字小文字を無視。先頭語 `Review [Cc]an not` を含まない部分文字列を使うことで実際の GitHub API メッセージの大文字小文字揺れに対して頑健にする) の両方にマッチする場合のみフォールバックする。フォールバック時は python3 で `$REVIEW_PAYLOAD` の JSON を再パースし、`event` を `"COMMENT"` に、`body` の先頭に英語の注記 (例: `Note: posted as COMMENT instead of REQUEST_CHANGES — self-review (own pull request) is not allowed to request changes.`) を追加した新ペイロードを構築して同じエンドポイントに再 POST する (既存の `comments` フィールドはそのまま維持)。再 POST が失敗した場合は `Error: failed to post fallback COMMENT review for PR #$PR_NUMBER` を出力して `exit 1`。上記条件を満たさない失敗 (非 422、またはメッセージ不一致) は、既存どおり `Error: failed to post review for PR #$PR_NUMBER` を出力して `exit 1` (フォールバックを広げない)。 (→ acceptance criteria 1, 2, 4)
3. (after 2) `tests/gh-pr-review.bats` に positive case を追加する: line comments に `severity: MUST` を含む入力を使い、mock `gh` の `api` 分岐を「1 回目の POST は stderr に `gh: Review can not request changes on your own pull request (HTTP 422)` を出力して exit 1、2 回目の POST は成功して exit 0」に切り替える (`$BATS_TEST_TMPDIR` 配下のカウンタファイルをインクリメントして呼び出し回数を判定するモック実装とする)。スクリプトが `exit 0` すること、2 回目の POST に渡されたペイロード (`$GH_API_STDIN` 相当) で `event == "COMMENT"` かつ `body` に注記文が含まれることを検証する。 (→ acceptance criteria 3, 4)
4. (after 2) `tests/gh-pr-review.bats` に negative case を追加する: line comments に `severity: MUST` を含む入力を使い、mock `gh` の `api` 分岐が (a) 422 だが自己レビューメッセージを含まない応答 (例: `gh: Validation Failed (HTTP 422)`)、または (b) 422 以外のステータス、のいずれかで exit 1 するようにし、スクリプトが `exit 1` すること、および `gh api ... --method POST` が 2 回呼ばれていない (フォールバックしていない) ことを `$GH_CALL_LOG` の出現回数で検証する。 (→ acceptance criteria 3, 4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/gh-pr-review.sh が REQUEST_CHANGES の 422 (Can not request changes on your own pull request) を検知して event を COMMENT に落として再投稿し、その旨を本文に注記する。422 以外の失敗ではフォールバックしない" --> 422 検知時に `COMMENT` フォールバックが行われ、その旨が本文に注記される
- <!-- verify: grep "422" "scripts/gh-pr-review.sh" --> `gh-pr-review.sh` に 422 フォールバックのロジックが存在する
- <!-- verify: rubric "gh-pr-review.sh の 422 フォールバック挙動を検証する bats テストが追加されている。422 応答時に COMMENT へ落ちること、および 422 以外の失敗ではフォールバックしないこと (negative case) の両方を検証している" --> 422 フォールバックの bats テストが positive / negative 両方追加されている
- <!-- verify: file_contains "tests/gh-pr-review.bats" "422" --> `tests/gh-pr-review.bats` に 422 フォールバックのテストケースが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テストスイートが CI で pass する (patch route)

### Post-merge

- MUST 指摘を含むレビューを自己 PR に対して実際に投稿し、手動介入なしで `COMMENT` として投稿されることを確認する <!-- verify-type: manual -->

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: `/issue` フェーズの Issue Retrospective。非対話モードでの曖昧ポイント自動解決なし、rubric 対象ファイル特定による `file_contains` 補完追加の理由、Background のコード照合結果 (一致)、severity フィールド欠落問題 (#1058 / PR #1201 系) は別スコープと明記、blocked-by なし、Title drift なし、を記録。 / URL: https://github.com/saitoco/wholework/issues/1102#issuecomment-5204474606
- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: Triage AC audit の指摘 (non-destructive) — AC2 の `grep` パターンに `REQUEST_CHANGES` が含まれ常時 PASS になる問題、AC5 の `gh pr checks` が patch route と不整合な問題を報告。 / URL: https://github.com/saitoco/wholework/issues/1102#issuecomment-5204499626
- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: 直前コメントの AC 監査指摘を Issue 本文に反映した旨の報告 (AC2 を `grep "422"` のみに変更、AC5 を `gh run list` 形式に変更)。取得した現在の Issue 本文は既にこの反映後の状態であることを確認した。 / URL: https://github.com/saitoco/wholework/issues/1102#issuecomment-5204516620

## Notes

### `gh api` エラー出力形式 (external spec 実測確認)

`gh version 2.96.0` で `gh api search/issues` (必須パラメータ `q` 欠如、読み取り専用・副作用なし) を実行し、`gh: Validation Failed (HTTP 422)` という形式 (`gh: <message> (HTTP <status>)`。`<message>` は GitHub API レスポンス JSON の `message` フィールドをそのまま使用) を実測確認した。同様に `gh api repos/saitoco/wholework/pulls/999999/reviews` (存在しない PR、読み取り専用) では `gh: Not Found (HTTP 404)` を確認しており、`(HTTP <status>)` トレーラー形式は安定している。自己レビュー時の具体的なメッセージ文字列自体は Issue 本文および #1069 retrospective に記録された実測 (`Review can not request changes on your own pull request`) からの引用であり、先頭語の大文字小文字 (`Review [Cc]an not`) が不安定な可能性があるため、判定は先頭語を含まない部分文字列 `request changes on your own pull request` を大文字小文字非依存でマッチさせる設計とする (Implementation Steps 2)。

### manual AC の自動化可否検討 (`modules/verify-patterns.md` §11)

Post-merge の手動確認 AC は、実行主体 (`/review` からの `gh-pr-review.sh` 呼び出し) 自体は既存の自動実行パスで行われるが、「特定の未来の PR で実際に 422 が発生し正しくフォールバックしたこと」を事前に機械検証できる対象が今は存在しない (bats テストは mock による論理検証であり、実際の GitHub API 相手の実地確認とは別軸)。observation-type AC への転換は新規の observation イベント種別追加を伴い Size S の本 Issue にはスコープ過大と判断し、`verify-type: manual` を維持する。

### Auto-Resolve Log

非対話モードでの曖昧ポイント自動解決は `/issue` フェーズ・`/spec` フェーズのいずれでも発生しなかった (対応方針が既に具体的で、要件レベルの曖昧ポイントが検出されなかったため)。

`/code` フェーズ開始時点で `phase/ready` ラベルが不在だった (現ラベルは `phase/code` — 過去の `/code` 実行が worktree 未作成のまま中断したことを示唆するレジューム状態と判断)。`reconcile-phase-state.sh --check-precondition` の診断も「Spec 欠落」ではなく「`phase/ready` ラベル不在」のみを指摘しており、`spec_file` フィールドは本 Spec の存在を確認済みだった。既存 Spec は要件を十分具体的に記述しているため、非対話モードのポリシーに従い Spec を破棄せず続行することを自動解決とした。

### フォールバック注記文の言語

`scripts/gh-pr-review.sh` は配布物 (Wholework Plugin の一部として全ユーザーに配布される共有スクリプト) であり、既存のエラーメッセージ (`Error: file not found` 等) もすべて英語で書かれている。本 Issue で追加するフォールバック注記文もこの既存慣例を継承し英語で埋め込む (CLAUDE.md 言語規約表の "Source code: English" に整合)。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1–4 をそのまま実装した。`set -e` 対策の `if ! VAR=$(cmd)` イディオムも Spec 記載どおり適用。

### Design Gaps/Ambiguities
- N/A — Spec の判定条件 (422 かつ `request changes on your own pull request` 部分文字列、大文字小文字非依存) が実装をそのまま導けるレベルまで具体化されており、追加の曖昧点は見つからなかった。

### Rework
- N/A — bats テスト 3 件 (positive 1 / negative 2) は初回実装で `tests/gh-pr-review.bats` 全 21 件 PASS。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 422 フォールバック判定は `EVENT = "REQUEST_CHANGES"` かつ stderr が `422` と自己レビューメッセージ部分文字列の両方にマッチする場合のみに限定し、それ以外の失敗 (別理由の 422、非 422 全般) は既存どおり `exit 1` とした (fail-open を広げない、Spec Implementation Steps 2 のとおり)。
- line comments なしパス (`else` 分岐) は `EVENT` が `REQUEST_CHANGES` になり得ないため変更対象外とし、既存の POST 呼び出しをそのまま残した。

### Deferred Items
- Post-merge の手動確認 AC (「MUST 指摘を含むレビューを自己 PR に実際に投稿」) は本フェーズでは未実施。実運用で MUST 指摘が出た次回の `/review` 実行時に自然に検証される。
- AC5 (`github_check "gh run list ..."`) は本コミットの push 前であるため本フェーズでは未チェック。push 後の CI 結果を待って `/verify` フェーズで確認する。

### Notes for Next Phase
- `/code` フェーズ開始時に `phase/ready` ラベルが不在だった (詳細は Notes > Auto-Resolve Log を参照)。Spec は既存のものを使用しており内容の欠落はない。
- patch route のため `/review` は実行されない。push 後の CI (`test.yml`) 結果が AC5 の判定材料となる。
