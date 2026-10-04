# Issue #1502: scripts: 未使用の check-file-overlap.sh を削除

## Overview

`scripts/check-file-overlap.sh` は XL 親 Issue の子 Issue 同士で変更ファイルが重なるかを調べるスクリプトだが、skills / modules / agents / scripts のいずれからも呼び出されておらず、導入以来 skills / modules から呼ばれた履歴も無い。加えて、Spec から変更ファイルを抽出する見出しが旧形式 (`## 変更対象ファイル`) のままで、現行の Spec 形式 (`## Changed Files`) に対しては常に `{"overlaps": []}` を返す。`docs/structure.md` の Key Files の説明 (`detect file overlap between repos`) も実態と違う。

#1493 (`get-verify-permission.sh`) と同じ未使用スクリプトの状態であり、同じ解決方針 (削除) を採る。スクリプト・テスト・`docs/structure.md` のエントリ (と日本語ミラー)・`.claude/settings.json.template` の allow 行を削除し、実装と文書を一致させる。方針は Issue 本文の「Auto-Resolved Ambiguity Points」で確定済みで、`/auto` の XL 並列実行から利用する案は採らない。

## Changed Files

- `scripts/check-file-overlap.sh`: 削除 (`git rm`)。skills / modules / agents / scripts からの呼び出しは 0 件。削除のみで新規ロジックは無いため、bash 互換性の考慮は不要
- `tests/check-file-overlap.bats`: 削除 (`git rm`)。削除するスクリプト専用のテスト
- `.claude/settings.json.template`: allow 行 `"Bash(scripts/check-file-overlap.sh *)",` を 1 行削除する。配列の途中要素のため、削除しても末尾カンマの問題は起きない。`.claude/` 配下は Edit / Write ツールが拒否されるため Bash (`python3`) で編集し、`git add` は `-f` を付ける
- `docs/structure.md`: (1) Key Files の Tooling 節で `scripts/validate-skill-syntax.py` エントリの直後にある `scripts/check-file-overlap.sh` エントリ行を削除する。(2) Directory Layout の `scripts/` 行コメント `(98 files)` を `(97 files)` に、`tests/` 行コメント `(134 files)` を `(133 files)` に更新する
  - [Steering Docs sync candidate] listing-side サブチェックの対象 (`ssot_for: directory-layout` を持つ文書)。Key Files のエントリと Directory Layout のファイル数コメントを再確認する
- `docs/ja/structure.md`: 英語版と同じ 3 箇所 (Key Files のエントリ行の削除、`(98 ファイル)` → `(97 ファイル)`、`(134 ファイル)` → `(133 ファイル)`) を同期する。`docs/translation-workflow.md` の同期手順に従う翻訳同期であり、Issue の AC の検証対象外

### Steering Docs sync candidate の評価結果

- [Steering Docs sync candidate] keyword "check-file-overlap.sh" skipped: matched 12 files (no discriminating power)。測定範囲: `grep -rl "check-file-overlap.sh" docs/ tests/ scripts/ modules/`。ヒットの大半は過去 Spec のため、個別評価はしない。代わりに下記の symbol impact 列挙 (Notes の「参照点」) で全ヒットを分類した
- listing-side サブチェック: 候補は `docs/structure.md` (上記 Changed Files に反映済み) と `README.md`。`README.md` は `grep -n -E "scripts/|tests/|[0-9]+ (files|scripts|tests)|[0-9]+ ファイル" README.md` が 0 件で、scripts / tests の列挙もファイル数コメントも持たないため変更不要
- outbound pointer サブチェック: `docs/structure.md` が指す `modules/verify-patterns.md` § "Literal Numeric Pinning ACs" などは今回の削除と無関係で、更新が必要な参照先は無い
- `docs/migration-notes.md` / `docs/ja/migration-notes.md`: 候補から除外する。本 Issue は CLI シグネチャ・フラグ・引数順の変更を含まず、該当する `#### check-file-overlap.sh` 節は Issue #9 の移植履歴 (歴史的記録) のため。Issue の rubric も同記録を除外している

## Implementation Steps

1. `scripts/check-file-overlap.sh` と `tests/check-file-overlap.bats` を `git rm` で削除する (→ 受け入れ条件 1, 2)
2. `.claude/settings.json.template` の allow 行 `"Bash(scripts/check-file-overlap.sh *)",` を削除する (→ 受け入れ条件 4)
   - `python3` で該当 1 行 (改行を含む) を `str.replace` で空文字に置換し、置換前後で内容が変わったことを `assert` で確認する (行が既に無い場合に黙って通らないようにするため)
   - 編集後に `python3 -c "import json; json.load(open('.claude/settings.json.template'))"` で JSON が壊れていないことを確認する
   - `.claude/` 配下のため、コミット対象への追加は `git add -f` を使う (`git add` では黙ってスキップされるおそれがあるため)
