# Issue #84: terminology: verify command への用語統一と残存 verify hint の置換

## Overview

L2 の `<!-- verify: ... -->` 構造を指す用語が 2 つのステアリングドキュメント間で不整合である問題を解消する。

- **Terms SSOT** (`docs/product.md:159`): 「Acceptance check」（旧称: verification hint）
- **Forbidden Expressions** (`docs/tech.md:70`): 「Verify hint → verify command」（末尾の閉じ引用符が欠落した typo あり）

Terms SSOT の「Acceptance check」は L1 `acceptance criteria`（受入条件）との語感衝突が強いため、本 Issue では **「verify command」** を採用し、Terms SSOT を正本化する。あわせて、Python 定数 `KNOWN_VERIFY_COMMANDS` を `KNOWN_VERIFY_COMMAND_TYPES` にリネームし、L2（verify command 全体）と L3（command type = 第一トークン）の階層を命名に反映する。

**スコープ**: 「verify hint」/「verify hints」の文字列除去に限定。「Acceptance check」の広範置換（24 ファイル・83 occurrences）は後続 Issue で扱う（Scope Declaration 参照）。

## Changed Files

**測定範囲**: `docs/spec/**` を除くアクティブファイル。測定コマンド: `Grep pattern="verify hint|verify hints|validate_verify_hints|verify_hint_errors" exclude=docs/spec/**` および `Grep pattern="KNOWN_VERIFY_COMMANDS" exclude=docs/spec/**`

**Phase A — 用語 SSOT の整理** (4 files):

- `docs/product.md`: Terms 表 (line 159) の「Acceptance check」エントリを「verify command」に置換。旧称記載は「verification hint / Acceptance check」として残す（移行履歴保存）
- `docs/ja/product.md`: Terms 表 (line 155) の「受入チェック」エントリを同様に更新
- `docs/tech.md`: Forbidden Expressions 行 (line 70) の閉じ引用符欠落 typo 修正（`"verify command)` → `"verify command")`）
- `docs/ja/tech.md`: Forbidden Expressions 行 (line 62) を同様に修正

**Phase B — コード・ドキュメント一括置換** (7 files, "verify hint" 文字列除去):

- `scripts/validate-skill-syntax.py`: コメント (line 272)、変数名 (lines 273, 274)、docstring (lines 512, 563-564)、関数定義 (line 561)、エラーメッセージ (line 592) を "verify command" 系に置換
- `tests/validate-skill-syntax.bats`: セクションコメント (line 480)、テスト名 (lines 482, 522, 541, 560, 578) を "verify command" 系に置換
- `modules/browser-verify-security.md`: line 44 のテーブルセル内 "verify hints" → "verify commands"
- `modules/verify-classifier.md`: lines 38, 40, 41 の「a `<!-- verify: ... -->` hint」「without a hint」等の表記を "verify command" に置換
- `skills/verify/SKILL.md`: lines 416, 419 の「verify hints」見出し・本文を "verify commands" に置換
- `skills/spec/SKILL.md`: line 296 の見出し「Section rename — update verify hints simultaneously」を "verify commands" に置換
- `skills/issue/SKILL.md`: line 194 の「verify hint assignment」を "verify command assignment" に置換

**Phase C — Python 関数・定数リネーム** (2 files):

- `scripts/validate-skill-syntax.py` (Phase B と同ファイル、追加変更):
  - 関数 `validate_verify_hints` → `validate_verify_commands` (line 561 定義 + lines 273-274 呼び出し)
  - ローカル変数 `verify_hint_errors` → `verify_command_errors` (lines 273, 274)
  - 定数 `KNOWN_VERIFY_COMMANDS` → `KNOWN_VERIFY_COMMAND_TYPES` (line 486 定義 + lines 599, 602, 606 参照)
- `modules/verify-patterns.md`: 命名規約テーブルの例示 (line 100: `validate_verify_hints`, line 101: `KNOWN_VERIFY_COMMANDS`) を新名称に追随

