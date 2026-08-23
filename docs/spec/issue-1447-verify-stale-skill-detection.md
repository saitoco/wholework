# Issue #1447: verify: 会話セッション単位skillキャッシュによるstale実行を検出/警告

## Overview

`/verify` は `run-verify.sh` のような wrapper を持たず、親会話セッション内で `Skill()` 呼び出しとして直接実行される。このため、会話開始時 (または最初の `/verify` invocation 時) に読み込まれた `skills/verify/SKILL.md` のテキストがセッション単位でキャッシュされ続け、同一会話内で別 Issue の `/spec`→`/code`→`/merge` サイクルにより `skills/verify/SKILL.md` 自体が変更・merge された後も、その変更が以降の `/verify` 実行に反映されない。

この事象は Issue #1278 の実測 (session `46468-1786195191`) で確認され、`docs/spec/issue-1202-verify-pr-search-closes-match.md` の Verify Retrospective でも独立に観測・記録されている。いずれのケースでも「渡された skill テキストの特徴的な一文とディスク上のファイルを照合する軽量チェック」が検出手段の候補として挙げられていた。

本 Issue では、`skills/verify/SKILL.md` 自身に行数マーカーを埋め込み、Step 1 冒頭で「現在実行中の指示文中に書かれているマーカー値 (会話キャッシュ由来)」と「`wc -l` によるディスク上の現在の行数」を比較する軽量な自己整合性チェックを追加する。不一致を検出した場合、terminal 警告に加えて Step 9 で投稿する Issue コメントにも警告を残し、terminal ログを直接観測しない自動実行環境でも検出可能にする。完全な防止 (harness のキャッシュ自体を回避すること) は範囲外とし、Issue の Purpose が明示するとおり検出・警告に留める。

## Changed Files

- `skills/verify/SKILL.md`:
  - `# Acceptance Test` タイトル直下に `<!-- skill-body-lines: N -->` マーカーを追加
  - `### Step 1: Check Working Directory Safety` の先頭 (既存の dirty file classifier 呼び出しより前) に自己整合性チェックを追加
  - `### Step 9: Post Comment on Issue` のコメント本文テンプレートに、stale 検出時の警告文差し込みロジックを追加
- `tests/verify.bats`: 新規 `step1_section()` ヘルパー追加 (既存の `step2_section()`/`step9_section()` と同じ awk パターン)、および新規テストケース追加 (マーカー同期・チェック配置・Step 9 警告差し込みの3点)

## Implementation Steps

1. `skills/verify/SKILL.md` の `# Acceptance Test` タイトル行の直後 (「Receive an Issue number...」の前) に `<!-- skill-body-lines: N -->` を追加する。`N` はステップ 2・3 の編集も終えたうえで、完成済みファイルに対して `wc -l < skills/verify/SKILL.md` を実行して得た値を使うこと (行数マーカーなので編集の最後に確定させる)。(→ 受入基準A)

2. `skills/verify/SKILL.md` の `### Step 1: Check Working Directory Safety` の最初のコンテンツとして (「Run the dirty file classifier:」より前に)、自己整合性チェックを追加する。
   - **比較の左辺 (キャッシュ側)**: 現在実行中の指示文中、上記ステップ1で追加した `<!-- skill-body-lines: N -->` に書かれている数値を、そのまま (新規の Read/Grep/Bash 呼び出しをせず) 転記する。**重要**: この値を新たなツール呼び出しで取得すると、両辺とも常にディスク上の現在値になり比較が恒真式になって stale 検出が機能しなくなる。会話コンテキストに既に読み込まれている指示文からその場で転記することを明記する。
   - **比較の右辺 (ディスク側)**: `wc -l < "${CLAUDE_PLUGIN_ROOT}/skills/verify/SKILL.md"` で取得する live な行数。
   - **不一致時**: `STALE_SKILL_BODY_DETECTED=true` を設定し、両方の行数 (キャッシュ側 N、ディスク側 M) を保持したうえで、terminal に以下の趣旨の警告を出力する: `skills/verify/SKILL.md` がこのセッション内で stale な可能性があり (cached N 行 / on-disk M 行)、現在実行中の指示が最新の merge 内容を反映していない可能性があるため、新しい会話セッションで `/verify $NUMBER` を再実行することを推奨する。
   - **一致時**: `STALE_SKILL_BODY_DETECTED=false` を設定し、何も出力せず継続する。
   (→ 受入基準A)

3. `skills/verify/SKILL.md` の `### Step 9: Post Comment on Issue` のコメント本文テンプレートを拡張する。ステップ 2 で `STALE_SKILL_BODY_DETECTED=true` だった場合、コメント本文に (HTML コメントではなく) 通常の Markdown 可視テキストとして警告行を、実行可能性マーカー行がある場合はその後、`## Acceptance Test Results` 見出しの直前に差し込む。これにより terminal 出力を見ない自動実行環境でも Issue 上で stale 実行を確認できるようにする (→ 受入基準A)

