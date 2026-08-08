# Issue #1288: doc/audit: ドキュメント走査の除外パターン重複定義を共通 SSoT に集約

## Overview

`type: project` / `type: steering` の frontmatter を持つドキュメントを Grep で全リポジトリから収集する際の除外パターン一覧 (`$SPEC_PATH/`・`node_modules/`・`.git/`・`.tmp/`・翻訳出力の5項目) が、共通モジュール参照ではなく次の3箇所に独立コピーされている:

- `skills/doc/SKILL.md:87` (Document Traversal (common procedure) § Step 2)
- `skills/audit/SKILL.md:65` (drift サブコマンド § Load Project Documents § Step 2)
- `skills/audit/SKILL.md:677` (fragility サブコマンド § Load Project Documents § Step 2)

`grep -rn "Paths starting with \`\$SPEC_PATH/\`\|Paths containing \`node_modules/\`" skills/ modules/` で上記3箇所のみがヒットすることを確認済み (スコープ: `skills/` + `modules/` 配下、実装ファイル全体)。

#1283 (`docs/spec/issue-1283-doc-translation-frontmatter.md`) は翻訳出力除外の追加のためにこの3箇所を同時編集する必要があり、その Verify Retrospective の Improvement Proposal で「共通モジュール (`modules/` 配下) への切り出しと3箇所からの参照化を検討する」ことを明示的に記録していた。本 Issue はその切り出しを実施し、除外パターンの追加・変更が1箇所の編集で完結する状態にする。

## Changed Files

- `modules/doc-scan-exclusions.md`: 新規作成。frontmatter ベースのドキュメント走査 (`type: project` / `type: steering` Grep) で共通に使う除外パターン一覧の SSoT
- `skills/doc/SKILL.md`: 「Document Traversal (common procedure)」§ Step 2 のインライン除外パターン一覧 (5項目) を `modules/doc-scan-exclusions.md` への参照に置き換える
- `skills/audit/SKILL.md`: drift サブコマンド・fragility サブコマンドそれぞれの「Load Project Documents」§ Step 2 のインライン除外パターン一覧 (2箇所、各5項目、両者は文字列レベルで同一) を同モジュールへの参照に置き換える
- `docs/structure.md`: Directory Layout のモジュール数コメント (`(43 files)` → `(44 files)`) を更新し、Key Files § Modules の「Key modules:」一覧 (現在43件、実ファイル数と1:1対応) に新規モジュールのエントリを追加する。同ファイル冒頭の Maintenance rule 節が modules/ 配下のファイル追加時にこの更新と件数確認 verify command の追加を明示的に求めている
- `docs/ja/structure.md`: `docs/structure.md` の日本語ミラー。`docs/translation-workflow.md` の Sync Procedure により、トップレベル `docs/*.md` の変更は対応する `docs/ja/` ミラーへの反映が義務付けられている。モジュール数コメント (`（43 ファイル）` → `（44 ファイル）`、全角括弧表記) と「Key modules:」相当リストへのエントリ追加を、英語版と同じ内容で反映する

## Implementation Steps

1. `modules/doc-scan-exclusions.md` を新規作成し、既存3箇所 (doc/SKILL.md, audit/SKILL.md ×2) が持つ除外パターン一覧をこのファイルの「Processing Steps」節に集約する。文言は `skills/doc/SKILL.md` 側の説明的な版 (各項目に "(specification documents)" 等の注釈がある) を正本として採用する。既存の `modules/worktree-lifecycle.md` に倣い「Callers (auto-maintained)」節で参照元3箇所を明記する (→ acceptance criteria AC1, AC2, AC3)
2. `skills/doc/SKILL.md` の「Document Traversal (common procedure)」§ Step 2 を、インライン5項目リストから `Read \`${CLAUDE_PLUGIN_ROOT}/modules/doc-scan-exclusions.md\` and follow the "Processing Steps" section to skip excluded paths` 形式の参照1行に置き換える。Step 1/3/4 (Grep 収集・frontmatter 読み取り・type フィルタ) は変更しない (→ acceptance criteria AC1, AC2)
3. `skills/audit/SKILL.md` の drift サブコマンド (§ Load Project Documents § Step 2) と fragility サブコマンド (同名セクション § Step 2) の両方で、同じインライン5項目リストを手順2と同じ参照1行に置き換える (2箇所とも文字列レベルで同一の変更) (→ acceptance criteria AC1, AC2)
4. 採用案 (A: 新規共通モジュール) と不採用とした代替案 (B: audit から doc/SKILL.md への直接参照) の判断根拠を本 Spec の「Notes」節に記録する (Spec 作成時点で本節に記録済み。code フェーズでの追加作業は不要) (→ acceptance criteria AC4)
5. `docs/structure.md` の Directory Layout 内モジュール数コメント (`(43 files)` → `(44 files)`) を更新し、Key Files § Modules の「Key modules:」一覧に `modules/doc-scan-exclusions.md` のエントリ (`modules/doc-checker.md` の直後に配置) を追加する。`docs/translation-workflow.md` の Sync Procedure に従い、`docs/ja/structure.md` にも同内容 (`（44 ファイル）` への更新 + 対応エントリ追加) を反映する (→ acceptance criteria AC5)

## Verification

### Pre-merge

