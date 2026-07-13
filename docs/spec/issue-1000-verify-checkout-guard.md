# Issue #1000: verify: Step 2 の base branch checkout に foreign-worktree ガードを追加

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (`/issue 1000 --non-interactive` の実行結果。Triage 判定 [Type=Feature / Size=L / Value=3]、Background ファクト検証の通過、AC1/AC2 を outcome ベース記述へ書き換えて実装方式の決定を `/spec` に委譲した経緯を記録。本 Spec の設計判断はこの委譲を引き継いでいる) / https://github.com/saitoco/wholework/issues/1000#issuecomment-4953903239

## Overview

`/verify` は `/review`・`/auto` から nested `Skill(skill="wholework:verify", args="$N")` として dispatch されることがあり、その呼び出しは呼び出し元と同一セッション・同一 CWD で実行される。`skills/verify/SKILL.md` の Step 2 (`git checkout "${BASE_BRANCH}"` / `git pull`) は、foreign-worktree 検出を行う Step 3 (Worktree Entry) より **前** に位置しており、呼び出し元の worktree を継承した状態でそのまま git のブランチ操作を実行してしまう。

本 Spec は #930 が Step 3 (Worktree Entry) に入れた保護の手前に残った未保護区間を塞ぐ。対象は 2 箇所:

1. **`/verify` Step 2**: base branch checkout の直前に foreign-worktree ガードを追加し、`foreign` 検出時は checkout/pull を実行せずメインリポジトリ root へ復帰する (defense in depth)。
2. **`/review` Opportunistic Verification**: nested `/verify` を dispatch する当該セクションの冒頭に「Worktree Exit が完了していること」の前提アサーションを追加する (根本原因側の予防)。

`/review` 側が主たる予防、`/verify` 側が最終防衛線という二層構成になっている。

## Changed Files

- `skills/verify/SKILL.md`: change — Step 2 の冒頭 (見出し直後、`--base` 引数の解釈より前) に **Worktree context guard** ブロックを追加。`detect-foreign-worktree.sh "verify/issue-$NUMBER"` の 3 分岐 (`none`/`own`/`foreign <path>`) を exhaustive に列挙し、`foreign` 時は `git checkout`/`git pull` を実行しない。frontmatter `allowed-tools` は変更不要 (`detect-foreign-worktree.sh:*`・`ExitWorktree` とも既存)
- `skills/review/SKILL.md`: change — `## Opportunistic Verification` セクションの見出し直後 (`opportunistic-verify: true` の判定より前) に **Precondition** ブロックを追加。`detect-foreign-worktree.sh "review/pr-$NUMBER"` の 3 分岐 (`none`/`own`/`foreign <path>`) を exhaustive に列挙。frontmatter `allowed-tools` は変更不要 (同上)
- `tests/verify.bats`: new file — `skills/verify/SKILL.md` Step 2 の構造テスト (ガードが checkout より前に位置すること、3 分岐の網羅、`foreign` 分岐の復帰手順)。`tests/review.bats` と同じ「SKILL.md をセクション抽出して grep する」構造テスト方式に倣う
- `tests/review.bats`: change — 既存 3 テストに加え、Opportunistic Verification の前提アサーション存在・3 分岐網羅・`## Worktree Exit (push-and-remove)` が `## Opportunistic Verification` より前に位置することの 3 テストを追加
- `docs/structure.md`: [Steering Docs sync candidate] change — Key Files > Scripts > Process management の `scripts/detect-foreign-worktree.sh` エントリの呼び出し元記述を、`modules/worktree-lifecycle.md` Entry section 単独から、`skills/verify/SKILL.md` Step 2・`skills/review/SKILL.md` Opportunistic Verification を含む形に更新
- `docs/ja/structure.md`: [Steering Docs sync candidate] change — 上記の日本語ミラーを同期 (`docs/translation-workflow.md` Sync Procedure 準拠)

## Implementation Steps

