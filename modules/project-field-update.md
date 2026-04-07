# Project Field Update + Label Fallback

Shared procedure for updating project SingleSelect fields (Priority / Size) via GraphQL and falling back to labels when the project is not found. Type uses the Issue Types API.

## Input

Information provided by the calling skill:

- **Field type**: `Priority` / `Size` / `Type`
- **Issue number**: Target Issue number (`$NUMBER`)
- **Determined value**: Value to set (e.g., `high`, `M`, `Feature`)

## Processing Steps

### Updating Priority / Size Fields

**Important: Execute steps 1→2→3→4 in order. If the GraphQL mutation in step 4 succeeds, processing is complete. Execute the label fallback in step 5 only if steps 1-4 fail.**

1. Dynamically fetch projects linked to the repository:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --cache --query get-projects-with-fields
   ```
   - If `projectsV2.nodes` is an empty array → proceed to step 5 (label fallback)

2. Identify the target field in the first found project (search by field name "Priority" or "Size")
   - If target field is not found → proceed to step 5 (label fallback)

3. Add Issue to the project if not already added:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --cache --query get-issue-id -F num=$NUMBER --jq '.data.repository.issue.id'
   ```
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query add-project-item -F projectId="$PROJECT_ID" -F contentId="$ISSUE_ID"
   ```

4. Set the field value:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query update-field-value -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_ID" -F optionId="$OPTION_ID"
   ```
   - **If successful → processing complete. Skip step 5.**

5. Label fallback (only if steps 1-4 failed):
   - Auto-create label if it does not exist:
     ```bash
     gh label create "{prefix}/{determined-value}" --force
     ```
   - Remove existing labels then apply new label (see label naming convention table)

### Label Naming Conventions

| Field | Prefix | Options (exhaustive) | Labels to Remove |
|-------|--------|---------------------|-----------------|
| Priority | `priority/` | `urgent`, `high`, `medium`, `low` | `--remove-label "priority/urgent" --remove-label "priority/high" --remove-label "priority/medium" --remove-label "priority/low"` |
| Size | `size/` | `XS`, `S`, `M`, `L`, `XL` | `--remove-label "size/XS" --remove-label "size/S" --remove-label "size/M" --remove-label "size/L" --remove-label "size/XL"` |
| Type | `type/` | `bug`, `feature`, `task` | `--remove-label "type/bug" --remove-label "type/feature" --remove-label "type/task"` |

### Updating Type Field

Type uses the Issue Types API (`updateIssueIssueType` mutation). **Execute steps 1→2 in order; if successful, done. Execute the label fallback in step 3 only if Issue Types are unavailable.**

1. Check if Issue Types are available in the repository:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --cache --query get-issue-types --jq '.data.repository.issueTypes.nodes // []'
   ```
   - If `nodes` is empty array or `issueTypes` is null → proceed to step 3 (label fallback)

2. If Issue Types are available (`nodes` is non-empty):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --cache --query get-issue-id -F num=$NUMBER --jq '.data.repository.issue.id'
   ```
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query update-issue-type -F issueId="$ISSUE_ID" -F typeId="$TYPE_ID"
   ```
   - **If successful → processing complete. Skip step 3.**

3. Label fallback (only if Issue Types are unavailable):
   Normalize the determined value to the Type options in the label naming convention table (`bug`, `feature`, `task`). Map values not in the table to the closest option (e.g., `enhancement` → `feature`, `defect` → `bug`).
   ```bash
   gh issue edit $NUMBER --remove-label "type/bug" --remove-label "type/feature" --remove-label "type/task" --add-label "type/{normalized-determined-value}"
   ```
