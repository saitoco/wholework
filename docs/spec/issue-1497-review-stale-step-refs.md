# Issue #1497: review: SKILL.md 本文の古い Step 番号参照を現行構成に合わせる

## Issue Retrospective

### 曖昧点の自動解決 (non-interactive)

- **対象範囲**: Background は古い Step 参照を 3 か所と述べるが、rubric 条件は「ほかに古い参照が残っていない」ことを求めている。`skills/review/SKILL.md` を実測したところ、確定の 8 か所 (337・837・896・902・904・923・999・1003 行目) と要判定の 3 件 (353 行目、740〜810 行目の "Step 9 was run" 系、878 行目) が追加で見つかった。Purpose と rubric 条件が全件を求めているため、3 か所に絞らず全件を対象とした
- 追加分は Background に「追加調査」節として列挙した。要判定分は文脈次第なので `/code` の判断に任せ、rubric の文面にその箇所を名指しした

### 受入条件の変更

- AC 5 の `python3 scripts/validate-skill-syntax.py` は引数なしだと usage エラーで常に exit 1 になる (常時 FAIL) ため、CI (`.github/workflows/test.yml`) と同じ `skills/` 引数付きに修正した (実測 exit 0)
- 確定分の 8 か所のうち、元の AC 1〜3 で未カバーの 8 件を `file_not_contains` で機械的に検証する条件として追加した (rubric の補助)

### Consumed Comments

No new comments since last phase.

## Consumed Comments
No new comments since last phase.
