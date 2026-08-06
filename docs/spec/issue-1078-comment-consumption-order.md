# Issue #1078: code: Step 1 の Consumed Comments 追記が worktree fresh 作成時に失われうる

## Overview

`skills/code/SKILL.md` と `skills/spec/SKILL.md` は、Comment Consumption Procedure (`modules/l0-surfaces.md`) の呼び出しを Step 1 (Fetch Issue Info/Information) に、Worktree Entry を Step 2 に配置している。Comment Consumption Procedure の Step 5 は Spec の `## Consumed Comments` セクションへの書き込みを伴うため、この順序では書き込みが worktree 作成前 (= メインリポジトリのワーキングツリー) に対して行われる。直後の `EnterWorktree` はデフォルト `baseRef=fresh` で `origin/<default-branch>` から分岐するため、この未コミット変更は新しい worktree ブランチに引き継がれず孤立する。

`skills/verify/SKILL.md` は既に Worktree Entry (Step 3) → Comment Consumption (Step 4) の順序で実装されており矛盾がない。本 Issue は `/code` と `/spec` の Step 順序をこの前例に整合させ、加えて `modules/worktree-lifecycle.md` の "Spec file write destination" 節に順序関係の明文化を追加する。

## Reproduction Steps

1. Issue 用の Spec が既にメインリポジトリにコミット済みの状態 (例: 2周目以降の `/spec` 実行、または `/code` の任意の実行) で `/spec $N` または `/code $N` を実行する。
2. Step 1 (Fetch Issue Info/Information) の Comment Consumption Procedure が新規コメントを検出し、`## Consumed Comments` セクションへの追記をメインリポジトリのワーキングツリー上の Spec に対して行う (この時点では worktree 未作成)。
3. Step 2 (Worktree Entry) が `EnterWorktree(name: ...)` を呼び出す。デフォルト `worktree.baseRef=fresh` は `origin/<default-branch>` から分岐するため、Step 2 で作成される worktree ブランチは Step 1 の未コミット変更を含まない。
4. メインリポジトリのワーキングツリーには、コミットされないまま孤立した diff (`## Consumed Comments` の追記) が残る。後続フェーズがこの状態で `git status` を検査すると (例: `/verify` の `check-verify-dirty.sh`)、無関係な dirty ファイルとして検出されうる。

実際に観測された発生例: Issue #1128 (`/auto` 実行中、`/verify` が `check-verify-dirty.sh` exit 1 でブロック)、Issue #1163 (`## Consumed Comments` の4行追記がメインツリーに残留、ユーザーが `git status` で発見)、および `docs/spec/issue-1163-manual-ac-retype-a.md` に記録された3件目の code フェーズでの実例。

## Root Cause

`skills/code/SKILL.md` の Step 1 (`### Step 1: Fetch Issue Info`) と `skills/spec/SKILL.md` の Step 1 (`### Step 1: Fetch Issue Information`) は、いずれも Comment Consumption Procedure (`modules/l0-surfaces.md`) の呼び出しを Worktree Entry (両スキルとも Step 2) より前に配置している。Comment Consumption Procedure の Step 5 ("Record in Consumed Comments") は Spec ファイルへの書き込みを伴う操作であり、`modules/worktree-lifecycle.md` の "Spec file write destination" 節が定める「Spec への書き込みはそのフェーズ自身の作業ブランチ上でのみ行う」という規約に反し、worktree 未作成 (= 作業ブランチ未確定) の状態で書き込みが実行されてしまう。

`EnterWorktree` の `baseRef` はデフォルト `fresh` であり、`origin/<default-branch>` から分岐する。`head` (ローカル HEAD から分岐) を使うにはセッション/グローバル設定の変更が必要で、スキル呼び出し単位で指定できる引数ではない (`EnterWorktree` ツールスキーマにも `baseRef` 相当の呼び出し時引数は存在せず、`name` / `path` のみが公開されている)。このため、Step 1 でメインリポジトリに加えた未コミット変更は、Step 2 が作成する worktree ブランチに一切引き継がれない。

`skills/verify/SKILL.md` は Worktree Entry (Step 3) → Comment Consumption (Step 4) という正しい順序を既に持っており、この順序の重要性は同ファイル内でも「Skipping it causes Step 4's `append-consumed-comments-section.sh` to commit/push directly onto a branch outside the worktree」という形で明記されている。対応方針の先例となる。`modules/worktree-lifecycle.md` の "Spec file write destination" 節 (#1058 で新設) は書き込み先ブランチの一般規約を宣言したのみで、`/code`/`/spec` の Step 順序自体は変更されておらず、"Known gaps" にもこの順序矛盾は記載がなかった。

## Changed Files

