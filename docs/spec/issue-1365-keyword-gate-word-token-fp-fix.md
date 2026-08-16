# Issue #1365: observation-trigger: keyword= ゲートの config-key/独立単語形式トークン誤検知を解消

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズ自身の Issue Retrospective。`/verify 476` re-run #19 で観測した第四のサブパターン (ベアファイル名参照) を Background に参考情報として追記した旨を記録。Purpose/AC 文言は変更なし / https://github.com/saitoco/wholework/issues/1365#issuecomment-5306089283
- (code phase) No new comments since last phase.
- (review phase) No new comments since last phase.

## Overview

Issue #476 の post-merge observation AC (`keyword=workflow`) は、#1220 (path-like token 除外) と #1293 (CLI-flag-like token 除外) の修正後も 18 回連続で誤発火/無関係発火を続けている (`docs/spec/issue-476-review-severity-classification.md` Verify Retrospective 参照)。原因は、`scripts/opportunistic-search.sh` の `resolve_filtered_context()` が除去する 2 種類のトークン形状 (`/` を含むパス様トークン、`--flag=value` 形式の CLI フラグ) のいずれにも該当しない**第三のサブパターン** — config-key 形式 (`capabilities.workflow`) やディレクトリ接頭辞のないベアファイル名 (`` `size-workflow-table.md` ``)、および独立した単語としての出現 (`Workflow path`) — が素通りするため。

本 Issue は、この第三のサブパターンのうち機械的に区別可能な部分 (config-key 形式・ベアファイル名 — いずれも `/` を含まない `word.word` 形状という共通の構造的マーカーを持つ) を根本修正し、機械的に区別不能な部分 (独立単語出現 — 構造的マーカーが一切ない) を設計上の受容として明文化する **ハイブリッド方針** を採用する (判断根拠は `## Notes` 参照)。

## Reproduction Steps

1. Issue の post-merge AC に `<!-- verify-type: observation event=<name> keyword=workflow -->` を設定する。
2. `--context-file` に渡す Spec/diff テキストに "workflow" という文字列を、config-key 形式 (`capabilities.workflow`) またはディレクトリ接頭辞なしのベアファイル名 (`` `size-workflow-table.md` ``) としてのみ含める (GitHub Actions ワークフローや `keyword=` が本来意図する概念への言及は含めない)。
3. `scripts/opportunistic-search.sh --event <name> --context-file <path>` を実行する。
4. 結果: 該当 Issue が誤って一致結果に含まれる。実測: Issue #476 の Verify Retrospective re-run #18 で `capabilities.workflow` 言及により、re-run #19/#20 でベアファイル名言及によりそれぞれ誤発火が確認されている。

## Root Cause