3. `docs/structure.md` を更新する (parallel with 1, 2) (→ 受け入れ条件 3, 6)
   - Key Files の `scripts/check-file-overlap.sh` エントリ行を削除する
   - Directory Layout の `scripts/` と `tests/` のファイル数コメントを、変更前の値からそれぞれ 1 ずつ減らす
   - 減算後の値が実数と一致することを `find scripts -maxdepth 1 -type f | wc -l` と `find tests -maxdepth 1 -type f | wc -l` で確認する (削除済みの状態で測る)
4. `docs/ja/structure.md` を step 3 と同じ 3 箇所で同期する (after 3)。`docs/translation-workflow.md` の手順 5 に従い、コードフェンス (```) の数が英語版と一致することを確認する (→ 翻訳同期。AC の検証対象外)
5. 取り残し確認と全体テストを行う (after 1, 2, 3, 4) (→ 受け入れ条件 5, 7)
   - `git grep -n "check-file-overlap" -- skills modules agents scripts tests .claude docs/structure.md` が 0 件であること
   - `bats tests/` を実行する。ローカルに bats が無い場合は Notes の「AC 7 の扱い」に従い、push 後の CI 結果で確認する

## Verification

### Pre-merge

- <!-- verify: file_not_exists "scripts/check-file-overlap.sh" --> `scripts/check-file-overlap.sh` が削除されている
- <!-- verify: file_not_exists "tests/check-file-overlap.bats" --> `tests/check-file-overlap.bats` が削除されている
- <!-- verify: file_not_contains "docs/structure.md" "check-file-overlap" --> `docs/structure.md` から `check-file-overlap.sh` のエントリ (誤った説明を含む) が削除されている
- <!-- verify: file_not_contains ".claude/settings.json.template" "check-file-overlap" --> `.claude/settings.json.template` から `check-file-overlap.sh` の allow 行が削除されている
- <!-- verify: rubric "scripts/check-file-overlap.sh の削除後、skills/ modules/ agents/ scripts/ tests/ .claude/ docs/structure.md (docs/spec/ 配下の過去 Spec、docs/sessions/ 配下の過去セッション記録、docs/migration-notes.md の Issue #9 移植履歴、docs/ja/ 配下の翻訳出力を除く) のいずれにも check-file-overlap への参照が残っていない" --> 削除後に参照の取り残しがない
- <!-- verify: rubric "docs/structure.md の Directory Layout の scripts/ と tests/ のファイル数コメントが、check-file-overlap.sh と tests/check-file-overlap.bats の削除に合わせて、変更前の値からそれぞれ 1 ずつ減っている" --> `docs/structure.md` のファイル数コメントが削除に合わせて更新されている
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

なし

## Notes

### 方針と Issue 本文の事実確認

- 方針は削除で確定済み (Issue 本文の「Auto-Resolved Ambiguity Points」)。根拠は、(1) 呼び出し元が 0 件、(2) スクリプトが依存する Spec 見出しが現行形式と合わず活用には書き直しが必要、(3) 同型の #1493 が削除で解決した先例がある、の 3 点。AC も削除方針でのみ決定的に判定できる
- Issue 本文の Background の主張を実測で確認した (測定範囲は worktree 直下、基準コミット `724c07aa`)
  - 説明の食い違い: `docs/structure.md` は `detect file overlap between repos`、スクリプト先頭は `Detect overlapping changed files across sub-issues` で、本文のとおり
  - 呼び出し元 0 件: `git grep -c "check-file-overlap" -- skills modules agents` の出力は空で、`premise: grep_count ... -eq 0` と一致する
  - 呼び出し履歴なし: `git log --oneline -S "check-file-overlap" -- skills modules agents` の出力は空
  - 見出しの不一致: `grep -rl "^## 変更対象ファイル" docs/spec` は 11 件 (最新は #31)、`grep -rl "^## Changed Files" docs/spec` は 749 件。`skills/` `modules/` `agents/` `scripts/` で `変更対象ファイル` 見出しを前提とする記述は、このスクリプト自身 (69 行目の `awk`) だけ
  - 依存先は孤立しない: スクリプトが呼ぶ `get-sub-issue-graph.sh` は `skills/auto/SKILL.md` から呼ばれており、本削除の影響を受けない
- Issue 本文との不整合: なし。本文は「参照は `.claude/settings.json.template` の allow 行と `tests/check-file-overlap.bats` だけ」と書くが、実測ではほかに `docs/structure.md` (本文で別途言及)、`docs/ja/structure.md`、移植履歴、過去 Spec とセッション記録がある。方針と AC には影響しない

### 参照点 (pre-change detection list)

不在確認の AC が「何も検出しなかっただけ」で通らないよう、変更前の検出結果を参照点として記録する (`modules/verify-patterns.md` § 26)。測定: worktree 直下で `git grep -c "check-file-overlap"` (追跡ファイル全体)。変更前は 21 ファイル。

- 削除で消える想定 (5 ファイル): `scripts/check-file-overlap.sh` (4 件)、`tests/check-file-overlap.bats` (4 件)、`.claude/settings.json.template` (1 件)、`docs/structure.md` (1 件)、`docs/ja/structure.md` (1 件)
- 残ってよい箇所 (Exclusions。履歴記録のため AC の対象外):
  - `docs/migration-notes.md` の `#### check-file-overlap.sh` 節 (Issue #9 移植履歴) と、その翻訳出力 `docs/ja/migration-notes.md`
  - `docs/sessions/34907-1783589732-2026-07-09/session.md` (過去セッション記録、2 件)
  - `docs/spec/` 配下の過去 Spec 13 ファイル (`issue-14-add-check-file-overlap-bats.md`、`issue-9-migrate-tooling-scripts-add-ci.md` など) と、この Spec 自身
- 対照群 (削除後も残るべきもの): `docs/structure.md` の他の Tooling エントリ (例: `scripts/check-allowed-tools.sh`、`scripts/check-verify-dirty.sh`)、`scripts/get-sub-issue-graph.sh`、`.claude/settings.json.template` の他 27 件の allow エントリ (変更前は 28 件)

### ファイル数コメント

- 変更前の値と測定方法 (記録時点): `scripts/` は 98、`tests/` は 134。実数と一致している
  - `find scripts -maxdepth 1 -type f | wc -l` = 98 (サブディレクトリ `scripts/git-hooks/` は数えない)
  - `find tests -maxdepth 1 -type f | wc -l` = 134 で、`ls tests/*.bats | wc -l` も 134 (サブディレクトリ `tests/fixtures/` は数えない)
- 削除後の期待値は 97 と 133。並行 PR が先にこの行を更新していた場合は、`/code` 時点の main のコメント値から 1 を引いた値にし、上記の `find` による実数とも一致させる
- 検証コマンドにリテラルの数値は固定しない。AC 6 は Issue 本文どおり「変更前の値から 1 ずつ減る」という相対表現の rubric で、`docs/structure.md` の注記と `modules/verify-patterns.md` § 31 (Concurrent PR Resilience) に沿っている
- 先例 #1493 は、`scripts/` コメントが変更前に実数より 1 大きかったため `tests/` だけを更新した。今回は両方とも変更前に実数と一致しているので、2 つとも 1 ずつ減らす

### AC 7 の扱い (bats)

- ローカルに bats が無い (この `/spec` 実行環境でも PATH 上に見つからなかった)。patch route の既存ルール (`skills/code/SKILL.md` Step 10 の bats 未導入時の扱い、`docs/workflow.md`) に従い、`/code` は `bats tests/` をローカルで実行できない場合にチェックを付けず、push 後に CI (`.github/workflows/test.yml` の bats ジョブ) の結果で確認する
- 削除する `tests/check-file-overlap.bats` は、このスクリプト専用で他のテストから参照されていない。テストの件数やスクリプトの数を前提とするテストも無い (`git grep -n -E "ls scripts|scripts/\*\.sh|find scripts|ls tests|tests/\*\.bats|find tests" -- tests` の該当は `chmod +x scripts/*.sh` のモック準備のみ)

### 翻訳ミラー

- `docs/ja/structure.md` は `/doc translate` 由来の生成物として Issue の AC の対象外 (#1493 と同じ扱い)。ただし `docs/translation-workflow.md` が top-level `docs/*.md` の変更時に同期を求めており、`scripts/check-translation-sync.sh` は git のコミット時刻で英語版と日本語版を比べて `OUTDATED` を判定する。そのため `docs/structure.md` と同一コミットで更新する (#1493 のコミット `a449895d` も同じ構成)

### `.claude/` 配下の扱い

- `.gitignore` は `.claude/*` を無視しつつ `!.claude/settings.json.template` で除外解除している。テンプレートは追跡済みなので通常の `git add` でも staging できるが、手順は `-f` 付きで統一する
- ローカル生成物 `.claude/settings.json` (gitignored、`./install.sh` が生成) は、このリポジトリの作業ツリーに存在せず影響しない。ほかの開発者のローカルに旧 allow 行が残っても無害で、必要なら `./install.sh` で再生成する

### 判定記録

- ルート: Size S、`always-pr` 未設定のため patch route。Axis 1 は変更ファイル 5 件で M、Axis 2 は #1493 の横展開 (copy & adapt) で 1 段下げて S。CI 依存の最低 M への引き上げ条件 (CI workflow、並列化・fixture 共有構造、CI 環境依存の検証) には該当しない
- audit/investigation-type: no。単一スクリプトの削除であり、複数項目を分類して判定根拠を永続成果物に残す作業ではない
- fail-safe critical: 対象外。削除のみで、検証や gate の新規ロジックを実装しない
- 新規 branch ロジックの追加なし。新規テストケースの要件は対象外
- 文字列照合系の verify command の存在確認: `check-file-overlap` は変更前に `docs/structure.md` (1 件) と `.claude/settings.json.template` (1 件) に存在し、`file_not_contains` は削除の確認として成立する。削除対象の 2 ファイルも現在存在する
- Simplicity: Pre-merge の検証項目は Issue 本文の AC (7 件) と 1:1 で同期するため light の上限 (5 件) を超えるが、Issue 本文との件数一致を優先する。Implementation Steps は 5 件に収めた

## Consumed Comments
No new comments since last phase.
