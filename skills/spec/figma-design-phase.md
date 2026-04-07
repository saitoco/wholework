# UI Design Phase

## Purpose

Collect and organize design information for Issues that require UI design.

## Auto-detection Criteria

| Judgment | Issue characteristics |
|----------|----------------------|
| **UI design needed** | Web app UI, component design, screen layout, frontend implementation |
| **UI design not needed (skip)** | Backend, CLI tools, config file changes, documentation updates, refactoring |
| **Cannot determine** | Confirm with user via AskUserQuestion |

## Steps

When UI design is determined to be needed, execute the following steps.

1. Propose wireframe/UI approach in text form
2. Confirm with user via AskUserQuestion:
   - **A) Figma design ready** — ask them to provide the Figma link
   - **B) Will design in Figma** — Claude creates a text-based UI proposal; user finishes in Figma and provides the link
   - **C) Proceed with text-based UI spec** — skip Figma integration and describe UI spec in text
   - **D) Object selected in Figma Desktop** — fetch the selected object via local MCP (`plugin:figma:figma`) without a URL

3. **When a Figma design is provided (A or after B is complete):**

   Receive the Figma link from the user and fetch information using the following tools:

   ```
   # Get code structure (React + Tailwind by default; framework changeable via prompt)
   mcp__plugin_figma_figma__get_design_context

   # Get design tokens (colors, spacing, typography)
   mcp__plugin_figma_figma__get_variable_defs

   # Get screenshot for visual reference
   mcp__plugin_figma_figma__get_screenshot
   ```

   **For large designs**: if `get_design_context` context is too large, first use `get_metadata` to understand the structure, then fetch only needed nodes with `get_design_context`.

   Reflect the obtained information in the Spec's "UI Design" section (see template below).

3-D. **When fetching a selected object in Figma Desktop (option D selected):**

   With the target object selected in Figma Desktop, fetch the selected object via local MCP:

   ```
   # Get code structure for the object selected in Figma Desktop
   mcp__plugin_figma_figma__get_design_context

   # Get screenshot of selected object
   mcp__plugin_figma_figma__get_screenshot
   ```

   The local MCP (`plugin:figma:figma`) integrates with Figma Desktop and can fetch only the selected object without a URL. More token-efficient than the cloud version (`mcp__claude_ai_Figma__`).

   **Combined use with cloud version**: use the cloud version (`mcp__claude_ai_Figma__get_design_context` with Figma URL) for full-screen understanding, and the local version for detailed fetching of selected objects — balancing precision and token efficiency.

   Reflect the obtained information in the Spec's "UI Design" section (see template below).

4. **Post UI design information to Issue comment:**

   Post the obtained Figma information as an Issue comment (in parallel with reflecting in the Spec).

## Spec "UI Design" Section Template

For Issues involving UI design, include the following section in the Spec:

```markdown
## UI Design

**(Include only for Issues involving UI. Omit if not applicable)**

### Design Source
- **Figma link**: [URL] (if applicable)
- **Fetch method**: get_design_context / text-based

### Component Structure
(component hierarchy extracted from get_design_context)

### Design Tokens
(colors, fonts, spacing, etc. extracted from get_variable_defs)

### Layout Spec
(screen layout, responsive behavior, etc.)
```
