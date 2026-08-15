# Issue #1132: verify-patterns: 診断メッセージ内の埋め込みコマンドにエスケープ妥当性の検証規約を追加

## Overview

診断メッセージ・エラーメッセージ・改善提案 (`IMPROVEMENT_HINT` 等) の中に、利用者がそのままコピー & ペーストして実行することを想定したコマンド文字列を埋め込むスクリプトについて、対応する bats アサーションが「パターン名の部分文字列一致」に留まり、埋め込みコマンド文字列そのものの内容 (エスケープ破損の有無) を検証していないという構造的ギャップを解消する。

`modules/verify-patterns.md` に新しい規約セクションを追加し、(a) この規約が発火する条件、(b) 具体的な検証手段 (`bash -n` によるシェル構文チェックと、それだけでは不十分な場合を補う内容レベルのチェック) を明示する。あわせて、既知の実例である `scripts/detect-wrapper-anomaly.sh` の `preview-deployment-absent` パターンの `IMPROVEMENT_HINT` (Issue #1128 で二重エスケープバグが発生し、`/review` の Workflow モードでのみ検知された箇所) に対して、`tests/detect-wrapper-anomaly.bats` へ回帰テストを追加する。

他の埋め込みコマンド箇所 (`modules/orchestration-fallbacks.md` のカタログ手順、各 `run-*.sh` の next-action メッセージ等) への規約の遡及適用は Out of Scope (Issue 本文参照)。

## Changed Files

- `modules/verify-patterns.md`: 新規セクション §30 を追加 (`## Output` 見出しの直前、既存 §29 の直後に挿入)
- `tests/detect-wrapper-anomaly.bats`: `preview-deployment-absent` の `IMPROVEMENT_HINT` に対する回帰テストを追加 (既存の "preview deployment absent" テストブロック直後、385 行目の `}` の直後・387 行目 "silent no-op: no false positive for code-patch..." の直前に挿入)
- Steering Docs sync candidate 確認済み (更新不要と判定): `docs/structure.md:110` (`modules/verify-patterns.md` の一行説明はセクション数を列挙しておらず、追加後も正確なまま)、`docs/environment-adaptation.md:471,487` (「Domain file 化して避けるべき」という規約は新規 capability 追加時のガイダンスコンテンツに限定されたスコープであり、本 Issue のような capability gate を持たない汎用規約には適用されない — 詳細は `## Notes`)

## Implementation Steps

1. `modules/verify-patterns.md` の `## Output` 見出し (既存ファイル末尾、§29 の直後) の直前に、新しい `### 30.` セクションを挿入する。見出し例: `### 30. Diagnostic Messages Embedding User-Executable Commands — Verify Shell Validity, Not Just Substring Presence`。以下の内容を含めること:
   - **Background**: `scripts/detect-wrapper-anomaly.sh` の `preview-deployment-absent` パターンの `IMPROVEMENT_HINT` に二重エスケープバグ (Issue #1128) が混入し、`tests/detect-wrapper-anomaly.bats` のパターン名部分文字列一致アサーションでは検知できず、`/review` の Workflow モードでのみ捕捉された実例を記載する。
   - **発火条件 (Trigger condition, AND 条件で3点)**:
     (a) スクリプトの診断・エラー・改善提案出力が、利用者がそのままコピー & ペーストして実行することを想定したコマンド文字列を埋め込んでいる (典型的にはバッククォートで囲まれたインラインコード、例: `` `gh api ...` ``) — 単なるキーワード・パス・パターン名ではないこと
     (b) その埋め込みコマンドがスクリプト自身のソース内で文字列展開・エスケープを経由して構築されている (ネストした引用符・バッククォートを含む bash のダブルクォート文字列リテラル等) — 編集時に静かに壊れうるエスケープ層が存在すること
     (c) 対応する bats テストが現状パターン名またはキーワードの部分文字列一致のみをアサートしている
   - **検証手段 (2段構え、いずれか一方だけでは不十分であることを明記)**:
     1. **シェル構文妥当性 (`bash -n`)**: 出力から埋め込みコマンド部分文字列を抽出し `bash -n <<< "$extracted_command"` (またはファイルに書き出して `bash -n <file>`) を実行し終了コード 0 を確認する。引用符の不対応・括弧の不一致・末尾の未完了バックスラッシュ継続など、構文として壊れているケースを検知する。
     - **既知の限界**: `bash -n` だけでは全てのエスケープ破損を検知できない。引用符の外側にあるバックスラッシュエスケープされた引用符 (`\"`) は bash にとって構文的に妥当 (単なるリテラル `"` 文字として扱われる) であるため、Issue #1128 で実際に発生した二重エスケープバグの形は `bash -n` に対して終了コード 0 を返してしまう (本 Spec 作成時に実機検証済み)。したがって `bash -n` 単独を十分条件として扱わず、必ず検証手段 2 と組み合わせること。
     2. **内容レベルのチェック**: 抽出したコマンドが期待するリテラル文字列と完全一致することをアサートする (`[[ "$extracted" == "expected literal command" ]]`)。動的な値を含むなどして期待リテラルの完全固定が実務上困難な場合は、代替として抽出コマンドに想定外のバックスラッシュ文字が含まれていないことをアサートする (`[[ "$extracted" != *'\'* ]]`) — 実装がシングルクォート引数のみで構成されエスケープを一切必要としない場合に適用できる。この検証手段 2 が、検証手段 1 (`bash -n`) だけでは検知できない「構文的には妥当だが意味的に壊れている」クラスのバグを捕捉する。
   - **推奨 bats パターン**: 安定したコマンド接頭辞 (例: `` `gh api[^`]*` ``) にアンカーした `grep -o` で埋め込みコマンドを抽出する (出力中の無関係なバッククォート区間を誤って捕捉しないよう、単純なバッククォートペア走査は避ける) → 完全一致アサーション → `bash -n` アサーション、の順に記載する。
   - **判断手順 (4ステップ)**: 上記の発火条件・検証手段を手順化して記載する。
   (→ acceptance criteria A, B, C)
2. (after 1) `tests/detect-wrapper-anomaly.bats` に以下の内容の新規 `@test` を追加する (挿入位置: 385 行目の既存 "preview deployment absent: no detection with only one of the two required strings" テストの `}` の直後、387 行目 "silent no-op: no false positive for code-patch..." の直前):

   ```bash
   @test "preview deployment absent: IMPROVEMENT_HINT embedded gh api command survives escaping intact" {
       printf 'PENDING: PR preview deployment not confirmed for PR #362 (branch=worktree-code+issue-334 state=none); skipping review session\n' > "$LOG_FILE"
       run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 2 --issue 1128 --phase review
       [ "$status" -eq 0 ]
       embedded_cmd=$(echo "$output" | grep -o '`gh api[^`]*`' | head -1 | sed 's/^`//; s/`$//')
       [[ "$embedded_cmd" == "gh api 'repos/:owner/:repo/deployments?per_page=1' --jq 'length'" ]]
       bash -n <<< "$embedded_cmd"
       [ "$?" -eq 0 ]
   }
   ```

   このテストは既存の `SCRIPT`/`LOG_FILE` 変数・既存のテストスタイル (4スペースインデント、`run bash "$SCRIPT" ...`) にそのまま従う。既存の "preview deployment absent" 系テスト (352-385 行目) はパターン名と `PREVIEW_URL` キーワードの部分文字列一致のみを検証しており、本テストが `IMPROVEMENT_HINT` の埋め込みコマンド内容そのもの (エスケープ破損の有無) を検証する初めてのアサーションとなる。
   (→ acceptance criteria D)
3. (after 2) `bats tests/detect-wrapper-anomaly.bats` をローカルで実行し、既存テスト全件と新規回帰テストが pass することを commit/push 前に確認する。
   (→ acceptance criteria E)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-patterns.md に、診断メッセージ・エラーメッセージ内へ利用者実行用のコマンド文字列を埋め込むスクリプトを対象として、bats アサーションを部分文字列の有無に留めず出力文字列のシェル妥当性 (エスケープ破損の検知) まで検証させる規約セクションが追加されている" --> `modules/verify-patterns.md` にエスケープ妥当性検証の規約セクションが追加されている
- <!-- verify: rubric "追加された規約が、どのようなスクリプト・出力を対象とするかの発火条件を判定可能な基準として明示している (例: 出力文字列にバッククォート・引用符で囲まれたコマンドを含む、利用者がコピー&ペーストして実行することを想定した文字列を生成する、等)" --> 規約に発火条件が判定可能な基準として明示されている
- <!-- verify: grep "bash -n" "modules/verify-patterns.md" --> 規約が具体的な検証手段 (`bash -n` によるシェル構文チェック等) を提示している
- <!-- verify: rubric "tests/detect-wrapper-anomaly.bats が IMPROVEMENT_HINT の内容そのものに対するアサーションを持ち、埋め込みコマンド文字列のエスケープが壊れていないことを検証している" --> 既知ケース (`scripts/detect-wrapper-anomaly.sh` の `IMPROVEMENT_HINT`) に規約が適用され、回帰テストが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テストが全て pass する (patch route — Step 18 の Size 再評価で S に更新され、PR が存在しないため `gh run list` 形式に修正)

### Post-merge

なし

## Notes

- **`docs/environment-adaptation.md` との整合性確認 (コンフリクトなしと判断)**: `docs/environment-adaptation.md:471,487` に「`modules/verify-patterns.md` へのガイダンスセクション追加は avoid し、代わりに Domain file 化すべき (`~1500 tokens/section` の eager-load コスト)」という記述がある。しかしこの規約は `### Extension Guide > Adding a new capability` セクション配下にあり、**新規 capability 追加時に capability 固有のガイダンス** (application scenarios, comparison with existing verify commands, decision criteria for adopting the capability) を対象とするものであり、`capabilities.*` gate を持たない汎用的な bats テスト設計規約には適用されない。本 Issue の規約は既存の §1-§29 (grep 誤検知パターン、rubric 使い分け等、いずれも capability gate なし) と同じ性質の汎用規約であり、conflict なしと判断した。
- **`bash -n` の限界に関する実機検証結果**: Spec 作成時に、Issue #1128 の実際の修正前コード (`\\\"` による二重エスケープ、PR #1131 のレビューコメント r3689276393 で指摘された形) を再現し `bash -n` に通したところ、終了コード 0 (構文エラーなし) が返ることを確認した。理由は、引用符の外側にあるバックスラッシュエスケープされたダブルクォート (`\"`) は bash にとって「リテラルの `"` 文字」として構文的に妥当であり、埋め込みコマンドの意味 (`gh api` に渡る引数) が壊れていても構文エラーにはならないため。この実機検証結果を踏まえ、規約は `bash -n` 単独ではなく内容レベルのチェックとの併用を必須とする設計とした (Implementation Step 1 参照)。
- **allowed-tools impact chain check**: `modules/verify-patterns.md` への追加内容は `scripts/detect-wrapper-anomaly.sh` を実例として文中で言及するのみで、新たな `scripts/*.sh` 呼び出し (Skill が実行する新規スクリプト起動命令) を導入するものではない。したがって `allowed-tools impact chain check` のゲート条件 (変更内容が `scripts/*.sh` パスへの新規呼び出しを含むか) には該当せず、`skills/*/SKILL.md` の `allowed-tools` 更新は不要と判断した。
- Implementation Step 2 の bats テストコードは、Spec 作成時に一時ファイル (`.tmp/` 配下、作業完了後に削除済み) で実際に `bats` 実行し、現行の (修正済み) 実装に対して pass することを確認済み。
- **Step 18 での Size 再評価と route 変更**: Spec の Changed Files が 2 件 (`modules/verify-patterns.md`, `tests/detect-wrapper-anomaly.bats`) のみであり、2軸判定法の Axis 1 (ファイル数) で Size S 相当と判定されたため、トリアージ時の Size M から S へ更新した (`modules/project-field-update.md` の手順で Project Size field を更新済み、read-back で確認済み)。これに伴い route が pr → patch に変わり、PR が存在しなくなるため、Issue 本文 AC5 の `github_check "gh pr checks" "Run bats tests"` は `modules/verify-classifier.md` § "Patch Route CI Verification Note" の正準形 `github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` に修正し、Spec と Issue 本文の両方に反映した。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class
  - 要約: `/issue` フェーズの Issue Retrospective コメント。Background のコードベース事実主張 (`PATTERN_NAME="preview-deployment-absent"` の実在、`tests/detect-wrapper-anomaly.bats` の該当アサーションが部分文字列一致のみで構成されている点) を確認済みと記録。曖昧性検出・自動解決 (スコープを規約新設 + 既知ケース回帰テストのみに限定し、他箇所への遡及適用は対象外とする判断) は Issue 本文の `## Auto-Resolved Ambiguity Points` / `## Out of Scope` に既に反映済みであり、本 Spec の設計に新たな追加対応は不要と判断した。
  - URL: https://github.com/saitoco/wholework/issues/1132#issuecomment-5304224803
