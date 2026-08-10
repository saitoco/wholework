# Issue #1130: validate-skill-syntax: 二重バッククォートのインラインコード誤処理を解消

## Consumed Comments

No new comments since last phase.

## Overview

`scripts/validate-skill-syntax.py` の `INLINE_CODE_PATTERN` が単一バッククォート専用の正規表現になっており、Markdown 標準のダブルバッククォート形式のインラインコード (コード自体に単一バッククォートを含めたい場合の標準記法) を正しく認識できない。開始・終了デリミタの長さが一致しない位置でマッチしてしまうため、意図しない範囲 (無関係な `<!-- verify: ... -->` プレースホルダーを含む場合がある) が「インラインコード」として除去され、後続の各種チェックの対象から欠落したり誤判定されたりする。#1109 / PR #1121 の実例で実際に踏まれ、`/review` の retrospective に運用回避策 (SKILL.md 本文でダブルバッククォートを使わない) として記録された。

Issue 本文が示す優先案 (ストリッパーを二重バッククォート対応にする) を採用する。バッククォートの連続数 (フェンス長) をキャプチャし、同じ長さの閉じフェンスまでを 1 つのインラインコードとして扱う正規表現に置き換える。

## Reproduction Steps

1. 以下の内容で SKILL.md フィクスチャを作成する (二重バッククォートで囲まれた区間の中に単一バッククォートのペアが 1 組ネストしている):

   ```
   ---
   name: myskill
   description: A test skill
   ---

   # Test Skill

   Use double backticks when the code itself contains a backtick, e.g. ``the `foo` value``.

   - <!-- verify: file_exists "path/to/file" --> some acceptance condition

   Later, reference the raw `backtick` character again for emphasis.
   ```

2. `python3 scripts/validate-skill-syntax.py <path-to-skill-dir>` を実行する。
3. **現状の挙動 (実測済み)**: `INLINE_CODE_PATTERN.sub()` を上記本文に直接適用して確認したところ、二重バッククォートの開始位置がずれてマッチするため、`<!-- verify: file_exists "path/to/file" --> some acceptance condition` を含む行が丸ごと「インラインコード」としてストリップ後のテキストから消える。この結果、`validate_verify_commands` の走査対象からこの verify コマンドが silently 欠落する (エラーにはならないが、検証されるべきものが検証されない)。#1109 / PR #1121 の実例では、この種の巻き込みが verify プレースホルダーの内容を破壊する形で起こり、「未知の verify コマンド」エラーとして顕在化した。
4. **期待される挙動**: 二重バッククォートのペア全体が 1 つのインラインコードとして正しく認識され、それ以外の本文 (`<!-- verify: ... -->` プレースホルダーを含む) はストリップ対象に含まれない。

## Root Cause

`scripts/validate-skill-syntax.py:67` の `INLINE_CODE_PATTERN` は「バッククォート 1 個 + 非バッククォート 1 文字以上 + バッククォート 1 個」の形にしかマッチしない正規表現になっている。Markdown 標準のインラインコード記法では、コード自体にバッククォートを含めたい場合、開始・終了に同じ長さのバッククォート連続列 (フェンス長 N) を使い、間に現れる N 未満の長さのバッククォート列は通常のコンテンツとして扱う、というルールになっている。現在の実装はこの「フェンス長の一致」を検証していない。

二重バッククォートの 1 文字目は「直後が非バッククォートであること」という要件を満たせないため、2 文字目 (2 個目のバッククォート) から次に現れる単一バッククォートまでが 1 マッチとして扱われる。その結果:

- 開始側の 1 文字目のバッククォートはマッチに含まれず、ストリップ後のテキストにリテラルとして残存する
- マッチ後に再開したスキャンが、残る片割れのバッククォートを新たな開始点として認識し、``[^`]+`` (非バッククォート文字を貪欲に消費する文字クラス) が消費を続ける。途中に他のバッククォートが存在しない限り、文書の広い範囲 (段落・見出しをまたいで無関係な `<!-- verify: ... -->` プレースホルダーを含む場合がある) が 1 つのマッチとして飲み込まれる

`INLINE_CODE_PATTERN` は同ファイル内で 6 箇所 (`validate_shell_sensitive_chars` / `validate_decimal_steps` / `validate_phase_headings` / `validate_verify_commands` / `validate_command_hint_paths` / `validate_body_tools_in_allowed_tools`) から呼ばれており、いずれも同じ誤処理の影響を受ける。

**修正方針の妥当性**: バッククォートの連続列をキャプチャグループで捕捉し、同じ列が再度現れるまでを 1 つのインラインコードとして扱う後方参照パターンに置き換えることで解決できる (Issue 本文の優先案と一致)。実際に候補パターンへ置き換えて動作確認した結果、二重バッククォート内に単一バッククォートを含むケース・単一バッククォート単体のケースいずれも正しく認識され、意図しない範囲の巻き込みは解消された。`re.DOTALL` フラグは、既存の ``[^`]+`` (非バッククォート文字クラス) が改行を含め無条件にマッチしていた挙動と同等の適用範囲を保つために必要 (`.+?` は `re.DOTALL` なしでは改行にマッチしないため)。

## Changed Files

