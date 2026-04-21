# Issue #290: auto: --batch に任意の Issue 番号リストを指定できるモードを追加

## Overview

`/auto --batch` を拡張し、ユーザが任意の Issue 番号リストを空白区切りで渡して順序付き連続実行できる "List mode" を追加する。既存の `/auto --batch N`（最新 N 件の XS/S を `createdAt` 降順で選択）は "Count mode" として後方互換で維持する。

入力形式（What として確定済み）:

- Count mode: `/auto --batch 5` — 従来どおり
- List mode: `/auto --batch 123 124 125 126` — 空白区切りで Issue 番号を並べる

判別ルール: `--batch` 直後に続く数値トークンを空白区切りで収集し、1 個なら Count mode、2 個以上なら List mode。非数値トークン（`--patch` 等）または ARGUMENTS 終端で収集を停止する。

List mode の挙動:

- ユーザ指定順で順次処理（並び替えなし）
- 許容 Size: XS/S/M/L（明示指定のため現行 Count mode の XS/S 制限を緩和）
- XL のみ警告を出して skip（サブ Issue 依存グラフによる並列実行経路と batch の直列処理が噛み合わないため）
- 個別 Issue 失敗時の継続挙動は Count mode と同じ（skip して次へ、batch 全体は abort しない）
- 未 triage の Issue は現行どおり per-issue で `run-issue.sh` が auto-triage する

## Changed Files

- `skills/auto/SKILL.md`: frontmatter `description` に List mode 構文（`` `--batch N1 N2 ...` ``）を追記 / Step 1 "Extract Issue Number" のパースロジックを Count/List 両対応に拡張 / `## Batch Mode (--batch N)` セクションを `## Batch Mode (--batch)` にリネームし Count mode / List mode の 2 サブセクション構成に再編

## Implementation Steps

1. frontmatter `description` 末尾の `` `--batch N` processes N backlog XS/S Issues. `` を `` `--batch N` processes N backlog XS/S Issues; `--batch N1 N2 ...` processes the explicitly listed Issues in order. `` に置換（→ 受け入れ条件 F）

2. Step 1 "Extract Issue Number" の `--batch` パース記述を更新。`--batch` 直後の連続する数値トークンを収集し、1 個なら `BATCH_SIZE=N` として Count mode、2 個以上なら `BATCH_LIST=[N1, N2, ...]` として List mode へ分岐する旨を記述。収集停止条件（非数値トークンまたは ARGUMENTS 終端）も明記（→ 受け入れ条件 A, B の基盤）

3. `## Batch Mode (--batch N)` セクションを `## Batch Mode (--batch)` にリネームし、以下の 2 サブセクション構成に再編（→ 受け入れ条件 A, B, C, D, E）:
   - `### Count mode (--batch N)`: 既存の Fetch Batch Candidates / Filtering criteria / Process Each Issue をそのまま収録。冒頭に「既存 `--batch N` の挙動は変更せず後方互換で維持する」旨を明記（→ C）
   - `### List mode (--batch N1 N2 ...)`: 任意の Issue 番号を空白区切りで指定する旨（→ A, B）/ ユーザ指定順で順次処理する旨（→ D）/ XS/S/M/L は受け入れ、XL の場合は警告を出して当該 Issue を skip し残りは継続する旨（→ E）/ 候補取得と `createdAt` ソートは List mode では行わない旨 / 個別 Issue の処理フロー（ラベル確認 → 未 triage なら `run-issue.sh` → Size 再確認で XL なら skip → `run-auto-sub.sh`）は Count mode と同じ旨

4. 自己整合チェック: `## Batch Mode (--batch)` セクション配下に「任意」「空白」「後方互換」「順」「XL」のキーワードがすべて出現することを Grep で確認。足りないキーワードがあれば Step 3 の文面を微修正して追加

## Verification

### Pre-merge
- <!-- verify: section_contains "skills/auto/SKILL.md" "Batch Mode" "任意" --> `skills/auto/SKILL.md` の Batch Mode セクションに、任意の Issue 番号リストを指定して連続実行できるモードの構文と挙動が記述されている
- <!-- verify: section_contains "skills/auto/SKILL.md" "Batch Mode" "空白" --> 任意指定の構文として空白区切り（例: `/auto --batch 123 124 125`）が採用された旨が Batch Mode セクションに記述されている
- <!-- verify: section_contains "skills/auto/SKILL.md" "Batch Mode" "後方互換" --> 既存の `--batch N`（最新 N 件の XS/S）の挙動は変更せず後方互換で維持される旨が明記されている
- <!-- verify: section_contains "skills/auto/SKILL.md" "Batch Mode" "順" --> 明示指定された Issue は、ユーザが渡した順序で順次処理される旨が記述されている
- <!-- verify: section_contains "skills/auto/SKILL.md" "Batch Mode" "XL" --> 明示指定に Size XL の Issue が含まれた場合、警告を出して当該 Issue を skip し、残りの Issue は継続処理する旨が記述されている
- <!-- verify: file_contains "skills/auto/SKILL.md" "--batch N1 N2" --> SKILL.md frontmatter の `description` に新モード（`--batch N1 N2 ...` 形式）の存在が反映されている