**Issue 本文修正** (Self-review 結果):

- `docs/spec/issue-84-*.md` の Verification section と Issue #84 本文の `## Acceptance Criteria > Pre-merge` で、`modules/verify-classifier.md` 向けの誤った pattern (`file_not_contains "..." "--> hint"`) を正しい pattern に修正する（次セクション参照）

## Implementation Steps

**Step 記録ルール**:
- Step 番号は整数のみ (1, 2, 3, ...)
- 依存関係は「(after N)」「(parallel with N, M)」で明示
- 受入条件へのマッピングは「(→ acceptance criteria X)」で明示

1. **Phase A-1: Terms SSOT 正本化** — `docs/product.md:159` および `docs/ja/product.md:155` の Terms 表で、「Acceptance check」/「受入チェック」エントリを「verify command」に置換。定義文に旧称として "verification hint / Acceptance check" を記載（移行履歴保存）。日本語側も同等の書式で更新。(→ Pre-merge 1-3)

2. **Phase A-2: Forbidden Expressions typo 修正** — `docs/tech.md:70` および `docs/ja/tech.md:62` の `Verify hint` 行で、閉じ引用符欠落 typo (`changed to "verify command)`) を正しく (`changed to "verify command")`) に修正。(parallel with 1) (→ Pre-merge 4-5)

3. **Phase B-1: Python script / bats test の "verify hint" 表記置換** — `scripts/validate-skill-syntax.py:272,273,274,512,561,563-564,592` のコメント・docstring・エラーメッセージを "verify command" 系に置換。`tests/validate-skill-syntax.bats:480,482,522,541,560,578` のセクションコメント・テスト名を同様に置換。※関数名・変数名・定数名の実リネームは Step 5 で実施。(after 2) (→ Pre-merge 6-7)

4. **Phase B-2: modules / skills ファイルの "verify hint/hints" 表記置換** — `modules/browser-verify-security.md:44`, `modules/verify-classifier.md:38,40,41`, `skills/verify/SKILL.md:416,419`, `skills/spec/SKILL.md:296`, `skills/issue/SKILL.md:194` の「verify hint/hints」系表記を "verify command/commands" に置換。`modules/verify-classifier.md` は backtick 介在の複雑パターンに注意（Notes 参照）。(parallel with 3) (→ Pre-merge 8-12)

5. **Phase C: Python 関数・定数リネーム** — `scripts/validate-skill-syntax.py` で以下をリネーム: 関数 `validate_verify_hints` → `validate_verify_commands`、ローカル変数 `verify_hint_errors` → `verify_command_errors`、定数 `KNOWN_VERIFY_COMMANDS` → `KNOWN_VERIFY_COMMAND_TYPES`。定義箇所と参照箇所（lines 273, 274, 486, 561, 599, 602, 606）を全て更新。(after 3) (→ Pre-merge 13-16)

6. **Phase C: verify-patterns.md 命名規約例示追随** — `modules/verify-patterns.md:100-101` の Python 関数名例・定数名例を新名称 `validate_verify_commands` / `KNOWN_VERIFY_COMMAND_TYPES` に追随更新。(after 5) (→ Pre-merge 17-18)

7. **Phase D: 自己検証テスト実行** — `python3 scripts/validate-skill-syntax.py skills/` で全 SKILL.md の構文 validation が PASS することを確認。続いて `bats tests/validate-skill-syntax.bats` で全テスト PASS を確認。関数・定数リネームの整合性、既存 verify command 検証ロジックの継続動作を担保。(after 6) (→ Pre-merge 19-20)

## Verification

### Pre-merge

**Phase A — 用語 SSOT の整理**