- `skills/code/SKILL.md`: Step 1 (`Fetch Issue Info`) 末尾の "Consume comments since the last phase (L0 input)" 段落 (Comment Consumption Procedure 呼び出し) を、Step 2 (`Worktree Entry`) 末尾に移動する。Step 番号・見出しは変更しない。
- `skills/spec/SKILL.md`: 同様に Step 1 (`Fetch Issue Information`) 末尾の同段落を Step 2 (`Worktree Entry`) 末尾に移動する。Step 番号・見出しは変更しない。
- `modules/worktree-lifecycle.md`: "Spec file write destination" 節に、Comment Consumption Procedure との実行順序関係を明記する新規段落を追加する。

## Implementation Steps

1. `skills/code/SKILL.md` の Step 1 (`### Step 1: Fetch Issue Info`) から、"**Consume comments since the last phase (L0 input):**" で始まる段落 (`ISSUE_NUMBER=$NUMBER`, `COMMENT_SCOPE=issue`, `PHASE_NAME=code` 指定、cutoff は直近の `phase/ready` ラベル付与、resume 時の `COMMENT_SCOPE=issue+pr` 注記を含む) を削除する。同段落を Step 2 (`### Step 2: Worktree Entry`) 末尾の "**Edit/Write path conventions inside worktree (CWD-relative):**" 段落の直後 (`### Step 3: \`phase/ready\` Label Check` 見出しの直前) に、内容そのまま移動する。移動後の段落見出しを "**Consume comments since the last phase (L0 input; run after Worktree Entry above — see `modules/worktree-lifecycle.md` § \"Spec file write destination\"):**" に変更し、Worktree Entry 完了後に実行する段落であることを明示する。Step 1 / Step 2 の見出し・番号・他の内容 (frontmatter の `allowed-tools` を含む) は変更しない。(→ 受入条件 AC1)
2. `skills/spec/SKILL.md` の Step 1 (`### Step 1: Fetch Issue Information`) から同様の段落 (`PHASE_NAME=spec`, cutoff は直近の `phase/issue` ラベル付与) を削除し、Step 2 (`### Step 2: Worktree Entry`) 末尾の "Record `ENTERED_WORKTREE` for later use..." 文の直後 (`### Step 3: Label Transition (start)` 見出しの直前) に、手順1と同じ見出し変更 (`PHASE_NAME=spec` 版) を適用して移動する。(parallel with 1) (→ 受入条件 AC1)
3. `modules/worktree-lifecycle.md` の "### Spec file write destination" 節、"...See Issue #1058 for the incident this rule generalizes from." で終わる段落の直後・"**Base propagation path per phase (exhaustive):**" の直前に、新規段落を追加する。内容として次の3点を明記する: (a) Comment Consumption Procedure (`modules/l0-surfaces.md`) は Spec の `## Consumed Comments` セクションへの書き込みを伴うため、これを呼び出すフェーズは必ず本モジュールの Entry セクションを先に実行しなければならないこと、(b) `skills/verify/SKILL.md` が既にこの順序 (Entry が Step 3、Comment Consumption Procedure 呼び出しが Step 4) を満たしていること、(c) `skills/code/SKILL.md` と `skills/spec/SKILL.md` は #1078 で Comment Consumption Procedure 呼び出しを各自の Worktree Entry Step 末尾に移動することでこの順序に整合させたこと。(after 1, 2) (→ 受入条件 AC2)
4. `python3 scripts/validate-skill-syntax.py skills/` を実行し、exit 0 (構文エラーなし) であることを確認する。(after 1, 2, 3) (→ 品質確認)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md と skills/spec/SKILL.md の両方について、Comment Consumption Procedure の実行と Worktree Entry (fresh baseRef) の実行順序矛盾を解消する対応 (例: Worktree Entry を先に実行する / 書き込みを worktree 作成後に遅延する / baseRef=head を使う、のいずれか) が含まれている" --> skills/code/SKILL.md と skills/spec/SKILL.md の両方で、Consumed Comments 書き込みと worktree 作成の順序矛盾が解消されている
- <!-- verify: grep "Comment Consumption" "modules/worktree-lifecycle.md" --> `modules/worktree-lifecycle.md` の Spec file write destination 節 (または関連箇所) が Comment Consumption Procedure との順序関係に具体的に言及している

### Post-merge

- 実際に `/code` および `/spec` を Issue に対して実行し、Comment Consumption Procedure で記録した Consumed Comments の内容が worktree ブランチ経由でコミットされた Spec に反映されていることを確認する <!-- verify-type: manual -->

## Notes