### Post-merge
- Claude Code 上で `/auto --batch 123 124 125 126` 形式（空白区切り）を実行し、指定された全 Issue が指定順序で処理されることをユーザが確認する
- Claude Code 上で既存の `/auto --batch N`（最新 N 件の XS/S）形式が後方互換で動作することをユーザが確認する

## Spec Retrospective

N/A

## Code Retrospective

### Deviations from Design

- なし。実装ステップは Spec 通りに進行した。

### Design Gaps/Ambiguities

- `## Batch Mode (--batch N)` セクションのリネーム後（→ `## Batch Mode (--batch)`）、Count mode / List mode の 2 サブセクション構成に再編する際、Spec に記載のサブセクションヘッダーが `###` (h3) か `####` (h4) か明示されていなかったが、既存の Batch Mode サブセクションが `### Fetch Batch Candidates` 等の h3 だったため、Count mode の内部見出しを `####` (h4) に降格し整合させた。
- ドキュメント同期 (docs/tech.md, docs/workflow.md, docs/ja/) の更新が Spec の「Changed Files」に含まれていなかったが、doc-checker の impact criteria に基づき更新対象と判断し追記した。

### Rework

- なし。

## Notes

### Post-merge 手動確認について

Post-merge は `verify-type: manual` で、ユーザが Claude Code から手動で `/auto --batch ...` を実行して確認する前提。本 Spec 実装は SKILL.md のドキュメント化（プロンプト更新）であり、自動 bats テストは対象外（`/auto` の引数パースは SKILL.md 内の LLM プロンプトとして解釈されるため、シェルスクリプトのように bats で直接テストできない）。

### frontmatter description の verify hint 強化

Issue 本文の元の verify hint は `file_contains "--batch"` だったが、既存テキストに既にマッチするため実質 no-op。Spec 側で `file_contains "--batch N1 N2"` に強化した（SSoT は Spec 側 — `/spec` 完了後に Issue 本文も同期される）。

### 判別ルールの根拠

「`--batch` 直後の数値トークンが 1 個 = Count mode / 2 個以上 = List mode」という判別は、ユーザが Issue #290 の UX Requirements で「他フラグとの併用は稀」「Issue 番号をそのまま並べて渡せる」入力を希望したことに基づく。単一 Issue を batch 経由で実行したいケースは `/auto N` で十分であり、`--batch 123` のような単一番号指定は Count mode として扱っても実用上問題ない（N=123 件の XS/S backlog が存在するケースはまれ）。

### auto モード自動解決との整合

Issue #290 の Auto-Resolve Log で記録した 4 つの判断（フラグ設計 / Size 制限 / 処理順序 / 区切り文字）は本 Spec でもそのまま採用。区切り文字のみユーザ確認で空白区切りに確定済み。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は明確で実装に十分な情報を含んでいた。N/A の Spec Retrospective が示す通り、設計上の問題なし。
- 唯一の軽微な不足点：`## Batch Mode` サブセクションの見出しレベル（`###` か `####` か）が Spec に明示されていなかった。実装者が既存の文書構造から `####` (h4) を選択し解決したが、Spec に「Count mode の内部見出しは h4」と明記していればより迷いなく実装できた。

#### design
- 本 Issue はドキュメント変更のみ（LLM プロンプト更新）のため、設計と実装の乖離リスクは低い。設計フェーズとして特筆すべき問題なし。

#### code
- 実装は Spec 通りに進行し、リワークなし。
- ドキュメント同期（docs/tech.md, docs/workflow.md, docs/ja/）が「Changed Files」に記載されていなかったが、実装者が doc-checker の判定基準に基づき追加更新した。Spec のスコープ記述を改善すれば防げる軽微なギャップ。

#### review
- パッチルート（Size S）のため PR レビューなし。直接コミット。Issue の受け入れ条件が verify コマンドで具体化されていたため、レビューなしでも品質担保できている。

#### merge
- パッチルート直コミット。コンフリクトなし、マージプロセス上の問題なし。

#### verify
- 全 6 件の Pre-merge 条件が PASS。verify コマンド（`section_contains` / `file_contains`）は実装文字列に適切にターゲットされていた。
- Post-merge 条件 2 件は `verify-type: manual` で、ユーザが Claude Code 上で手動実行して確認する設計。自動検証の限界（LLM プロンプトの実行動作は bats テスト等で直接検証できない）を正しく認識した設計。

### Improvement Proposals
- Spec に Batch Mode のサブセクション見出しレベル（h3/h4）を明記することで、実装者の迷いを削減できる。ただし本 Issue は一般的な提案として「Spec のサブセクション見出しレベルを明記する慣習を設けるべき」という改善提案として記録する。
