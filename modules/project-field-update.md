# Project Field Update + Label Fallback

Shared procedure for updating project SingleSelect fields (Priority / Size) via GraphQL and falling back to labels when the project is not found. Type uses the Issue Types API.

## Input

Information provided by the calling skill:

- **Field type**: `Priority` / `Size` / `Type`
- **Issue number**: Target Issue number (`$NUMBER`)
- **Determined value**: Value to set (e.g., `high`, `M`, `Feature`)

## Processing Steps

### Updating Priority / Size Fields

**Important: Execute steps 1→2→3→4 in order. If the GraphQL mutation in step 4 succeeds (exit 0 and `projectV2Item.id` returned), processing is complete. Execute the label fallback in step 5 only if steps 1–4 fail (i.e., mutation error in step 4).**

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

4. Set the field value and capture the mutation result:
   ```bash
   MUTATION_RESULT=$(${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query update-field-value -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F fieldId="$FIELD_ID" -F optionId="$OPTION_ID")
   MUTATION_EXIT=$?
   RETURNED_ID=$(echo "$MUTATION_RESULT" | jq -r '.data.updateProjectV2ItemFieldValue.projectV2Item.id // empty')
   ```
   - **If `MUTATION_EXIT` is 0 and `RETURNED_ID` is non-empty → mutation succeeded. Field write confirmed. Proceed to verify-after-write (warn-only) below. Skip step 5.**
   - **If `MUTATION_EXIT` is non-0 or `RETURNED_ID` is empty → mutation failed. Proceed to step 5 (label fallback).**

#### Verify-after-write (for Size field; warn-only eventual-consistency monitoring)

After the GraphQL mutation in step 4 confirms success (exit 0 and `projectV2Item.id` returned), read back the Size value to monitor for GitHub Projects V2 eventual-consistency delays. Read-back mismatches do **not** trigger label fallback — they emit a warn and monitoring continues. Label fallback is only executed when the mutation itself fails (step 5).

1. Read back the Size immediately after the mutation:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache $NUMBER
   ```
2. Compare the returned value against the determined Size (e.g., `XS`, `M`):
   - If they match → monitoring complete. Processing complete.
   - If they do not match (or the script returns empty) → output a warn and proceed to retry loop below.
3. Retry loop (max 3 attempts, increasing wait):
   - Attempt 1: wait 1 second, then re-read:
     ```bash
     sleep 1
     ```
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache $NUMBER
     ```
     If the value now matches → monitoring complete. Processing complete.
     If still mismatched → output a warn and continue.
   - Attempt 2: wait 2 seconds, then re-read:
     ```bash
     sleep 2
     ```
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache $NUMBER
     ```
     If the value now matches → monitoring complete. Processing complete.
     If still mismatched → output a warn and continue.
   - Attempt 3: wait 3 seconds, then re-read:
     ```bash
     sleep 3
     ```
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache $NUMBER
     ```
     If the value now matches → monitoring complete. Processing complete.
4. If all 3 retries fail (value still does not match or remains empty): output a warn — "Size field write confirmed by mutation (projectV2Item.id returned), but read-back mismatch after retries — probable eventual-consistency delay. No label fallback." — and complete processing. **Do not proceed to step 5.**

**For Priority/Value fields:** No read-back helper is currently available. When eventual consistency issues arise for these fields, extend this verify-after-write pattern using an appropriate API query to read back the field value.

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