- <!-- verify: section_contains "docs/product.md" "## Terms" "verify command" --> `docs/product.md` Terms 表に "verify command" エントリが存在し、旧称として verification hint / Acceptance check が記載されている
- <!-- verify: section_contains "docs/ja/product.md" "## Terms" "verify command" --> `docs/ja/product.md` Terms 表が同様に更新されている
- <!-- verify: file_not_contains "docs/product.md" "| Acceptance check |" --> `docs/product.md` Terms 表の旧 "Acceptance check" 行（pipe-delimited）が削除されている
- <!-- verify: file_not_contains "docs/ja/product.md" "| 受入チェック |" --> `docs/ja/product.md` Terms 表の旧 "受入チェック" 行（pipe-delimited）が削除されている
- <!-- verify: file_contains "docs/tech.md" "changed to \"verify command\")" --> `docs/tech.md:70` Forbidden Expressions 行の閉じ引用符欠落 typo が修正されている
- <!-- verify: file_contains "docs/ja/tech.md" "changed to \"verify command\")" --> `docs/ja/tech.md:62` Forbidden Expressions 行が同様に修正されている

**Phase B — コード・ドキュメント一括置換（"verify hint" 除去）**

- <!-- verify: file_not_contains "scripts/validate-skill-syntax.py" "verify hint" --> `scripts/validate-skill-syntax.py` の "verify hint" 表記（コメント・docstring・エラーメッセージ）が除去されている
- <!-- verify: file_not_contains "tests/validate-skill-syntax.bats" "verify hint" --> `tests/validate-skill-syntax.bats` の "verify hint" 表記（セクションコメント・テスト名）が除去されている
- <!-- verify: file_not_contains "modules/browser-verify-security.md" "verify hints" --> `modules/browser-verify-security.md:44` の "verify hints" 表記が除去されている
- <!-- verify: file_not_contains "modules/verify-classifier.md" "without a hint" --> `modules/verify-classifier.md:40` の「without a hint」表記が除去されている（`<!-- verify: ... -->` を指す "hint" 系表記の置換を担保）
- <!-- verify: file_contains "modules/verify-classifier.md" "verify command" --> `modules/verify-classifier.md` に新用語 "verify command" が存在する
- <!-- verify: file_not_contains "skills/verify/SKILL.md" "verify hints" --> `skills/verify/SKILL.md:416,419` の "verify hints" 表記が除去されている
- <!-- verify: file_not_contains "skills/spec/SKILL.md" "verify hints" --> `skills/spec/SKILL.md:296` の "verify hints" 表記が除去されている
- <!-- verify: file_not_contains "skills/issue/SKILL.md" "verify hint assignment" --> `skills/issue/SKILL.md:194` の "verify hint assignment" 表記が除去されている

**Phase C — Python 関数・定数リネーム**

- <!-- verify: grep "def validate_verify_commands" "scripts/validate-skill-syntax.py" --> `scripts/validate-skill-syntax.py` に関数 `validate_verify_commands` が定義されている
- <!-- verify: file_not_contains "scripts/validate-skill-syntax.py" "validate_verify_hints" --> `scripts/validate-skill-syntax.py` に旧関数名 `validate_verify_hints` が残っていない
- <!-- verify: grep "KNOWN_VERIFY_COMMAND_TYPES" "scripts/validate-skill-syntax.py" --> `scripts/validate-skill-syntax.py` に定数 `KNOWN_VERIFY_COMMAND_TYPES` が定義されている
- <!-- verify: file_not_contains "scripts/validate-skill-syntax.py" "KNOWN_VERIFY_COMMANDS" --> `scripts/validate-skill-syntax.py` に旧定数名 `KNOWN_VERIFY_COMMANDS` が残っていない
- <!-- verify: grep "validate_verify_commands" "modules/verify-patterns.md" --> `modules/verify-patterns.md:100` の Python 関数名例が `validate_verify_commands` に更新されている
- <!-- verify: grep "KNOWN_VERIFY_COMMAND_TYPES" "modules/verify-patterns.md" --> `modules/verify-patterns.md:101` の定数名例が `KNOWN_VERIFY_COMMAND_TYPES` に更新されている