4. `tests/verify.bats` に以下を追加する:
   - `step1_section()` ヘルパー (既存の `step2_section()`/`step9_section()` と同じ awk による `### Step 1: ` 〜 次の `### Step ` 見出し直前までの抽出パターン)
   - 新規テストケース (既存スイートに追加するもので、既存スイートを置き換えない):
     a. `skills/verify/SKILL.md` の `skill-body-lines` マーカーの数値が、同ファイルの `wc -l` 結果と一致すること (ステップ1のマーカー同期を保護する回帰テスト)
     b. `step1_section()` 内で、自己整合性チェックのブロックが既存の `check-verify-dirty.sh` 呼び出しより前に出現すること
     c. `step9_section()` 内に `STALE_SKILL_BODY_DETECTED` を条件とした警告差し込みロジックが存在すること
   - 既存スイートが PASS することだけでなく、上記の新規テストケースを追加したうえでスイート全体が PASS すること
   (→ 受入基準A, 受入基準B)

## Verification

### Pre-merge

- <!-- verify: rubric "採用した方針が実装され、/verify が会話セッション単位でキャッシュされた stale な skill 本文を実行した場合に、検出または警告が行われるようになっている" --> stale な skill 実行が検出または警告される
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが全PASSしている (pr route)

### Post-merge

なし

## Notes

### 採用方針の選定根拠 (Issue Proposal 候補 1〜3 からの選択、non-interactive auto-resolve)

Issue 本文 (候補 1〜3) および `docs/spec/issue-1202-verify-pr-search-closes-match.md` の Verify Retrospective が独立に記録した候補のうち、**候補 1**「`/verify` 実行冒頭で、渡された skill テキストの特徴的な一文とディスク上のファイルを照合する軽量チェックを追加し、不一致なら警告を出す」を採用した。

- **候補 2 を採らなかった理由**: session 開始時点の commit hash / mtime を記録し、後から比較する方式は、`/verify` が wrapper を持たず親会話に直接 dispatch されるため「session 開始時点」を記録するフック自体が存在せず、新たな記録インフラ (session-start マーカーファイル等) を要する。Size S の light spec の範囲を超えると判断した。
- **候補 3 を採らなかった理由**: 運用ガイド追加のみでは、Issue の Purpose が明示する「検出または警告」という動作面の変更を満たさない。
- **「特徴的な一文」ではなく行数 (`wc -l`) を採用した理由**: Step 数や末尾 Step 見出しのような部分指標では、#1278 のように既存 Step (Step 8b / Step 9) の内容のみを書き換える編集 (Step の追加・削除を伴わない) を検知できない。行数はほぼ全てのプローズ編集で変化するため、追加インフラなしで最も検知力の高い代理指標と判断した。

### 自己参照チェックの正しさに関する重要な実装上の注意

Implementation Step 2 の比較は「現在実行中の指示文中に書かれているマーカー値」対「`wc -l` によるディスク上の現在値」でなければならない。マーカー値を Bash/Read/Grep 等の新規ツール呼び出しで取得すると、両辺とも常にディスクの現在値になり比較が恒真式になって stale 検出が機能しなくなる。`/code` 実装時にこの点を落とさないよう Implementation Step 2 に明記した。

### Size 再評価に伴う verify command 修正 (Step 18)

Step 18 の 2-axis 再評価で、変更ファイル数 (2件) に加えて「新規アーキテクチャパターンの導入 (行数マーカーによる自己整合性チェックは本リポジトリに類似実装が存在しない)」という複雑度加算要因に該当したため、Size を S (patch route) から M (pr route) に更新した (Project field 更新済み)。この結果、Verification > Pre-merge の bats テスト AC が patch route 前提の `github_check "gh run list ...--branch=main..."` 形式のままだと pr route では意味を持たなくなる (main 上の無関係な直近 CI 結果を見てしまい、この PR 自体の CI 結果を見ない) ため、`github_check "gh pr checks" "Run bats tests"` 形式に修正し、Issue 本文の Acceptance Criteria も同期させた。

### スコープ

本 Issue は `/verify` (wrapper を持たないスキル) に限定する。他スキル (`/spec`/`/code`/`/review`/`/merge`) は `#1206` (pr route merge 後のローカル main 未追従の検出/防止) で別途保護されている。同種の自己参照行数マーカーパターンを他スキルや他ファイルに一般化するかどうかは本 Issue のスコープ外 (将来の別 Issue 候補)。

### ドキュメント同期チェック

`modules/skill-dev-doc-impact.md` の「Skill addition, change, or deletion」行が形式的には該当しうるが、影響対象として挙げられているのは README.md / docs/workflow.md の「skill list」「phase descriptions」であり、本変更はスキル一覧やフェーズ責務を変えない `/verify` 内部の自己防御ロジック追加のため、これらのドキュメント更新は対象外と判断した。

### Steering Docs sync candidate check

新規マーカー名 `skill-body-lines` および新規変数名 `STALE_SKILL_BODY_DETECTED` について `grep -rn` を `docs/`, `tests/`, `scripts/`, `modules/`, `skills/` に対して実行し、既存の参照は見つからなかった (新規導入のため同期対象なし)。

### New test case requirement (light depth — Step 13 retrospective省略のため本 Notes に代替記録)

`tests/verify.bats` に Step 1 の自己整合性チェック (マーカー同期・配置) と Step 9 の警告差し込みを検証する新規テストケース (計3件) を追加し、既存スイートと合わせて全PASSすることを Implementation Step 4 で要求した。

## Consumed Comments

- saito / MEMBER / first-class / Size Re-evaluation (S→M, patch→pr route)、AC2 の verify command を `github_check "gh pr checks" "Run bats tests"` 形式へ修正 (Spec Notes に既に反映済み) / https://github.com/saitoco/wholework/issues/1447#issuecomment-5383520575
