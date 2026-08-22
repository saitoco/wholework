# Issue #1434: verify-patterns: リテラル数値ピン留め型 AC の並行 PR 耐性を確保

## Consumed Comments

No new comments since last phase.

## Overview

`docs/structure.md` の `(N files)` 件数コメントのような、リテラル数値ピン留め型の verify command (例: `file_contains "docs/structure.md" "(94 files)"`) は、同じ件数を独立に +1 する並行 PR 間で git が非競合マージを行い、一方の加算を静かに失うリスクを構造的に持つ (#1047 で実測、#1119 でも同種事例)。

本 Issue では、Proposal のうち **アプローチ 3 (`modules/verify-patterns.md` へのガイダンス追加)** を採用し、リテラル数値ピン留めを post-merge の動的比較 (`command` verify command で実測値と記載値を突き合わせる) へ置き換える設計パターンを新セクションとして追加する。あわせて `docs/structure.md` / `docs/ja/structure.md` の「メンテナンスルール」記述 (旧来のリテラル pin 例示を含む) を新ガイダンスと整合する形に更新し、AC2 (両ファイルの記述が矛盾しないこと) を満たす。

アプローチ 2 (件数コメント自体の廃止・CI 自動生成化) は、新規 CI ジョブの追加を要し Size S に対して過大なため不採用。アプローチ 1 (動的整合性ガードへの置き換え) は、アプローチ 3 のガイダンス内で推奨パターンとして統合する形で採用する (両アプローチは独立ではなく補完関係にある)。

## Changed Files

- `modules/verify-patterns.md`: 新セクション `### 31. Literal Numeric Pinning ACs — Concurrent PR Resilience` を追加 — リテラル数値ピン留め型 AC の並行 PR 非耐性のリスク説明、#1047 の実例、post-merge 動的比較パターンの推奨、判断手順を記載 (Markdown ファイルのため bash 3.2+ 非該当)
- `docs/structure.md`: 「Maintenance rule」callout (Key Files セクション、L88 付近) のテキストを変更 — 旧来のリテラル pin 例示 (`<!-- verify: grep "(29 files)" "docs/structure.md" -->`) を、`modules/verify-patterns.md` §31 への参照と動的比較の推奨に置き換え
- `docs/ja/structure.md`: 上記と同内容の「メンテナンスルール」callout (L81 付近) を日本語で同期 (`docs/translation-workflow.md` の Sync Procedure に従う)

## Implementation Steps

1. `modules/verify-patterns.md` の末尾セクション (§30, L1107 付近) の直後、`## Output` (L1109) の直前に、新セクション `### 31. Literal Numeric Pinning ACs — Concurrent PR Resilience` を追加する (→ acceptance criteria A)
   - 内容: 並行 PR が同じ行を同じ値へ独立に変更した場合、git の非競合マージが一方の加算を失う仕組みの説明
   - 実例: #1047 (docs/structure.md のスクリプト件数コメントが `92→93` のまま止まり、真値 `94` を失いかけた事例。#1119 で同種事例が先行し未対処だった旨も記載)
   - 推奨パターン: 事前に正しい値をハードコードせず、実測値と記載値を比較する post-merge (`verify-type: auto`、verify command 付与時のデフォルト — 既存 §10 参照) の `command` verify command に置き換える。例:
     ```
     <!-- verify: command "test \"$(find scripts -maxdepth 1 -type f | wc -l)\" -eq \"$(grep 'Utility scripts used by skills and agents' docs/structure.md | grep -oE '[0-9]+')\"" -->
     ```
     抽出には `-P` (PCRE、BSD grep 非対応) を使わず `-E`/`-o` のみを使うこと (macOS ローカル環境と CI 双方でのポータビリティのため)。この pattern は spec 作成時の investigation で実行確認済み (`find scripts -maxdepth 1 -type f | wc -l` = 94、`grep 'Utility scripts used by skills and agents' docs/structure.md | grep -oE '[0-9]+'` = 94、両者一致)
   - pre-merge で解決できない理由の明記: 並行 PR がまだマージされていない時点では `/review` (safe mode) が競合を観測できない。`command` type は safe mode で常に UNCERTAIN になる (既存 § "Out-of-Tree File References" の verify mode に関する注記を参照) ため、post-merge (`/verify`, full mode) が唯一実行可能なフェーズであることを明記する
   - 判断手順 (4 ステップ): (1) リテラル数値ピン留めの検出 → (2) 並行 PR による競合可能性の判定 (共有・頻繁に触られるカウンタか) → (3) 該当する場合は post-merge 動的比較へ置換 → (4) 競合可能性がない専有カウンタは pre-merge pin のままで良い、という決定木を記載
   - 適用範囲の明記: `docs/structure.md` の `(N files)` に限らず、共有ドキュメント上のファイル数/行数/エントリ数を数え上げるあらゆるリテラル数値ピン留め AC に一般化されることを記載する

2. `docs/structure.md` の Key Files セクション「Maintenance rule」callout (L88 付近) の第 2 段落を更新する (→ acceptance criteria A, B)
   - 変更前 (該当段落全文): `When adding or removing a file in `modules/` or `scripts/`, also update the file count comment (e.g., `(29 files)`) in the Directory Layout section above, and include a verify command in the PR's acceptance criteria to confirm the count (e.g., `<!-- verify: grep "(29 files)" "docs/structure.md" -->`).`
   - 変更後: 件数コメント自体を更新する指示文はそのまま残し、verify command の例示部分 (`and include a verify command ... <!-- verify: grep "(29 files)" "docs/structure.md" -->` 相当) を、「リテラルピン留めを避け post-merge の動的比較を使うこと。パターンと根拠は `modules/verify-patterns.md` § "Literal Numeric Pinning ACs — Concurrent PR Resilience" を参照」という趣旨の一文に置き換える (具体的な verify command 例は Step 1 の §31 側に一本化し、2 ファイルでの二重管理を避ける)

3. `docs/ja/structure.md` の対応箇所 (L81 付近、「メンテナンスルール」callout 第 2 段落) を Step 2 の変更内容に合わせて日本語で同期する (→ acceptance criteria B)
   - `docs/translation-workflow.md` の Sync Procedure に従い、英語原文の構造・見出し・フォーマットを保った日本語訳とする (コードフェンス数に変化なし)
   - CLAUDE.md の約物ルール (日本語文中の括弧は半角 `()` + 前後半角スペース) を適用する

## Verification

### Pre-merge

- <!-- verify: rubric "リテラル数値ピン留め型 AC (docs/structure.md の (N files) 等) の並行 PR 耐性を確保する変更が modules/verify-patterns.md のガイダンス追加、動的整合性ガードへの置き換え、または対象ファイルのフォーマット見直しのいずれかの形で行われている" -->
  <!-- verify: file_contains "modules/verify-patterns.md" "Literal Numeric Pinning ACs" -->
- <!-- verify: rubric "docs/structure.md と docs/ja/structure.md の記述が採用したアプローチと整合しており、旧来のリテラル数値ピン留め形式のまま放置された矛盾がない" -->
  <!-- verify: file_contains "docs/structure.md" "Literal Numeric Pinning ACs" -->
  <!-- verify: file_contains "docs/ja/structure.md" "Literal Numeric Pinning ACs" -->

### Post-merge

なし (Issue body の `### Post-merge` に条件記載なし)

## Notes

- **Steering Docs sync candidate check**: キーワード `verify-patterns.md` は `docs/`, `tests/`, `scripts/`, `modules/` 配下で 148 ファイルにヒットし、discriminating power フィルタ (閾値 8) を超過するためスキップした。
- **不採用としたアプローチ**: Proposal アプローチ 2 (`docs/structure.md` の件数コメント自体を廃止し CI 自動生成に置き換える) は、新規 CI ジョブの追加を要し Size S の変更粒度に対して過大なため不採用とした。採用したアプローチ 3 (ガイダンス追加) は、アプローチ 1 (動的整合性ガード) を推奨パターンとして内包する形で統合している。
- **既存の件数ドリフトについて (スコープ外)**: 調査時点で `docs/structure.md` の `tests/` 件数コメントは `128 files` と記載されているが実測は `130` だった (`scripts/` 94 files / `modules/` 46 files / `agents/` 8 files は実測と一致)。この既存ドリフトの是正は本 Issue のスコープ外 (本 Issue は AC 設計パターンの是正が目的であり、個別ドキュメントの数値是正は対象外) とし、変更しない。

## Code Retrospective

### Deviations from Design
- Spec Step 1 は post-merge 動的比較が唯一実行可能な理由の裏付けとして「既存 §7 ガイダンス」を参照していたが、実装時点で確認したところ該当するガイダンス (`command` verify command は `/review` safe mode で UNCERTAIN になる旨) は §7 ではなく § "Out-of-Tree File References" 内の "Note on verify mode" だった。新セクション本文では番号ではなく見出し文字列で参照する形に修正した — セクション番号は今後の追記で変動しうるため、番号参照より見出し参照の方が陳腐化しにくいと判断した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Proposal のアプローチ 3 (`modules/verify-patterns.md` へのガイダンス追加) を採用し、アプローチ 1 (動的整合性ガード) を推奨パターンとして §31 本文に統合した。アプローチ 2 (件数コメント自体の廃止・CI 自動生成化) は新規 CI ジョブを要し Size S に対して過大なため不採用。
- §31 本文および `docs/structure.md`/`docs/ja/structure.md` からの相互参照は、セクション番号ではなく見出し文字列 (`§ "Literal Numeric Pinning ACs — Concurrent PR Resilience"`) で行った。番号参照は将来のセクション追加で陳腐化するため。
- `docs/structure.md` の `tests/` 件数コメントに既存ドリフト (記載 128 files / 実測 130 files) を発見したが、本 Issue のスコープ (AC 設計パターンの是正) 外として意図的に変更しなかった。

### Deferred Items
- None — 上記の既存件数ドリフトはスコープ外として明示的に見送ったものであり、フォローアップ Issue化は不要と判断した (本 Issue はパターン是正が目的であり、個別ドキュメントの数値是正はスコープ外と Issue 本文にも明記されている)。

### Notes for Next Phase
- Issue の Post-merge AC は「なし」。`/verify` で新規に確認すべき post-merge 条件はない。
- Pre-merge の 2 rubric 条件はいずれもこの code phase 内で PASS と判定し、Issue body のチェックボックスを `[x]` に更新済み。
- Spec の Verification セクションには rubric に加えて `file_contains` 3 件も記載されているが、Issue body の AC 自体は rubric 2 件のみで構成されている (file_contains は Spec 側の補助的な検証手段)。矛盾ではなく、Spec が Issue より詳細な検証手段を併記している状態。