**Phase D — テスト整合性**

- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> `validate-skill-syntax.py` 単体実行で全 SKILL.md が PASS する
- <!-- verify: command "bats tests/validate-skill-syntax.bats" --> `validate-skill-syntax.bats` の全テストが PASS する

### Post-merge

- 後続 Issue で "Acceptance check" / "acceptance check" / "受入チェック" の広範な置換（残 24 ファイル・83 occurrences）が追跡されている <!-- verify-type: manual -->

## Tool Dependencies

### Bash Command Patterns

- `python3 scripts/validate-skill-syntax.py`: SKILL.md 構文 validation（既存 command hint で使用中、追加許可不要）
- `bats tests/validate-skill-syntax.bats`: bats テスト実行（既存 command hint で使用中、追加許可不要）

### Built-in Tools

- `Read`, `Edit`, `Grep`, `Glob`, `Bash`: 既存 allowed-tools（追加許可不要）

### MCP Tools

- none

## Notes

### Auto-Resolved Ambiguity Points（Issue 本文から転記）

- **新用語の選定**: "verify command" を採用
  - 却下案 1: "Acceptance check"（現 Terms SSOT）→ L1 `acceptance criteria` との語感衝突、日本語「受入条件」「受入チェック」の近さで混乱
  - 却下案 2: "verify hint"（旧 Forbidden Expressions 移行元）→ 役割（動作指示）が曖昧
  - 採用理由: 「command = 実行される指示」が明確、L3 `KNOWN_VERIFY_COMMAND_TYPES` と階層化可能、shell command / CLI command との類推で英語ネイティブにも自然
- **Python 新関数名**: `validate_verify_hints` → `validate_verify_commands`（直訳置換）
- **Python 新ローカル変数名**: `verify_hint_errors` → `verify_command_errors`（追随）
- **Python 新定数名**: `KNOWN_VERIFY_COMMANDS` → `KNOWN_VERIFY_COMMAND_TYPES`（L3 = "command type" を明示、L2 の "verify command" との階層を命名で区別）
- **docs/ja/ 追随更新**: 英語修正と対応する日本語ミラー（`docs/ja/product.md`, `docs/ja/tech.md`）も同じ Issue で更新（英日の用語ドリフトを発生させないため）
- **disposable spec files**: `docs/spec/issue-*.md` の過去 retrospective は使い捨てなので対象外（CLAUDE.md Language Conventions 準拠）

### Spec 作成時の自己レビューで発見した Issue 本文の誤り

Issue #84 本文の `## Acceptance Criteria > Pre-merge > Phase B` にある以下の受入条件:

```markdown
- [ ] <!-- verify: file_not_contains "modules/verify-classifier.md" "--> hint" --> ...
```

この pattern (`--> hint`) は `modules/verify-classifier.md:38` の実際のファイル内容と **mismatch** する。実際の line 38 は:

```markdown
When assigning `<!-- verify-type: auto -->` to a condition, a `<!-- verify: ... -->` hint **must be present**.
```