- **設計選択: 「Step 1/2 の全面入れ替え」ではなく「該当段落のみを Step 2 末尾へ移動」を採用した理由**: `skills/verify/SKILL.md` の前例 (Worktree Entry が独立した Step 3、Fetch+Consume+Handoff がまとめて Step 4) に完全に合わせるなら Step 1 全体と Step 2 全体を入れ替える方法もある。しかし `skills/code/SKILL.md` を調査した結果、Step 1/Step 2 という Step 番号そのものを参照する既存のクロスリファレンスが本文中に4箇所 (Scope: `skills/code/SKILL.md` 本文、`grep -n "Step 1\b\|Step 2\b" skills/code/SKILL.md` で確認 — "XS/S detection in Step 2" が Step 0 内、"already created by Worktree Entry (EnterWorktree) in Step 2" が Step 4 内に2箇所、"already fetched in Step 1" が Step 10 内)、`modules/worktree-lifecycle.md` に1箇所 ("`skills/code/SKILL.md` Step 2" — `ENTERED_WORKTREE=false` の説明) 見つかった。全面入れ替えはこれら5箇所すべての更新を要し、light spec の変更範囲としては過大かつ更新漏れのリスクを増やす。該当段落のみの移動なら Step 1 / Step 2 の見出し・スコープは変わらないため、これら5箇所は一切変更不要 (確認済み — 全て現状の記述のまま整合する)。AC1 の rubric が明示する3つの解決例のうち「書き込みを worktree 作成後に遅延する」に該当する。`skills/spec/SKILL.md` 側は同様のクロスリファレンスが存在しないため (Step 10 のテンプレート例示内の "Step 1"/"Step 2" のみで自己参照ではない)、いずれの方式でもリスクは小さいが、両スキルの一貫性のため同じ移動方式を採用した。
- **`baseRef=head` を採用しなかった理由**: `EnterWorktree` ツールスキーマを確認したところ、`baseRef` はツール呼び出し時の引数として公開されておらず (`name` / `path` のみ)、`worktree.baseRef` はセッション/グローバル設定 (`fresh` がデフォルト) としてのみ制御される。スキル本文から呼び出しごとに指定する手段がないため、この Issue のスコープでは採用しない。
- **`docs/spec/issue-*.md` の既存言及は対象外**: `grep -rn "Comment Consumption" docs/ tests/ scripts/` (Scope: 全ファイル種別、上記3ディレクトリ配下) で `docs/spec/issue-1058-*.md` (#1078 を既に前方参照済み)、`issue-705/811/774/998/1028/1109/1163-*.md` がヒットしたが、いずれも過去 Issue の凍結された Spec (disposable、`docs/tech.md` の "Spec-first (disposable)" 方針により完了後は更新しない) であり、Changed Files に含めない。`scripts/emit-event.sh:187` のコメントは `l0-surfaces.md` 内部の Step 6 (Emit event) を指しており、本 Issue が扱う呼び出し元スキルの Step 1/2 とは無関係のため対象外。
- **`docs/structure.md` の更新不要確認**: `docs/structure.md` の `append-consumed-comments-section.sh` の説明 (Key Files > Scripts) は Step 12 (code) / Step 12 (spec) の安全網呼び出しを指しており、今回移動する Step 1/2 の LLM 駆動 Comment Consumption Procedure 呼び出しとは別の呼び出し箇所である。今回の変更はこの安全網呼び出し自体に触れないため、`docs/structure.md` の更新は不要 (grep で該当行を確認済み、記述は現状のまま正確)。
- **本セッション自身での実地確認**: 本 Spec を作成した `/spec 1078` セッション自身が、修正前の Step 順序下で実行された。Step 1 (Comment Consumption) の時点では Issue #1078 自身の Spec ファイルが未作成だったため実害は発生しなかったが、`## Consumed Comments` セクションへの記録は本 Spec 作成 (Step 10、worktree entry 後) まで意図的に遅延させ、Issue が指摘する不整合を自セッションで再現しないようにした。この経験は Post-merge の手動確認条件と整合する一次情報である。
- **`modules/worktree-lifecycle.md` の Known gaps は対象外**: 同モジュールの既存 "Known gaps" (verify の `--no-push` 未対応、`/spec` Step 14 の `ENTERED_WORKTREE=false` 分岐が `worktree-merge-push.sh` を経由しない bare push である点) はいずれも Step 1/2 の順序とは無関係な既知の別課題であり、本 Issue のスコープ外として変更しない。

## Consumed Comments

- saito / MEMBER / first-class / `/issue 1078` 実行時の Issue Retrospective — スコープを `/spec` にも拡大、AC2 の verify command 強化 (`"Consumed Comments"` → `"Comment Consumption"`)、post-merge チェックボックス書式修正の根拠を記録。現行 main で `/code`・`/spec` 双方が未解消であることも確認済み / https://github.com/saitoco/wholework/issues/1078#issuecomment-5204156551