`scripts/opportunistic-search.sh` の `resolve_filtered_context()` (L249-261) は `sed -E` で 2 種類のトークン形状のみを除去する: (1) `/` を 1 つ以上含むパス様トークン (#1220)、(2) `--flag=value` 形式の CLI フラグ (#1293)。config-key 形式 (`capabilities.workflow`) やディレクトリ接頭辞のないベアファイル名 (`` `size-workflow-table.md` ``) はいずれも `/` も `--` も含まない `word.word` 形状のトークンであり、既存の 2 規則のどちらにも一致しないため素通りする。

一方、独立した単語としての出現 (`Workflow path` のような地の文中の単語) には除去可能な構造的マーカー (`/`・`--`・`.`) が一切存在せず、テキストの部分一致というこのゲートの設計 (`modules/observation-trigger.md` に明記された "No semantic/LLM judgment is performed here") の範囲内では原理的に区別不能である。

実装ロジックは手元の `sed` で実測検証済み (macOS BSD sed、`-E` 拡張正規表現): `capabilities.workflow` および `` `size-workflow-table.md` `` は新規パターンで完全に除去される一方、`Workflow path` (独立単語) と通常のプローズ中の "workflow" 言及は意図どおり除去されずに残る。新規パターンを CLI フラグ除去パターンより**前**に置くと `--workflow=test.yml` の値部分 (`test.yml`) だけが先に消費され `--workflow=` が残存し、#1293 が修正した誤検知が再発することも実測で確認した — 実装順序の妥当性は既存テスト「context gate: keyword found only inside a CLI flag token excludes the issue」が回帰防止として機能する。

## Changed Files

- `scripts/opportunistic-search.sh`: `resolve_filtered_context()` に 3 つ目の `sed -E` `-e` 節を追加 (config-key 形式・ベアファイル名の両サブパターンを一括で除去) し、関連する 3 箇所のコメントブロック (ファイル先頭の `--context-file` ゲート説明 L20-27、関数直前のコメント L240-245、ゲート適用箇所直前のインラインコメント L391-397) を更新
- `modules/observation-trigger.md`: 「CLI-flag-like token exclusion (Issue #1293)」段落の直後に、根本修正済みサブパターンを説明する新規段落「Config-key-format and bare-filename token exclusion (Issue #1365)」と、設計上の受容とするサブパターンを説明する新規段落「Accepted limitation — independent word occurrence」を追加。「Matching specification」節の `sed` コマンド例を 3 節構成に更新
- `tests/opportunistic-search.bats`: 新規 `@test` を 3 件追加 (config-key 形式トークン除外、ベアファイル名トークン除外、独立単語出現は引き続き一致に含まれることの回帰ロック)

## Implementation Steps

1. `scripts/opportunistic-search.sh`: `resolve_filtered_context()` (現在 L249-261) 内の `sed -E` 呼び出しに、既存 2 節の**後**に 3 節目の `-e` を追加する: `-e 's#[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+##g'` (`/` を要求せず、`word` + リテラル `.` + `word` の形状。文字クラス外で使う `.` は `\.` とエスケープすること — 文字クラス内の `.` はリテラル扱いだが、文字クラス外では正規表現メタ文字になるため)。**節の順序が重要**: CLI フラグ除去節より後に置くこと (Root Cause 参照 — 逆順だと #1293 の誤検知が再発する)。あわせて L20-27 (ファイル先頭のゲート説明コメント)、L240-245 (関数直前のコメント)、L391-397 (ゲート適用箇所直前のインラインコメント) の 3 箇所を、新しく除去するトークン形状 (config-key 形式・ベアファイル名) と Issue #1365 への参照を含むように更新する。bash 3.2+ 互換 (既存の `sed -E` パターンをそのまま踏襲) (→ 受入条件 1 の実装半分、受入条件 2)
2. `modules/observation-trigger.md`: 「CLI-flag-like token exclusion (Issue #1293)」段落 (現在 L205-214) の直後、「**Arguments table addition (both scripts):**」見出し (現在 L216) の直前に、以下 2 段落を追加する:
   - 「Config-key-format and bare-filename token exclusion (Issue #1365)」— 根本修正の内容 (両サブパターンが共有する no-slash `word.word` 構造、除去ロジック、節順序の重要性) を記述
   - 「Accepted limitation — independent word occurrence」— 独立単語出現が原理的に区別不能である理由と、`keyword=` 属性の推奨運用ガイドライン (より具体的/希少なトークンの選択。`[^ >]+` 抽出の制約上フレーズは選択不可である旨を明記。ファイル変更を対象とする条件には `.github/workflows/*.yml` のような changed-file-path ベースの構造化マッチへの移行を検討価値ありとして記録するが、本 Issue では未実装の deferred な方向性として明記) を記述
   
   あわせて「Matching specification」節 (現在 L222-228) の `sed` コマンド例 (2 節) を 3 節構成に更新する (→ 受入条件 1、受入条件 2 の設計上の受容部分)
3. `tests/opportunistic-search.bats`: 既存テスト「context gate: keyword found in prose text alongside a CLI flag token still includes the issue」(現在 L338-348) の直後に、以下 3 件の新規 `@test` を追加する:
   - `"context gate: keyword found only inside a config-key-format token excludes the issue"` — context file に `capabilities.workflow` のみを含め、`keyword=workflow` が除外されることを検証
   - `"context gate: keyword found only inside a bare filename token excludes the issue"` — context file に `` `size-workflow-table.md` `` のみを含め、`keyword=workflow` が除外されることを検証
   - `"context gate: keyword found as an independent word in prose still includes the issue"` — context file に "the Workflow path" のような地の文中の独立単語のみを含め、`keyword=workflow` が引き続き一致に含まれることを検証 (設計上の受容の回帰ロック)
   
   (→ 受入条件 3)

## Verification

### Pre-merge
- <!-- verify: rubric "modules/observation-trigger.md に、config-key 形式 (例: capabilities.workflow) や独立単語としてのキーワード出現が、path-like/CLI-flag-like トークン除去では対処できない第三のサブパターンとして明記され、対応方針 (根本修正または設計上の受容) が記録されている" --> 第三のサブパターンと対応方針が明文化されている
- <!-- verify: rubric "対応方針が根本修正の場合は scripts/opportunistic-search.sh に該当ロジックが実装されている。設計上の受容の場合は keyword= 属性の推奨運用 (より具体的な文字列選択、または .github/workflows/*.yml のようなファイルパスベースの条件式への移行提案) が modules/observation-trigger.md に記載されている" --> 対応方針に沿った実装またはガイドラインが反映されている
- <!-- verify: command "bats tests/opportunistic-search.bats" --> 既存 bats テストが green (新規ケース追加時を含む)

### Post-merge
- Issue #476 の post-merge AC (`event=pr-review-light keyword=workflow`) が次回以降の `/review --light` 完了時に UNCERTAIN 以外の恒久的な判定経路に到達する (PASS、または設計上の受容を反映した別の判定) ことを観察 <!-- verify-type: observation event=pr-review-light keyword=workflow -->

## Notes

**Issue #476 の状態変化 (実装時の重要な前提条件)**: 本 Spec 作成時点 (2026-08-16) で `gh issue view 476` を実行し、Issue #476 が既に `state: CLOSED` / `labels: ["triaged","phase/done","type/task"]` — つまり `phase/verify` から `phase/done` へ既に遷移済みであることを確認した。`docs/spec/issue-476-review-severity-classification.md` の Verify Retrospective (re-run #20) によると、19 回連続 UNCERTAIN の後、20 回目の re-run で PASS に到達している。ただし re-run #20 自身の記録が明記する通り、その回のディスパッチ根拠は本 Issue が対象とする第四サブパターン (ベアファイル名 `` `workflow-guidance.md` `` への部分一致) であり、「ゲート自体は今回も誤発火していたが、発火先の PR がたまたま Issue #476 の対象シナリオを独立に含んでいた」という偶然の一致で PASS に到達したものである。

この状態変化により、本 Issue の Post-merge AC (「Issue #476 の post-merge AC が…恒久的な判定経路に到達することを観察」) は文字通りには**もはや観測不能**になっている可能性が高い — `opportunistic-search.sh` の母集団取得 (`gh issue list --label "phase/verify" --state all`) は `phase/verify` ラベルの現存を条件とするため、`phase/done` へ遷移済みの Issue #476 は今後の母集団に含まれない。SPEC_DEPTH=light + non-interactive のため Issue 本文の Post-merge AC 自体は変更していない (Step 7 ambiguity resolution は light では skip され、これは字句上のあいまいさではなく実装後に生じた状態変化のため) が、`/verify` がこの AC を評価する際にはこの前提を踏まえた判断が必要になる可能性が高いことをここに記録する。

**設計判断 (根本修正 vs 設計上の受容): ハイブリッド採用の根拠**:
- config-key 形式 (`capabilities.workflow`) とベアファイル名 (`` `size-workflow-table.md` ``) は、いずれも `/` を含まない `word.word` 形状という共通の構造的マーカーを持ち、機械的に区別・除去可能 — 既存の path-like/CLI-flag-like 除外と同じ設計哲学 (構造的トークンはプローズではないと推定してストリップする) の自然な拡張であるため、根本修正 (トークン除去ロジックの拡張) を採用した。
- 実際の `keyword=` 使用状況を `gh search issues --repo saitoco/wholework "keyword="` で確認したところ、現行のバックログで `keyword=` の実値として使われているのは `workflow` (Issue #476) のみであり、`.` を含む値は存在しない — 新規ストリップ規則が既存の正当な `keyword=` マッチを破壊するリスクはないと判断した。
- 独立単語出現 (`Workflow path` のような地の文中の単語) には除去可能な構造的マーカーが一切なく、原理的に区別不能 (Issue 本文の Purpose が想定する「テキストの部分一致だけでは原理的に区別が困難な場合がある」ケースそのもの) — このサブパターンは設計上の受容とし、`modules/observation-trigger.md` に運用ガイドライン (より具体的なトークン選択、および構造化マッチへの移行提案) を明記する。

**allowed-tools impact chain check (Case 2 — modules/*.md)**: `modules/observation-trigger.md` への追加段落は既存の `opportunistic-search.sh` への言及を含むが、新規スクリプト呼び出しの追加ではない (同スクリプトは変更前から本モジュールの主題として全体にわたって参照されている) ため、reader SKILL.md の `allowed-tools` 更新は不要と判断した。

**Fail-safe critical script identification**: `scripts/opportunistic-search.sh` は `2>/dev/null || true` パターンを含む (`grep -nF` で確認、L259 ほか)。本 Issue の変更は `resolve_filtered_context()` 内の同一 `sed -E` 呼び出しに `-e` 節を 1 つ追加するのみであり、この呼び出しは変更前から既存の `|| true` フォールバックで保護されている (sed 失敗時は `FILTERED_CONTEXT=""` となり、空文字列に対する `grep -qi` は不一致 → ゲートは除外側 (fail-closed) に倒れる、既存の意図した挙動)。新しい失敗モードを導入しないため、追加のエッジケース挙動記述は不要と判断した。

**New test case requirement 要約 (Step 13 は SPEC_DEPTH=light のため skip — ここに要約を記録)**: Implementation Step 1 (`resolve_filtered_context()` への `-e` 節追加) は新規分岐ロジックであるため、Implementation Step 3 で `tests/opportunistic-search.bats` に新規 `@test` を 3 件追加する: (a) config-key 形式トークンのみでの一致は除外される、(b) ベアファイル名トークンのみでの一致は除外される、(c) 独立単語としての出現は引き続き一致に含まれる (設計上の受容の回帰ロック)。

両サブパターンが共有する「`/` を含まない `word.word` 形状」という構造的類似性に気づいたことで、2 つの具体例 (config-key・ベアファイル名) を単一の sed 節で一括対応できた — 個別に対応する場合よりシンプルな実装になった。

## Autonomous Auto-Resolve Log

- **Step 3 (`phase/ready` label check)**: `phase/ready` ラベルが不在だったが、`gh api .../timeline` で確認したところ `phase/ready` → `phase/code` への遷移は既に完了しており (2026-08-16T06:47:08Z)、Spec ファイルも既に存在していた。これは前回の `/code` 実行がラベル遷移まで到達したものの、PR 作成前に (worktree・remote branch とも残存なし) 中断されたことを示唆する。non-interactive mode の auto-resolve ポリシーに従い、既存 Spec を使って続行した。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Step 1〜3 を Spec の記述順どおりに実装した。節順序 (CLI フラグ節の後に config-key/ベアファイル名節を配置) や sed パターンも Spec の Root Cause / Implementation Step 1 の指示をそのまま採用した。

### Design Gaps/Ambiguities
- N/A — Spec の Notes (ハイブリッド採用の根拠、`keyword=` 実値調査結果、fail-safe 確認) が実装判断に必要な材料を既に揃えていたため、新規の曖昧さ解消は発生しなかった。

### Rework
- N/A

### Pre-implementation FAIL Check
- 新規追加した 3 `@test` のうち、string-matching assert を持つ 2 件 (config-key 形式トークン除外、ベアファイル名トークン除外) について、実装対象ファイル (`scripts/opportunistic-search.sh`) を `git stash` で実装前状態に戻して実行し、FAIL することを確認した。独立単語出現の回帰ロックテストは実装前後で PASS のまま (既存動作を変えない設計上の受容のため、当然の結果)。

### Behavioral Change Detection
- `tests/check-known-events-firing.bats` が `scripts/opportunistic-search.sh` を参照していたため behavioral change と判定し、フルスイート (`bats --jobs 18 tests/`, 1806 件) を実行した。1 件 pre-existing FAIL (`tests/code.bats`: "Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route" — `skills/code/SKILL.md` の記述と test 期待文字列の不一致) を検出したが、本 Issue が変更した3ファイルとは無関係で、既存の重複 Issue #1377 で追跡済みのため follow-up Issue の新規起票はスキップした。pr route の Step 9 FAIL handling に従い、CI が同じ FAIL を検出する前提でこのまま続行した。

## review retrospective

### Spec vs. implementation divergence patterns
- Spec の Root Cause 節は「実装ロジックは手元の sed で実測検証済み」と記載していたが、この実測は Issue 本文が挙げる 2 セグメント例 (`capabilities.workflow`) のみを対象としており、Overview/Purpose が掲げる「config-key 形式トークン」というクラス全体 (任意深さのネストを含む) を代表するテストケースではなかった。結果として、`/code` 側の rubric 自己採点 (Pre-merge AC 3 件 PASS 判定) は「3 セグメント以上の dot-chain (`capabilities.a.workflow` 等) では第 3 sed 節が完全に除去できない」という回帰再導入ギャップを検出できなかった。`/review` の Parser/Validator Edge Case Pre-check (実コード実行) がこのギャップを捕捉し、`/review` 内で修正済み (commit 445974b3)。今後、「根本修正」を謳う Spec では、実測検証の対象を Issue 本文の代表例 1 件だけでなく、パターンの構造的バリエーション (ネスト深さ・境界条件) を最低限含めるよう Root Cause / Implementation Steps に明記することを推奨する。

### Recurring issues
- 同じ `keyword=` ゲートの誤検知修正は本 Issue で 3 件目 (Issue #1220: path-like トークン、#1293: CLI-flag-like トークン、#1365: config-key/bare-filename トークン)。いずれも Issue #476 の実観測で見つかった具体例 1 件を起点に sed 節を追加する形で修正されており、修正後の検証も概ね同じ具体例に限定されていた。これは「同じ構造的欠陥のクラス (`sed -E` の単発マッチが構造的バリエーションを網羅しない) が毎回別のトークン形状で再発する」パターンであり、Parser/Validator Edge Case Pre-check (Issue #1055 起源) がまさにこの再発パターンを検出する目的で `/review` に組み込まれていることを、本件は実例として裏付けた (発火条件 (a)/(c) に合致し、実際に未文書化のギャップを 2 件検出)。既存の仕組みが機能した事例であり、新規の改善提案は不要と判断する。

### Acceptance criteria verification difficulty
- rubric AC2 の文言 (「対応方針に沿った実装...が反映されている」) は、根本修正の「完全性」(全深さのネストを正しく処理するか) までは明示的に要求していなかったため、rubric grader (および `/code` の自己採点) が 2 セグメント例のみのテストで PASS 判定を出せてしまう余地があった。`modules/verify-executor.md` の rubric ガイドライン (「セキュリティ関連のサブフィールドを明示的に rubric 文言に含める」原則) と同様に、「トークン形状クラスの根本修正」を検証する rubric 文言には、代表的な境界条件 (例: 「2 セグメントおよび 3 セグメント以上のネストの両方で正しく除去されること」) を明示的に含めることが望ましい。次回同種の Issue (`keyword=` ゲート系) を起票する際の Acceptance Criteria 文言作成時に反映を検討する。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #1384 は mergeable=true (CI success / review approved)、pre-merge AC ゲートは unchecked 0 件・review_incomplete_fallback なしで通過したため、conflict 解決や auto-resolve を経由せずそのまま squash merge した。
- squash merge 後、worktree を `origin/main` (commit 1007a888) へ ff-only で追従させ、Phase Handoff をこのコミットに含めて `main` へ直接コミット・push する。

### Deferred Items
- 先頭ドット単一セグメントトークン (`.workflow`) が `keyword=` ゲートで除去されない件は未対応のまま。実際に問題化した場合は別 Issue で対応を検討する。
- Post-merge AC (`event=pr-review-light keyword=workflow` の観測) は Issue #476 が既に `phase/done` へ遷移済みのため文字通りには観測不能な可能性が高い。`/verify` はこの前提を踏まえて判定する必要がある。
- 本 Issue とは無関係な pre-existing test FAIL (`tests/code.bats` の Step 10 branch-scoped CI AC exclusion アサーション、Issue #1377 で追跡済み) は今回の PR でも CI 上に現れる可能性があるが、本 Issue の変更に起因するものではないため対応不要。

### Notes for Next Phase
- `/verify` は Post-merge AC (`keyword=workflow` 観測) について、Issue #476 が既に `phase/done` である前提を踏まえた判定が必要 (詳細は上記 Deferred Items 参照)。
- `/verify` は本 PR に review フェーズでの追加修正 commit 445974b3 (3 セグメント以上のネスト config-key チェーン対応) が含まれていることを踏まえ、squash merge commit 1007a888 の内容で判定すること。