1. `skills/verify/SKILL.md` の `### Step 2: Detect and Update Base Branch` 見出し直後 (既存の `If ARGUMENTS contains --base {branch}` の段落より前) に、**Worktree context guard** ブロックを挿入する (→ acceptance criteria 1)。ブロックの構成:
   - 導入文: `/verify` は nested `Skill()` dispatch で呼び出し元の CWD を継承しうること、worktree 内で base branch を checkout すると (a) メインリポジトリで当該ブランチが checkout 済みなら `fatal: '<base>' is already used by worktree at ...` で exit 128、(b) checkout 済みでなければ呼び出し元 worktree のブランチをサイレントに base branch へ切り替えてしまうこと、Step 3 の Worktree Entry ガードでは手遅れであること
   - 判定コマンド: `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh "verify/issue-$NUMBER"` を bash code fence で記載
   - 分岐リストは **(exhaustive)** マーカー付きで以下 3 件を列挙する:
     - **`none`** (メインリポジトリ root — 通常ケース): そのまま以降の base branch 検出・`git checkout`・`git pull` を記載どおり実行する
     - **`own`** (`verify/issue-$NUMBER` worktree 内 — 再入呼び出し): base branch 検出 (`BASE_BRANCH` の決定。Step 13 の Worktree Exit で使用) は実行するが、この Step 末尾の `git checkout` / `git pull` はスキップする。理由はメインリポジトリが base branch を checkout している限り worktree 内での checkout は exit 128 で失敗するため。Step 3 へ進み、Entry section が `ENTERED_WORKTREE=false` を記録する
     - **`foreign <path>`** (呼び出し元の worktree を継承): `git checkout` / `git pull` を実行しない。復帰手順を順序付きで記載する — (1) 警告出力 `Warning: /verify was dispatched with the caller's worktree still active (<path>). Returning to the main repository root before base branch checkout.`、(2) `ExitWorktree(action: "keep")` を呼び呼び出し元の worktree セッションから抜ける (worktree セッションが無い場合はドキュメント上の no-op。`"remove"` ではなく `"keep"` を使い、呼び出し元の worktree とブランチをディスク上に残す)、(3) 判定コマンドが出力した `<path>` へ `cd <path>` して CWD を正規化、(4) `detect-foreign-worktree.sh "verify/issue-$NUMBER"` を再実行し、なお `none` にならない場合は `Error: Failed to return to the main repository root from <path>. Complete the caller's Worktree Exit, then re-run /verify $NUMBER.` を出力して中断 (checkout へ進まない)、(5) `none` になったら通常フローへ合流
   - Step 番号・見出し文言は変更しない (整数 Step 番号を維持し、既存参照を壊さない)
