# Issue #73: ci: DCO (Developer Certificate of Origin) を導入

## Overview

DCO (Developer Certificate of Origin) を Wholework に導入し、将来の運用層/商用事業への法的リスクを事前に防衛する。具体的には:

1. `.github/workflows/dco.yml` を新設し `tim-actions/dco` で PR の全 commit に `Signed-off-by:` を要求
2. `CONTRIBUTING.md` を新規作成し DCO の説明と `git commit -s` の使い方を明記
3. `README.md` に `## Contributing` セクションを追加（`## License` 直前）
4. wholework skills / modules が生成する内部 commit テンプレートを `git commit -m` → `git commit -s -m` へ一括更新（`Signed-off-by:` は git config の user に従って自動付与）

Issue Q&A で確定した方針:
- 実装: `tim-actions/dco`（カスタム grep / dcoapp/action より実績優位）
- Author: git config の user（`-s` による自動付与、Co-Authored-By: Claude trailer は併記維持）
- 対象範囲: SKILL.md / module 内の commit 生成箇所（scripts/*.sh には該当 0 件のためスコープ是正）
- `allowed-tools`: 既存の `Bash(git commit:*)` ワイルドカードで `-s` をカバー、追加変更不要

## Changed Files

- `.github/workflows/dco.yml`: 新規作成。`tim-actions/dco@master` を使用し PR の全 commit に `Signed-off-by:` を要求
- `CONTRIBUTING.md`: 新規作成。DCO 本文リンク + `git commit -s` 基本用法 + `git commit --amend -s` の既存コミット追記手順 + `git config --global format.signoff true` 永続設定 tips
- `README.md`: `## License` の直前に `## Contributing` セクションを新設し DCO 採用旨と `CONTRIBUTING.md` への誘導を記載
- `skills/code/SKILL.md`: 行 263, 373 の `git commit -m` を `git commit -s -m` に変更
- `skills/spec/SKILL.md`: 行 523, 574 の `git commit -m` を `git commit -s -m` に変更
- `skills/review/SKILL.md`: 行 534, 704 の `git commit -m` を `git commit -s -m` に変更
- `skills/review/external-review-phase.md`: 行 47, 88, 128 の `git commit -m` を `git commit -s -m` に変更
- `skills/verify/SKILL.md`: 行 371 の `git commit -m` を `git commit -s -m` に変更
- `skills/auto/SKILL.md`: 行 183, 230 の `git commit -m` を `git commit -s -m` に変更
- `skills/doc/translate-phase.md`: 行 144 の `git commit -m` を `git commit -s -m` に変更
- `modules/doc-commit-push.md`: 行 26 の `git commit -m` を `git commit -s -m` に変更

## Implementation Steps

1. `.github/workflows/dco.yml` を新規作成する（→ 受入条件 1）
   - トリガ: `pull_request` イベント
   - ジョブ名: `DCO` (CI で明示的に `DCO` と表示されるよう設定)
   - 使用 Action: `tim-actions/dco@master`
   - 必要な permissions: `pull-requests: read` 程度で十分
   - 参考スニペット:
     ```yaml
     name: DCO
     on: pull_request
     jobs:
       dco:
         name: DCO
         runs-on: ubuntu-latest
         steps:
           - uses: actions/checkout@v4
             with:
               fetch-depth: 0
           - uses: tim-actions/dco@master
     ```

2. `CONTRIBUTING.md` を新規作成する（→ 受入条件 2, 3）
   - 冒頭: プロジェクト概要 + Contributions welcome 文言
   - `## Developer Certificate of Origin (DCO)` セクション: DCO の目的（IP hygiene / 法的防衛）、`developercertificate.org` へのリンク、CI で `Signed-off-by:` を強制する旨
   - `### How to sign off` サブセクション:
     - 通常コミット: `git commit -s -m "message"`
     - 既存コミット追記: `git commit --amend --no-edit -s`
     - 永続設定: `git config --global format.signoff true`
   - `### What Signed-off-by means` サブセクション: DCO 本文の要約（自分にこのコードを提出する権利があることの明示）
   - CLA との違いは明示的に書かず、DCO 採用の事実のみ簡潔に提示

3. `README.md` に `## Contributing` セクションを追加する（→ 受入条件 4）
   - 追加位置: `## License` の直前
   - 内容例:
     ```markdown
     ## Contributing

     Contributions require a DCO sign-off on every commit. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.
     ```

4. wholework skills / modules の内部 commit テンプレートを `-s` 付きに一括更新する（→ 受入条件 5）
   - 対象箇所（Grep 確認済み、exhaustive）:
     - `skills/code/SKILL.md` 行 263（`git commit -m "{prefix} <summary>`）, 行 373（`"Add code retrospective for issue #$NUMBER`）
     - `skills/spec/SKILL.md` 行 523（`"Add design for issue #$NUMBER"`）, 行 574（`"Add retrospective notes for issue #$NUMBER"`）
     - `skills/review/SKILL.md` 行 534（`"Address review feedback: {fix summary}"`）, 行 704（`"Add review retrospective for issue #$ISSUE_NUMBER`）
     - `skills/review/external-review-phase.md` 行 47（`"Address Copilot review: {fix summary}"`）, 行 88 / 行 128（いずれも Copilot/CodeRabbit レビュー修正の commit）
     - `skills/verify/SKILL.md` 行 371（`"Add verify retrospective for issue #$NUMBER`）
     - `skills/auto/SKILL.md` 行 183（`"Add issue retrospective for issue #$NUMBER`）, 行 230（`"Add auto retrospective for issue #$NUMBER`）
     - `skills/doc/translate-phase.md` 行 144（`"docs: regenerate {lang} translations`）
     - `modules/doc-commit-push.md` 行 26（`"docs: ${SUMMARY}`）
   - 各箇所で `git commit -m "..."` → `git commit -s -m "..."` へ機械的置換
   - narrative 表記の箇所（`skills/review/SKILL.md:534` "**Commit with \`git commit -m ...\`**" 等）は inline code 内も含めて置換

## Verification

### Pre-merge

- <!-- verify: file_contains ".github/workflows/dco.yml" "tim-actions/dco" --> `.github/workflows/dco.yml` に `tim-actions/dco` を使用した Signed-off-by チェック workflow が実装されている
- <!-- verify: file_contains "CONTRIBUTING.md" "Signed-off-by" --> CONTRIBUTING.md が新規作成され DCO の説明と `Signed-off-by:` の意味が記載されている
- <!-- verify: file_contains "CONTRIBUTING.md" "git commit -s" --> CONTRIBUTING.md に `git commit -s` の使い方（初回、`--amend` での追加、設定 tips）の具体例が記載されている
- <!-- verify: file_contains "README.md" "DCO" --> README.md の Contributing 関連セクションまたはフッターに DCO を採用している旨が明記されている
- <!-- verify: file_contains "skills/code/SKILL.md" "git commit -s" --> wholework skills/modules 内の `git commit -m` テンプレートが `git commit -s -m` 形式に更新されている（`skills/code/SKILL.md` を代表とし、他 `skills/spec/`, `skills/review/`, `skills/verify/`, `skills/auto/`, `skills/doc/translate-phase.md`, `modules/doc-commit-push.md` も同様に更新）

### Post-merge

- 新規 PR の CI に `DCO` check が表示される <!-- verify-type: opportunistic -->
- `Signed-off-by:` なしの commit を含む PR で DCO check が FAIL する <!-- verify-type: opportunistic -->
- `Signed-off-by:` 付き commit の PR で DCO check が PASS する <!-- verify-type: opportunistic -->

## Notes

- **allowed-tools 変更不要**: 各 skill の `allowed-tools` は `Bash(git commit:*)` ワイルドカードのため `git commit -s -m ...` も許可済み。追加変更不要。
- **Author 実態の扱い**: `git commit -s` は現在の git config の `user.name` / `user.email` から自動的に `Signed-off-by:` を付与する。開発者のローカル環境設定がそのまま利用される。Co-Authored-By: Claude trailer は従来通り commit message 本文に併記（DCO の sign-off は実人保証、Co-Authored-By は制作者の記録で目的が異なるため共存）。
- **narrative 表記の置換漏れ注意**: `skills/review/SKILL.md:534` の `**Commit with \`git commit -m ...\`**` のような inline code（backtick で囲まれた文字列）も対象。単純 sed 置換だとマッチしない場合があるため、Edit ツールで per-file 確認推奨。
- **`docs/ja/*` は対象外**: 翻訳出力ファイル（`/doc translate ja` 生成）のため実装対象外。同様に `README.ja.md` も対象外。
- **既存履歴の sign-off 遡及**: 既存コミットに遡及適用するには `git rebase -i --signoff` が必要だが、本 Issue スコープ外（CI は新規 PR のみチェック、既存コミットは `tim-actions/dco` のデフォルト設定次第。本 Spec は新規 PR からの適用のみを想定）。
- **DCO check の scope**: `tim-actions/dco@master` は PR に含まれる全 commit を検査。既存 main の commit は対象外。将来 main のリライトが必要になった場合は別 Issue で対応。
- **`settings.json` の `Skill(...)` 変更**: 不要（既存 skills への commit template 変更のみ、新 skill 追加なし）。

## Code Retrospective

### Deviations from Design

- `skills/review/external-review-phase.md` の行 88, 128 は Spec で「`git commit -m` を `git commit -s -m` に置換」と記載されていたが、実際のファイルには `git commit -m` が存在せず `Commit message: "..."` 形式だった。意図を補完し、7.4/7.6 セクションのコミット記述を `Commit with \`git commit -s -m ...\`` 形式に統一した（7.2 との形式一貫性も向上）。

### Design Gaps/Ambiguities

- Spec の行番号（88, 128）は実際のファイル内容と一致しなかった。`git commit -m` のGrepで確認したところ line 47 のみが該当。Spec 作成時の行番号ズレと推定。

### Rework

- N/A

## review retrospective

### Spec vs. implementation divergence patterns

- `dco.yml` の実装において、Spec は `tim-actions/dco@master` の使用を指定していたが、Spec・Issue ともに `tim-actions/get-pr-commits` との組み合わせが必要な点（`commits` 入力が `required: true`）を記載していなかった。Specに外部Actionの正しい使い方（必要な前ステップ含む）を明記しておく必要がある。

### Recurring issues

- 特になし。外部Actionの誤用は `dco.yml` のみで発生した。

### Acceptance criteria verification difficulty

- verify command はすべてファイル内容チェック（`file_contains`）のため PASS 判定は容易だった。しかし受け入れ条件「`.github/workflows/dco.yml` に `tim-actions/dco` を使用した Signed-off-by チェック workflow が実装されている」という条件はファイルの存在と文字列の有無のみを検証しており、Actionが正しく動作するかどうか（`commits` 入力が適切に渡されているか）まで検証できていない。CI FAILがなければ見落としていた可能性がある。Verify command で `github_check` を使った CI PASS 検証を追加する改善余地がある。