- `scripts/validate-skill-syntax.py`: `INLINE_CODE_PATTERN` (line 67) を、バッククォート連続列の長さが一致する閉じ位置までをマッチする後方参照パターン (`re.DOTALL` 付き) に変更する
- `tests/validate-skill-syntax.bats`: 二重バッククォートのインラインコード (内部に単一バッククォートを含む) と、その後方に位置する無関係な `<!-- verify: ... -->` プレースホルダーを含む SKILL.md フィクスチャで検証する新規 `success:` `@test` を追加する

## Implementation Steps

1. `scripts/validate-skill-syntax.py:67` の `INLINE_CODE_PATTERN` を、バッククォートの連続列 (1 個以上) をキャプチャし、同じ長さの列が再度現れる位置までを 1 つのインラインコードとして扱う後方参照パターンに置き換える。`re.DOTALL` を付与する (→ acceptance criteria 1)
2. `tests/validate-skill-syntax.bats` に、二重バッククォート形式のインラインコード (内部に単一バッククォートを含む) と、その後方に位置する `<!-- verify: file_exists "path/to/file" --> ...` プレースホルダーを含む SKILL.md フィクスチャを用意し、`python3 "$REAL_SCRIPT" ...` の実行結果が `0 error` であること、かつ出力に verify プレースホルダーが「未知の verify コマンド」として検出されないことをアサートする新規 `@test` を追加する。入力データ形式は既存テスト (378 行目 `success: exclamation mark inside code fence is allowed` 等) と同じ heredoc 形式の SKILL.md フィクスチャに合わせる (after 1) (→ acceptance criteria 2)
3. `python3 scripts/validate-skill-syntax.py skills/verify/SKILL.md skills/code/SKILL.md skills/issue/SKILL.md skills/spec/SKILL.md` を実行し、既存 SKILL.md が引き続き 0 error であることを確認する (after 1) (→ acceptance criteria 3)
4. `bats tests/*.bats` を実行し、既存テストがすべて PASS することを確認する (after 1, 2) (→ acceptance criteria 4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/validate-skill-syntax.py が二重バッククォート形式のインラインコードを含む本文に対して、無関係な箇所を誤検出しない実装になっている (二重バッククォート対応、または二重バッククォートを検出して原因が分かるエラーを出す形のいずれか)。検出+エラーメッセージ方式 (代替案) を採用した場合は、二重バッククォートのインラインコードが未対応である制約が docs/ の該当箇所または skills/*/SKILL.md の編集ガイドラインに明記されていることも合わせて満たしている" --> 二重バッククォートの誤処理が解消されている (代替案採用時は制約の明文化も含む)
- <!-- verify: rubric "二重バッククォートを含む入力に対する挙動 (正常処理されるか、原因の分かるエラーで失敗するか) を検証する新規テストケースが追加されている" --> 二重バッククォート入力の新規テストが追加されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/verify/SKILL.md skills/code/SKILL.md skills/issue/SKILL.md skills/spec/SKILL.md" --> 既存の SKILL.md が引き続き 0 error で通る
- <!-- verify: command "bats tests/*.bats" --> 既存の bats テストがすべて PASS する

### Post-merge

- 二重バッククォートのインラインコードを含む SKILL.md を編集し、validator が誤検出せずに通る (または原因の分かるエラーで失敗する) ことを確認する <!-- verify-type: manual -->

## Notes

- **優先案を採用**: Issue 本文の「代替案」(検出してエラーで早期失敗させる方式) ではなく「優先案」(ストリッパーを二重バッククォート対応にする) を採用した。理由: 候補パターンへの置き換えを実際に動作確認した結果、Markdown 標準記法をそのまま使えるようになり、代替案採用時に必須となる追加のドキュメント明文化も不要になるため、Issue 本文の目的 (「Markdown の標準記法が SKILL.md 本文で使えるようにする」) に最も直接的に合致する。
- **既知の限定事項 (スコープ内で許容)**: 後方参照パターンは「開始と同じ長さのバッククォート列を最初に見つけた時点で閉じる」ため、閉じデリミタの直前・直後にさらにバッククォートが連続する極端なケース (短いフェンスが長いフェンスの一部に前置されるようなネスト) では、完全な CommonMark 仕様と異なる挙動になりうる。本 Issue が対象とする「二重バッククォートで単一バッククォートをエスケープする」通常の用法 (Issue 本文の実例と一致) では正しく動作することを確認済み。SKILL.md 本文でこのような極端なネストが使われている実例は現時点で確認されていないため、スコープ外として許容する。
- **横展開候補 (本 Issue のスコープ外)**: `scripts/check-language-convention.py` の `INLINE_CODE_PATTERN` (line 41) にも同種の単一バッククォート限定の弱点がある。ただしこちらは diff の 1 行単位でストリップを適用するため、`validate-skill-syntax.py` のように複数パラグラフにまたがる広範囲の巻き込みは起こりにくい。Issue #1130 の Purpose は `validate-skill-syntax.py` に明示的にスコープされているため (Issue 本文 Background/Purpose 参照)、本 Spec の変更対象には含めない。将来 CJK 誤検出・見逃しの実例が観測された場合は別途検討する。
- **CommonMark 仕様の直接引用は不可**: `spec.commonmark.org` および `commonmark-spec` リポジトリの Code spans セクションを WebFetch で参照しようとしたが、文書が長大で該当セクションを取得できなかった。既知のバッククォート文字列マッチングルール (開始・終了デリミタの長さが一致するまでを 1 つのコードスパンとする規則) に基づいて修正パターンを設計し、実際の入出力を Python で直接検証することで正当性を確認した。