2. `skills/review/SKILL.md` の `## Opportunistic Verification` 見出し直後 (既存の `If opportunistic-verify: true is set in .wholework.yml` の段落より前) に、**Precondition** ブロックを挿入する (parallel with 1) (→ acceptance criteria 2)。ブロックの構成:
   - 見出し文: このセクションが nested `Skill(skill="wholework:verify", ...)` を同一セッション・同一 CWD で dispatch するため、直前の `## Worktree Exit (push-and-remove)` セクションが完了していることが前提であること (Issue #930 / #1000)
   - 判定コマンド: `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh "review/pr-$NUMBER"` を bash code fence で記載 (`$NUMBER` は `/review` の PR 番号。worktree 名の規約は Step 2 の `review/pr-$NUMBER` と一致)
   - 分岐リストは **(exhaustive)** マーカー付きで以下 3 件を列挙する:
     - **`none`**: Worktree Exit が完了済み (または `ENTERED_WORKTREE=false` で worktree を作成していない)。このセクションを続行する
     - **`own`**: Worktree Exit セクションが未実行または未完了で、まだ `review/pr-$NUMBER` の中にいる。上の `## Worktree Exit (push-and-remove)` セクションに戻って完了させ、このアサーションを再実行する。`none` になるまで dispatch しない
     - **`foreign <path>`**: CWD が別 skill の worktree 内にある。`ExitWorktree(action: "keep")` を呼び、`cd <path>` でメインリポジトリ root へ復帰し、このアサーションを再実行する。なお `none` にならない場合は本セクション全体 (opportunistic verification と Event-based observation scan の両方) をスキップし、`Warning: skipping Opportunistic Verification — could not return to the main repository root from <path>.` を出力する
   - このブロックはセクション冒頭に置くため、`opportunistic-verify` 設定の有無に関わらず常時実行される Event-based observation scan ブロックもカバーされる
3. `tests/verify.bats` を新規作成する (after 1) (→ acceptance criteria 3, 4)。`tests/review.bats` に倣い、`SKILL_FILE` を `skills/verify/SKILL.md` の絶対パスに解決し、`awk` で `### Step 2:` 見出しから次の `### Step ` 見出しまでを抽出するヘルパー関数 `step2_section()` を定義する。テストケース (最低 4 件):
   - `"Step 2 guard: detect-foreign-worktree.sh runs before base branch checkout"`: `grep -n` で Step 2 セクション内の `detect-foreign-worktree.sh` の初出行番号と `git checkout "${BASE_BRANCH}"` の行番号を取得し、前者 < 後者 であることを検証する
   - `"Step 2 guard: all three worktree contexts are enumerated"`: Step 2 セクションが `none` / `own` / `foreign` の 3 語をいずれも含むことを検証する
   - `"Step 2 guard: foreign branch exits the caller worktree session"`: Step 2 セクションが `ExitWorktree(action: "keep")` を含むことを検証する
   - `"Step 2 guard: foreign branch skips checkout and pull"`: Step 2 セクションが `foreign` 分岐で checkout/pull を実行しない旨の記述 (`do not run` + `git checkout`) を含むことを検証する
   - bash 3.2+ 互換で書く (`mapfile` 等の bash 4 専用組み込みは使用しない)
4. `tests/review.bats` に 3 テストを追加する (after 2) (→ acceptance criteria 3, 4)。既存の `opportunistic_verification_section()` ヘルパーをそのまま再利用する (挿入するブロックは `## ` 見出しを含まないため、既存の awk 抽出ロジックは変更不要):
   - `"Opportunistic Verification: worktree exit precondition is asserted"`: セクションが `detect-foreign-worktree.sh` を含むことを検証する
   - `"Opportunistic Verification: all three worktree contexts are enumerated"`: セクションが `none` / `own` / `foreign` の 3 語をいずれも含むことを検証する
   - `"Worktree Exit section precedes Opportunistic Verification"`: `grep -n` で `## Worktree Exit (push-and-remove)` と `## Opportunistic Verification` の行番号を取得し、前者 < 後者 であることを検証する
5. `docs/structure.md` の `scripts/detect-foreign-worktree.sh` エントリ (Key Files > Scripts > Process management) の呼び出し元記述を更新し、`modules/worktree-lifecycle.md` Entry section に加えて `skills/verify/SKILL.md` Step 2 (base branch checkout guard) と `skills/review/SKILL.md` Opportunistic Verification (worktree exit precondition) から直接呼ばれることを明記する。`docs/ja/structure.md` の対応行にも同じ内容の日本語ミラーを同期する (parallel with 1, 2) (SHOULD レベル。`docs/translation-workflow.md` Sync Procedure 準拠)。ファイル数コメント (`scripts/` `(65 files)`) は新規スクリプト追加が無いため変更しない

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.mdのbase branch checkoutが、呼び出し元のworktreeを引き継いだ状態でgit checkout/git pullを実行しないよう保護されている" --> `skills/verify/SKILL.md` の base branch checkout (現 Step 2) が、呼び出し元の worktree/CWD を引き継いだ状態のまま `git checkout`/`git pull` を実行することがないよう保護されている
- <!-- verify: rubric "skills/review/SKILL.mdのOpportunistic Verificationセクションが、Worktree Exit完了後にのみ実行されることを検証可能な形で保証している" --> `skills/review/SKILL.md` の Opportunistic Verification セクション (Event-based observation scan を含む) が、Worktree Exit セクション完了後にのみ実行されることを検証可能な形で保証されている
- <!-- verify: rubric "追加された保護機構について、テストコード (bats等) が存在する" --> 上記構造について bats テスト等の自動検証が追加されている
- <!-- verify: command "bats tests/verify.bats tests/review.bats" --> 追加した bats テストが PASS する

### Post-merge

- 次回 `/review --full` 完了時の `pr-review-full` イベントで nested `/verify` が dispatch されたセッションにおいて、`/verify` の base branch checkout が呼び出し元 worktree 内で実行されないことを観察 <!-- verify-type: observation event=pr-review-full -->
  - 期待される出力構造: (a) `/review` の Opportunistic Verification 開始時点で `detect-foreign-worktree.sh` が `none` を返している、(b) nested `/verify` の Step 2 が foreign 検出による中断・復帰を必要としない

## Tool Dependencies

### Bash Command Patterns
- none — `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh:*` は `skills/verify/SKILL.md`・`skills/review/SKILL.md` 双方の `allowed-tools` に #930 で追加済み。`cd` は `modules/worktree-lifecycle.md` Entry section が既に採用している既存パターンで、個別の allowed-tools エントリを持たない

### Built-in Tools
- none — `ExitWorktree` は両 SKILL.md の `allowed-tools` に登録済み

### MCP Tools
- none

## Uncertainty

- **nested skill から `ExitWorktree(action: "keep")` を呼んだ場合の呼び出し元セッションへの影響**: `/verify` Step 2 の `foreign` 分岐は、呼び出し元 (`/review` 等) の worktree セッションを nested 側から exit する。ExitWorktree のツール仕様には「EnterWorktree セッション外で呼ばれた場合は no-op (ファイルシステム状態は不変)」と明記されており、CWD だけが残留している leftover ケースでは安全。一方、呼び出し元のセッションが実際にアクティブな場合、呼び出し元は自身の worktree の外に戻されることになる。ただし本 Spec の `/review` 側 (Implementation Step 2) の前提アサーションが機能していれば、この分岐に到達する時点で呼び出し元は既に Worktree Exit 済みのはずであり、この経路は異常系のフォールバックとして働く。
  - **検証方法**: Post-merge の observation AC (次回の実 `/review --full` 実行) で確認する。`/review` 側のアサーションが正しく機能していれば、`/verify` 側の `foreign` 分岐はそもそも発火しない。
  - **影響範囲**: Implementation Steps 1 (`foreign` 分岐の復帰手順 (2))。
- **`own` 分岐で `git checkout` / `git pull` をスキップした場合の base branch 鮮度**: 再入呼び出し (`/verify` 自身の worktree 内から再実行) では base branch の `git pull` が行われないため、worktree branch の基点が origin より古い可能性がある。ただしこの分岐は通常フロー (Step 3 で新規 worktree を作成する) では到達せず、`EnterWorktree` が `worktree.baseRef` 設定に従って基点を解決するため、実運用上の影響は限定的と判断した。
  - **検証方法**: `own` 分岐は現行の通常フローに存在しないため、bats 構造テストでの分岐記述の存在確認に留める。実挙動の観測は再入ケースが実際に発生した時点で行う。
  - **影響範囲**: Implementation Steps 1 (`own` 分岐)。

## Notes

### Ambiguity Resolution (Auto-Resolve Log — non-interactive mode)

- **論点 1 (最重要): AC1 の保護方式 — 「Step 2 直前へのガード追加」 vs 「Step 2/3 の順序入れ替え」**
  - **自動解決**: 「Step 2 直前へのガード追加」を採用。「順序入れ替え」(Worktree Entry を先に実行し、base branch checkout を worktree 内で行う) は **技術的に成立しない** ことを実測で確認した。
  - **判断根拠 (実測)**: 使い捨て git リポジトリで検証したところ、worktree 内で `git checkout main` を実行すると — (a) メインリポジトリが `main` を checkout している場合、`fatal: 'main' is already used by worktree at '<main root>'` で **exit 128** となり失敗する。(b) メインリポジトリが別ブランチにいる場合、checkout は **成功してしまい**、worktree の HEAD が自身のブランチ (`wt1`) から `main` へサイレントに切り替わる。つまり順序入れ替えは、Issue body の Background が挙げる failure mode (a)(b) をそのまま `/verify` の正常系に持ち込むことになる。
  - **不採用とした候補**: 順序入れ替え (`/issue` フェーズの Auto-Resolve Log が「より DRY」として有力視していた案)。上記実測により棄却した。`/issue` は実装方式の決定を明示的に `/spec` へ委譲していたため、この棄却は委譲の範囲内の判断である。
- **論点 2: `foreign` 検出時の復帰手段 — `cd <path>` のみ vs `ExitWorktree("keep")` + `cd <path>`**
  - **自動解決**: `ExitWorktree("keep")` → `cd <path>` の 2 段構えを採用。
  - **判断根拠**: EnterWorktree のツール仕様に「Must not already be in a worktree session when creating a new worktree (`name`)」という制約があるため、CWD だけを `cd` で戻しても呼び出し元の worktree セッションが生きていれば Step 3 の `EnterWorktree(name: ...)` が失敗する。ExitWorktree はセッションが無ければ no-op なので、leftover CWD ケースでも安全に併用できる。`modules/worktree-lifecycle.md` Entry section の既存 `foreign` 分岐が `cd <path>` のみで済ませているのは、そこに到達する時点でセッションが既に閉じている前提に立っているためで、Step 2 (Entry より手前) では同じ前提を置けない。
- **論点 3: `/review` 側アサーションの配置 — `modules/opportunistic-verify.md` (3 skill 共通) vs `skills/review/SKILL.md` 直接**
  - **自動解決**: `skills/review/SKILL.md` の `## Opportunistic Verification` セクション冒頭に直接配置。
  - **判断根拠**: nested `Skill(wholework:verify, ...)` を実際に dispatch しているのは Event-based observation scan ブロックであり、これは SKILL.md 本文に「runs regardless of `opportunistic-verify` setting」と明記されたとおり、`opportunistic-verify: false` の環境でも常時実行される。すなわち `modules/opportunistic-verify.md` は読み込まれないケースがあり、モジュール側にアサーションを置いても dispatch 経路をカバーできない。セクション冒頭に置くことで両ブロックを一括してカバーできる。

### 共有モジュール抽出を見送った理由 (DRY 判断)

`modules/worktree-lifecycle.md` Entry section step 1、`/verify` Step 2 ガード、`/review` Opportunistic Verification アサーションの 3 箇所は `detect-foreign-worktree.sh` の 3 分岐という骨格を共有するが、分岐後の tail action が互いに異なる (Entry: `ENTERED_WORKTREE=true` を記録して継続 / verify Step 2: ExitWorktree + cd + 再判定 + 中断 or 続行 / review: ExitWorktree + cd + 再判定 + セクション全体スキップ)。共通化すると 3 種類の tail をパラメータ化する必要があり、除去できる重複より複雑さの増分が大きい。LLM-native prose の重複は 2 skill までは許容し、同じロジックを 3 つ目の skill (例: `/auto` の verify dispatch 箇所) が必要とした時点で `worktree-lifecycle.md` への抽出を再検討する。

### Steering Docs sync candidate 調査

`detect-foreign-worktree` をキーワードに `docs/*.md` / `docs/ja/*.md` を grep した結果、`docs/structure.md:213` と `docs/ja/structure.md:205` の 2 箇所のみがヒットし、いずれも呼び出し元を `modules/worktree-lifecycle.md` Entry section 単独と記述している。本 Spec で直接の呼び出し元が 2 箇所増えるため、両ファイルを Changed Files に含めた。`docs/workflow.md` の `opportunistic` ヒットは verify-type 分類の説明であり実行順序に触れていないため対象外。`README.md`・`CLAUDE.md` は skill 一覧・phase 説明レベルの記述のみで、SKILL.md 内部ステップのガード追加による影響を受けない。

### 既存ドリフト (本 Issue の対象外)

`docs/structure.md:45` の `tests/` ファイル数コメントは `(95 files)` だが実測は 98 件で、既にドリフトしている。`docs/structure.md:89` のファイル数更新ルールは `modules/` と `scripts/` のみを対象としており `tests/` を含まないため、本 Issue では `tests/verify.bats` 追加後も当該コメントを変更しない。

### Verify command sync 確認

`## Verification > Pre-merge` の 4 項目は Issue 本文 `## Acceptance Criteria > Pre-merge` の 4 項目と verify command を含め完全一致 (件数一致: Issue 側 4 件 / Spec 側 4 件)。Post-merge も Issue 本文の 1 件と一致 (`verify-type: observation event=pr-review-full` を含め verbatim)。4 件目の `command "bats ..."` AC と Post-merge の observation AC は本 `/spec` フェーズで追加し、Issue 本文にも同時に反映済み (経緯は Issue 本文の Autonomous Auto-Resolve Log `/spec` フェーズ節を参照)。

### validate-skill-syntax.py 制約の確認

追加する SKILL.md 本文には半角の感嘆符を含めない。分岐リストには **(exhaustive)** マーカーを付与する。Step 番号は整数のまま (Step 2 の見出し・番号は変更しない)。
