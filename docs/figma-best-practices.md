---
type: project
ssot_for:
  - figma-workflow
---

English | [日本語](ja/figma-best-practices.md)

# Figma Best Practices Guide

This guide summarizes best practices for UI designers creating Figma design files to maximize code generation accuracy by AI agents (Claude + Figma MCP).

## Why Figma File Structure Matters

Figma MCP converts designs to React + Tailwind code representation using the `get_design_context` tool. Since the Figma file structure is directly reflected in the code structure, organized files produce clean code while disorganized files produce verbose code.

## 1. Component Structuring

Always make reused UI elements into Figma components.

### Good Examples

- Componentize common UI such as buttons, cards, input fields, and modals
- Define variants in components (Primary / Secondary / Ghost, etc.)
- Set properties in components (text, icon, state)

```
Components/
  Button/
    Primary (variant)
    Secondary (variant)
    Ghost (variant)
  Card/
    Default (variant)
    Highlighted (variant)
  Input/
    Text (variant)
    Password (variant)
```

### Bad Examples

- Copy and paste the same button design to each screen
- Create separate components instead of using variants (`ButtonRed`, `ButtonBlue`)
- Detach instances and apply local modifications

**Impact**: Without componentization, MCP recognizes each element independently and generates duplicate code.

## 2. Semantic Layer Names

Give layers meaningful names that indicate their function.

### Good Examples

```
LoginForm
  EmailInput
  PasswordInput
  SubmitButton
  ForgotPasswordLink
```

### Bad Examples

```
Frame 1
  Rectangle 5
  Text 12
  Group 3
    Vector 7
```

**Impact**: MCP uses layer names directly as component names and variable names. `Frame 1` significantly reduces generated code readability.

## 3. Using Variables

Use Figma variables for colors, spacing, border radius, and typography.

### Good Examples

- Colors: `colors/primary/500`, `colors/neutral/100`
- Spacing: `spacing/sm` (8px), `spacing/md` (16px), `spacing/lg` (24px)
- Border radius: `radius/sm` (4px), `radius/md` (8px)
- Typography: `text/heading/lg`, `text/body/md`

### Bad Examples

- Directly specify colors: hardcode `#3B82F6`
- Specify spacing in pixel values individually: 16px, 17px, 15px scattered across elements
- Use the same color with different values in multiple places within the file

**Impact**: `get_variable_defs` extracts variables used in the file. Without variables, hardcoded values are reflected directly in code, losing consistency with the design system.

## 4. Leveraging Auto Layout

Use Auto Layout to communicate responsive intent.

### Good Examples

- Card list: horizontal Auto Layout + Wrap
- Form: vertical Auto Layout + Fill container
- Header: horizontal Auto Layout + Space between
- Verify that resizing behaves as intended

### Bad Examples

- Position elements with absolute coordinates manually
- Layer elements inside fixed-size frames
- Group elements with Group instead of Auto Layout

**Impact**: Auto Layout information is directly converted to flexbox / grid code. Positioning with absolute coordinates generates code full of `position: absolute`, making responsive design difficult.

## 5. Adding Annotations

Supplement behavior and intent that cannot be conveyed visually with annotations.

### Information to Add

- Interactions: hover animations, click transition destinations
- Animations: transition type and duration
- Responsive: display switching rules per breakpoint
- States: loading, error, empty states
- Accessibility: reading order for screen readers

Use Figma's Dev Resources feature to attach links and notes to frames.

## 6. File Organization Guidelines

### Recommended Structure

```
Page: Design System
  Frame: Colors
  Frame: Typography
  Frame: Icons
  Frame: Components

Page: Login Flow
  Frame: Login Screen
  Frame: Registration Screen
  Frame: Password Reset

Page: Dashboard
  Frame: Overview
  Frame: Settings
  Frame: Profile
```

### Structures to Avoid

- Placing all screens on a single page
- Mixing component definitions with screen designs
- Large numbers of unused frames or layers remaining

**Impact**: When specifying nodes with MCP, an organized file quickly identifies the target frame and prevents unnecessary context from being mixed in.

## Checklist

Before using a design with `/spec`, verify the following:

- [ ] Reused UI elements are componentized
- [ ] Layers have semantic names (no `Frame 1`)
- [ ] Variables are used for colors, spacing, and typography
- [ ] Auto Layout communicates responsive intent in the structure
- [ ] Resizing the target frame behaves as intended
- [ ] Unnecessary layers and detached instances are cleaned up
