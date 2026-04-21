# Issue #298: /doc sync --deep skill scan skill-dev gate

## Overview

`/doc sync --deep` の Step 6（sync Bidirectional Normalization）内に3箇所の skill-dev 専用処理が gate なしで記述されている。

1. **Scan implementation code** ブロック（`skills/*/SKILL.md`, `modules/*.md`, `agents/*.md`, `scripts/*.sh` を無条件 Glob+Read）
2. **Narrative Semantic Drift Check** の **Skill Coverage Gap** カテゴリ（`skills/*/SKILL.md` の存在を前提に検出）
3. **Terms consistency check** の skill/module/agent ファイルスキャン（deprecated term 検出・missing term 検出）

非 skill-dev プロジェクトではこれらのディレクトリが存在せず、Glob が空結果を返すだけでなく drift 検出ロジックも意味を持たない。`scripts/validate-skill-syntax.py` 存在または `skills/` ディレクトリ存在を skill-dev 判定条件として3箇所に gate を追加する。

## Changed Files

- `skills/doc/SKILL.md`: Step 6 に skill-dev 判定 gate を3箇所追加

## Implementation Steps

1. `skills/doc/SKILL.md` Step 6 の **Scan implementation code** ブロックに skill-dev 判定を追加: `scripts/validate-skill-syntax.py` 存在または `skills/` ディレクトリ存在の場合のみ Glob+Read を実行し、どちらも存在しない場合はこのブロック全体をスキップすると明記する（→ 受入 A）
2. **Narrative Semantic Drift Check** の **Input sources for comparison** 内の implementation files 行に、上記 gate が有効な場合のみ利用可能である旨を追記し、4カテゴリテーブルの **Skill Coverage Gap** 行に「skill-dev プロジェクトの場合のみ適用」と明記する（→ 受入 A）
3. **Terms consistency check** のブロック先頭に skill-dev 判定 gate を追記: `--deep` フラグに加えて skill-dev プロジェクト判定も条件とし、非 skill-dev プロジェクトではこのチェック全体をスキップすると明記する（→ 受入 A）

## Verification

### Pre-merge

- <!-- verify: rubric "In skills/doc/SKILL.md Step 6 (sync Bidirectional Normalization), the 'Scan implementation code' block, the 'Skill Coverage Gap' drift category, and the Terms consistency check's skill/module/agent file scanning are all gated by an explicit skill-dev project condition (e.g., scripts/validate-skill-syntax.py existence); SKILL.md documents that these steps are skipped when the condition fails" --> skill-dev 判定 gate が3箇所に追加されている
- <!-- verify: grep "Scan implementation code" "skills/doc/SKILL.md" --> Scan implementation code 節の見出しが存在する
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> SKILL.md 構文エラーなし

### Post-merge

- wholework リポ自身で `/doc sync --deep` を実行し、skill-dev 特化の drift 検出が従来通り動作することを確認
- 非 skill-dev プロジェクトで `/doc sync --deep` を実行し、Skill Coverage Gap や Terms consistency check のノイズが出ないことを確認

## Notes

- 条件式の表現は `If scripts/validate-skill-syntax.py exists or skills/ directory exists:` の形式で統一する（既存の line 504 の gate 表現 `If scripts/validate-skill-syntax.py exists, ...` より広い条件）
- **Scan implementation code** ブロックの直後にある **Cross-skill consistency check**（line 502-504）はすでに `validate-skill-syntax.py` 存在チェックで gate されており変更不要
- **Narrative Semantic Drift Check** の **Input sources for comparison** 3行目（implementation files）はブロック gate の影響を受けるため、条件付き利用であることを示す注記を追加する（Step 2 で対応）

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body と Spec の実装ステップが明確に対応しており、3箇所の gate 追加箇所が具体的に記述されていた。受け入れ条件も rubric/grep/command と適切なコマンドが割り当てられていた。

#### design
- Spec の Notes セクションに既存の gate 表現との差分（既存: `validate-skill-syntax.py` 存在チェックのみ、新規: `skills/` ディレクトリ存在も含む広条件）が明記されており、判断根拠が残っている。設計品質は良好。

#### code
- 実装は1コミット（7行追加、3行変更）で完結。リワークなし。Spec の実装ステップ3項目に完全対応。

#### review
- patch route（main直コミット）のため PR レビューは実施されていない。小規模変更（10行以下）かつ rubric で意味的検証を行ったため、レビュー省略の判断は妥当。

#### merge
- patch route で main に直接マージ。コンフリクトなし。

#### verify
- 全3条件（rubric/grep/command）が PASS。Post-merge の manual 条件2件は非自動検証対象のため user verification guide として提示。verify コマンドの設計が適切で自動判定に成功した。

### Improvement Proposals
- N/A