`-->` の直後には backtick (`` ` ``) が介在するため、fixed-string pattern `--> hint` は**永続的に false-positive**（更新なしでもパス）になる。

**修正方針**: Issue 本文の Phase B 該当条件を以下 2 項目に置き換える:

1. `file_not_contains "modules/verify-classifier.md" "without a hint"` — line 40 の「`auto` without a hint」表記の除去を担保
2. `file_contains "modules/verify-classifier.md" "verify command"` — 新用語の存在を positive 確認

Spec 作成完了時に Issue 本文を自動更新する（`/spec` 内の「Verification conditions vs. Issue body acceptance criteria consistency check」ルール準拠、Spec 側を source of truth とする）。

### `modules/verify-classifier.md` の置換パターン詳細

line 38-41 の原文と置換後（例）:

```markdown
### 原文
When assigning `<!-- verify-type: auto -->` to a condition, a `<!-- verify: ... -->` hint **must be present**.

- `verify-type: auto` is assigned only to conditions that have a hint (a `auto` without a hint is equivalent to skipping verification, which contradicts user expectations)
- If a hint cannot be provided, classify as `opportunistic` or `manual` instead

### 置換後（例）
When assigning `<!-- verify-type: auto -->` to a condition, a `<!-- verify: ... -->` verify command **must be present**.

- `verify-type: auto` is assigned only to conditions that have a verify command (a `auto` without a verify command is equivalent to skipping verification, which contradicts user expectations)
- If a verify command cannot be provided, classify as `opportunistic` or `manual` instead
```

置換の粒度は実装者判断に委ねるが、「hint」単独表現は全て "verify command" に置換し、セクション内に「hint」が残存しない状態を目標とする。

### Scope Declaration（Issue 本文から転記）

**[同一ファイル内の非推奨用語 `Acceptance check` の置換] 含まない**

- 本 Issue では Terms SSOT のみ先行修正し、各 skill / module / docs で使用されている "Acceptance check" / "acceptance check" / "受入チェック"（計 24 ファイル・83 occurrences）の広範な置換は後続 Issue で扱う
- Phase B は **"verify hint" / "verify hints" の文字列**に限定（"Acceptance check" や "command hint" 等のサブタイプ参照は対象外）
- 期間中は Terms SSOT と一般文書の間に過渡的な不整合が残存するが、これは段階的移行として許容（`docs/tech.md` Terminology Migration Scope Rule 準拠）

### 既存パターン・類似 Issue からの学び

- `docs/spec/issue-66-terms-unify-japanese.md`: 用語統一系 Issue の参考（手法・acceptance check 設計）
- `docs/spec/issue-36-migrate-tech-md.md`: tech.md 移行系 Issue の参考（Forbidden Expressions 更新パターン）
- Rename 系 Issue での grep check 重要性 → 本 Spec の測定範囲明示で対応済み

### Verification section と Issue body の count alignment

- Issue body pre-merge criteria (当初): 20 items（Phase A 5 + Phase B 7 + Phase C 6 + Phase D 2）
- Spec 修正後の pre-merge verification: **22 items**（Phase A 6 + Phase B 8 + Phase C 6 + Phase D 2）
- 差分: Phase A に ja/product.md の旧エントリ削除確認 +1、Phase B に verify-classifier 向けの 2 分割 (+1) = 計 +2 items
- 本 Spec 作成時に Issue body を Spec と一致するよう更新する（Spec 側を source of truth）

## issue retrospective

### 判断根拠の記録

**用語選定のロジック**:

本 Issue の出発点は「`verify hint`（Forbidden Expressions の旧用語）がコード/ドキュメントに残っている」という単純な残存調査だったが、事前調査中に 2 つのステアリングドキュメント間の用語不整合が判明したため、調査範囲を「Terms SSOT の正本化」まで拡張した。

- `docs/product.md:159` Terms (SSOT for terminology): 「Acceptance check」
- `docs/tech.md:70` Forbidden Expressions: 「Verify hint → verify command」（末尾の閉じ引用符欠落 typo あり）

ユーザーとの対話で以下を明確化:

1. **L1 `acceptance criteria`（受入条件）** と **L2 の `<!-- verify: ... -->` 構造** は別概念だが、Terms SSOT の「Acceptance check」は日本語「受入チェック」と相まって語感衝突が強い。`/verify` 実行時に「受入条件のチェックボックスに完了チェックを入れる」のような文脈で混乱しやすい。
2. 「command = 実行される指示」という英語ニュアンスが、L2 の役割（verify-executor が解釈・実行するディレクティブ）と一致する。
3. Python 定数 `KNOWN_VERIFY_COMMANDS`（現行）は shell 慣例的に「既知コマンド種別の集合」を意味するが、L2 全体を「verify command」と呼ぶ新用語の下では曖昧化するため、`KNOWN_VERIFY_COMMAND_TYPES` にリネームし L2/L3 の階層を命名で区別する。

採用案: **`verify command`**（L2）+ **`KNOWN_VERIFY_COMMAND_TYPES`**（L3 定数）。

### Q&A で決まった主要方針

- **Forbidden Expressions 行の扱い**: 新用語に修正して残す（誤用検出ガードとして機能継続、典型的な「migration row」パターン）
- **Python 関数・定数のリネーム**: スコープに含める。`KNOWN_VERIFY_COMMANDS → KNOWN_VERIFY_COMMAND_TYPES` も含む（影響 5 箇所、小規模）
- **docs/ja/ 追随更新**: 英日のドリフトを避けるため同 Issue で更新
- **Scope 宣言**: 「Acceptance check」の広範置換（24 ファイル・83 occurrences）は本 Issue スコープ外

### 関連 Issue

- #77 「verify: section_contains hint でOR代替パターンは分割する旨をガイドラインに追記」 は同じ旧用語 "section_contains hint" を title に含む別 Issue。本 Issue マージ後、#77 のタイトル・本文の用語を新用語に合わせる追従が望ましい

## spec retrospective

### Minor observations

- Issue #84 本文の `file_not_contains "modules/verify-classifier.md" "--> hint"` が実ファイル内容と pattern mismatch（backtick 介在）し、永続 false-positive となる問題を Spec フェーズの self-review で発見。Issue body を修正済み。pre-verification of target file format（`verify-patterns.md` セクション 3）の重要性が実証された
- `docs/product.md` Terms 表の旧エントリ削除確認に当初 `section_not_contains "Formerly called \"verification hint\""` を用いようとしたが、新エントリにも旧称を legacy mention として残す方針だと false-negative になるため、`file_not_contains "| Acceptance check |"` (pipe-delimited テーブル行) に変更。テーブル行削除検出の典型パターンとして再利用可能
- Forbidden Expressions typo 修正の verify command は当初 `grep "verify command\"\\)"` を使ったが、regex バックスラッシュと fixed-string の境界が曖昧だったため `file_contains "changed to \"verify command\")"` (fixed-string + エスケープ) に変更。ロジックが単純で確実

### Judgment rationale

- **verify-classifier.md 置換の scope 拡張**: 当初 Issue では「verify hint」文字列のみを対象としたが、同ファイル line 38-41 は「hint」単独表現で `<!-- verify: ... -->` を指すため、本 Issue のスコープ（L2 用語統一）に含めるべきと判断。Spec 作成時に実ファイルを読んで確認した上で Verification section に反映
- **テーブル行削除検出パターンの採用**: Terms 表の旧エントリ削除確認に pipe-delimited パターン (`| X |`) を採用。markdown テーブル行は他の本文と区別でき、fixed-string 検索で一意に特定できるため false-positive リスクが最小
- **Python ローカル変数 `verify_hint_errors` の追随リネーム**: Issue 本文の Phase C には含まれていなかったが、関数名・定数名リネームと同時に更新するのが自然なため、Spec 側で明示的に含めた。実装時の見落とし防止

### Uncertainty resolution

- **Issue body の誤 acceptance criterion**: Spec self-review 中に Issue 本文の実装不整合を発見 → Spec を source of truth として Issue body を自動更新（`/spec` Step 10 self-review rules 準拠）
- **Terms SSOT 正本と一般文書の過渡的不整合**: 「Acceptance check」系 83 occurrences の広範置換を同 Issue に含めるか後続 Issue に分離するか → 後続 Issue に分離（`docs/tech.md` Terminology Migration Scope Rule 準拠）。Scope Declaration で明示
- **ambiguity 検出 0 件**: 本 Issue の受入条件は Spec 段階で新たな ambiguity を発見せず。Issue フェーズで AskUserQuestion を通じて全決定を行い、Auto-Resolved として記録済みだったため