- <!-- verify: command "test $(grep -rn 'Paths containing' skills/ 2>/dev/null | wc -l | tr -d ' ') -eq 0" --> `skills/` 配下に除外パターンのインラインコピーが 1 件も残っていない
- <!-- verify: rubric "frontmatter ベースのドキュメント走査における除外パターンが単一の SSoT 箇所に定義されており、skills/doc/SKILL.md の Document Traversal・skills/audit/SKILL.md の drift・同 fragility の 3 箇所すべてがその SSoT を参照する形になっている" --> 3 箇所が共通の SSoT を参照している
- <!-- verify: rubric "統合後の除外パターンに、#1283 で追加された翻訳出力の除外 (docs/{lang}/ 配下および README.{lang}.md) が失われずに含まれている" --> #1283 が追加した翻訳出力除外が保持されている
- <!-- verify: rubric "採用案 (A または B) と不採用理由が Spec に記録されている" --> 案の採否が記録されている
- <!-- verify: command "grep -q '(44 files)' docs/structure.md && grep -q '（44 ファイル）' docs/ja/structure.md" --> docs/structure.md と日本語ミラー docs/ja/structure.md の両方でモジュール数コメントが更新されている

### Post-merge

- 次回 `/audit drift` または `/doc sync` 実行時に、Project Documents 収集へ `docs/{lang}/` 配下の翻訳ファイルが混入しないことを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### 案の採否

**採用: 案 A (新規共通モジュールへ切り出し)**

- **理由**: `docs/tech.md` の "Shared module pattern" (複数skillにまたがる共通処理は `modules/*.md` に切り出し、"Read and follow" パターンで参照する) という既存アーキテクチャ方針に合致する。加えて #1283 自身の Verify Retrospective の Improvement Proposal が既に「共通モジュール (`modules/` 配下) への切り出しと3箇所からの参照化を検討する」と明示的に推奨していた。
- **案 B (audit から `skills/doc/SKILL.md` への直接参照) を不採用とした理由**: Issue 本文が指摘する通り、skill が別 skill の SKILL.md セクションを直接参照する形は依存方向が不自然になる — `/audit` が `/doc` の内部実装詳細 (セクション名・構造) に依存することになり、将来 `/doc` 側でセクション名や構造を変更した際に `/audit` 側が予告なく壊れるリスクがある。`modules/*.md` は複数skillから参照されることを前提に設計された既存の共有レイヤーであり、そちらに切り出す方が依存方向として自然。

### スコープ判断: 除外パターンのみを切り出し、Document Traversal 手続き全体は移動しない

`skills/doc/SKILL.md` の「Document Traversal (common procedure)」という節名・節構造自体は維持し、その Step 2 (除外パターン部分) のみをモジュール参照に置き換える設計とした。

理由: 同ファイル内に「Follow the "Document Traversal (common procedure)" section...」という形でこの節を参照する箇所が既に4箇所 (Status Display § Step 1、init 関連1箇所、sync 関連2箇所) 存在し、加えて `skills/doc/translate-phase.md:19` からも同様に参照されている (`grep -n "Document Traversal" skills/doc/SKILL.md skills/doc/translate-phase.md` で確認済み)。節名・節の存在自体を変更すると、これら5箇所の参照文言も追随して更新する必要が生じ、Issue 本文が指摘する3箇所 (除外パターンの重複コピー) を大きく超えるスコープ拡大になる。除外パターンのリスト部分だけを独立したモジュールとして切り出すことで、この5箇所の既存参照には一切手を入れずに済む。

このスコープ判断の結果、AC1 の grep 判定式 (`grep -rn 'Paths containing' skills/`) は追加調整なしでそのまま機能する — 除外パターンのテキストが `skills/` 配下から完全に消え `modules/` 配下に移るため。Issue 本文の Notes が指摘していた「案 B を採る場合は AC1 の判定式調整が必要」という懸念は、案 B ではなく案 A を採用した今回の設計では発生しない。

### 対象外とした類似除外リスト (参考: `modules/doc-checker.md:52-53`)

`modules/doc-checker.md` (52-53行目) と `skills/doc/SKILL.md` の `sync --deep` 統合スキャン (341行目付近) にも "Translation output" 除外の記述があるが、いずれも Grep による全リポジトリ走査ではなく Glob ベースの別スキャン機構であり、除外項目の構成も異なる (前者は `$STEERING_DOCS_PATH` 配下限定のスキャンで `node_modules/`・`.git/`・`.tmp/` の除外を持たない、後者は `vendor/`・`skills/`・`modules/`・`agents/` など本 Issue の3箇所にはない除外項目を持つ)。Issue 本文が指摘する3箇所の完全一致コピーとは異なる別実装のため、本 Issue のスコープ外として変更しない。

### 除外パターンの文言統一

`skills/doc/SKILL.md` 側は各除外項目に括弧注釈 (例: "(specification documents)") が付いていたが、`skills/audit/SKILL.md` の2箇所には注釈がなかった (Translation output 項目のみ3箇所とも文字列レベルで同一)。SSoT 化にあたり、より説明的な `skills/doc/SKILL.md` 側の文言を正本として採用した (Implementation Step 1 に反映)。

### bats テスト追加の要否

`modules/doc-checker.md` には内容確認用の shallow bats テスト (`tests/doc-checker.bats`、frontmatter/契約文言の grep 確認のみ) が存在するが、同様のテストを持たないモジュール (`modules/worktree-lifecycle.md`・`modules/l0-surfaces.md`・`modules/detect-config-markers.md`・`modules/measurement-scope.md` 等) も多数あり、全モジュール共通の規約ではない。本 Issue の Acceptance Criteria もテスト追加を要求していないため、新規 bats テストの追加は見送った。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (issue フェーズ) — 「検討候補」節の案 A/B 選択は `/issue` vs `/spec` の責務境界に従い意図的に `/spec` へ委譲済みで追加解決なし、Post-merge observation AC に `session=next` 追加済み、Triage 結果 (Type: Task, Size: M, Value: 3) を記録。本 Spec の設計判断に対する追加の制約や変更なし / https://github.com/saitoco/wholework/issues/1288#issuecomment-5228136766
