#!/usr/bin/env python3
"""
Skill syntax validation script

Validates YAML frontmatter and Markdown body syntax.
Uses Python standard library only.
"""

import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


# Known frontmatter fields
KNOWN_FIELDS = {'name', 'description', 'allowed-tools', 'argument-hint', 'context', 'agent', 'model'}

# Known Claude Code tool names (for validating allowed-tools base tool names)
KNOWN_TOOLS = {
    'Bash', 'Glob', 'Grep', 'Read', 'Write', 'Edit',
    'TaskCreate', 'TaskUpdate', 'TaskList', 'TaskGet', 'TaskOutput',  # TaskOutput: retrieve background task results (#387)
    'AskUserQuestion', 'WebFetch', 'WebSearch',
    'NotebookEdit', 'EnterPlanMode', 'Task', 'Skill', 'ToolSearch', 'Agent',
    'EnterWorktree', 'ExitWorktree',
}

# Tool names that must not appear in allowed-tools
# AskUserQuestion is a built-in tool and can be called without listing it in allowed-tools.
# Including it triggers the alwaysAllowRules early-return, causing an empty response with no UI prompt (claude-code#29547)
FORBIDDEN_ALLOWED_TOOLS = {'AskUserQuestion'}

# Tool names excluded from body tool usage checks
# Task appears frequently as an Issue type name (Bug/Feature/Task), and Agent appears as
# a subagent type name or product name (e.g. "GitHub Copilot Agent") in SKILL.md bodies,
# so exclude them from tool usage checks to avoid false positives
BODY_TOOL_CHECK_SKIP = {'Task', 'Agent', 'Skill'}

# Valid values for the context field
VALID_CONTEXTS = {'fork'}

# Valid values for the agent field
VALID_AGENTS = {'general-purpose'}

# Pattern for the name field (lowercase letters, digits, hyphens only)
NAME_PATTERN = re.compile(r'^[a-z0-9-]+$')

# Forbidden patterns inside bash code blocks (patterns that break permission pattern matching)
FORBIDDEN_BASH_PATTERNS = [
    (re.compile(r'<\s*/tmp/'), 'Shell redirect (< /tmp/...) breaks permission pattern matching. Pass the file path as an argument to the script instead'),
    (re.compile(r'\$\(cat\s'), 'Command substitution $(cat ...) causes multiline expansion that breaks pattern matching. Pass the file path as an argument to the script instead'),
    (re.compile(r'--body\s+"\$[A-Z_]'), '--body "$VAR" causes multiline variable expansion that breaks pattern matching. Pass the file path as an argument to the script instead'),
]

# Pattern to extract bash code blocks
BASH_CODEBLOCK_PATTERN = re.compile(r'```bash\s*\n(.*?)```', re.DOTALL)

# Pattern to extract all code fences (any language)
ALL_CODEBLOCK_PATTERN = re.compile(r'```[^\n]*\n.*?```', re.DOTALL)

# Pattern to extract HTML comments (<!-- verify: ... --> etc.)
HTML_COMMENT_PATTERN = re.compile(r'<!--.*?-->', re.DOTALL)

# Pattern to extract inline code (`...`)
INLINE_CODE_PATTERN = re.compile(r'`[^`]+`')

# Pattern for shell-sensitive characters forbidden outside code fences
# `!` is detected as a shell operator by the Claude Code Bash permission checker
SHELL_SENSITIVE_CHAR_PATTERN = re.compile(r'!')

# Pattern to extract script paths from allowed-tools
SCRIPT_PATH_PATTERN = re.compile(r'\$\{CLAUDE_PLUGIN_ROOT\}/scripts/([a-zA-Z0-9_-]+\.sh)')

# Pattern to extract module file references from SKILL.md body
MODULES_REF_PATTERN = re.compile(r'\$\{CLAUDE_PLUGIN_ROOT\}/modules/([a-zA-Z0-9_-]+\.md)')


def parse_simple_yaml(text: str) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """
    Parses simple YAML (key: value format only).
    Uses Python standard library only.

    Returns:
        (parsed_dict, error_message)
    """
    result: Dict[str, Any] = {}

    for line_num, line in enumerate(text.split('\n'), 1):
        line = line.rstrip()

        # Skip empty lines and comments
        if not line or line.startswith('#'):
            continue

        # Parse key: value format
        match = re.match(r'^([a-zA-Z_-][a-zA-Z0-9_-]*)\s*:\s*(.*)$', line)
        if not match:
            return None, f"line {line_num}: invalid format '{line}'"

        key = match.group(1)
        value = match.group(2)

        # Infer value type
        if value == '' or value == '~' or value.lower() == 'null':
            result[key] = None
        elif value.lower() == 'true':
            result[key] = True
        elif value.lower() == 'false':
            result[key] = False
        elif re.match(r'^-?\d+$', value):
            result[key] = int(value)
        elif re.match(r'^-?\d+\.\d+$', value):
            result[key] = float(value)
        else:
            # Treat as string (strip quotes)
            if (value.startswith('"') and value.endswith('"')) or \
               (value.startswith("'") and value.endswith("'")):
                value = value[1:-1]
            result[key] = value

    return result, None


def parse_frontmatter(content: str) -> Tuple[Optional[Dict[str, Any]], str, Optional[str]]:
    """
    Parses YAML frontmatter from a Markdown document.

    Returns:
        (frontmatter_dict, body, error_message)
    """
    if not content.startswith('---'):
        return None, content, "frontmatter not found (does not start with '---')"

    # Find the end of frontmatter
    end_match = re.search(r'\n---\n', content[3:])
    if not end_match:
        return None, content, "frontmatter closing marker ('---') not found"

    frontmatter_text = content[4:end_match.start() + 3]  # skip leading '---\n'
    body = content[end_match.end() + 3:]  # body after closing marker

    frontmatter, parse_error = parse_simple_yaml(frontmatter_text)
    if parse_error:
        return None, body, f"YAML parse error: {parse_error}"

    if frontmatter is None:
        frontmatter = {}

    return frontmatter, body, None


def validate_skill(file_path: Path) -> Tuple[List[str], List[str]]:
    """
    Validates a skill file.

    Returns:
        (errors, warnings)
    """
    errors: List[str] = []
    warnings: List[str] = []

    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception as e:
        return [f"file read error: {e}"], []

    # Parse frontmatter
    frontmatter, body, parse_error = parse_frontmatter(content)
    if parse_error:
        errors.append(parse_error)
        return errors, warnings

    if frontmatter is None:
        frontmatter = {}

    # Validate name field
    if 'name' not in frontmatter:
        errors.append("required field 'name' is missing")
    elif not isinstance(frontmatter['name'], str):
        errors.append("'name' must be a string")
    elif not NAME_PATTERN.match(frontmatter['name']):
        errors.append(f"'name' may only contain lowercase letters, digits, and hyphens: '{frontmatter['name']}'")

    # Validate description field
    if 'description' not in frontmatter:
        errors.append("required field 'description' is missing")
    elif not isinstance(frontmatter['description'], str):
        errors.append("'description' must be a string")
    elif not frontmatter['description'].strip():
        errors.append("'description' must not be empty")

    # Validate allowed-tools field (if present)
    if 'allowed-tools' in frontmatter:
        allowed_tools = frontmatter['allowed-tools']
        if not isinstance(allowed_tools, str):
            errors.append("'allowed-tools' must be a string")
        else:
            tool_errors = validate_allowed_tools_names(allowed_tools)
            errors.extend(tool_errors)

    # Validate context field value (if present)
    if 'context' in frontmatter:
        context_val = frontmatter['context']
        if not isinstance(context_val, str):
            errors.append("'context' must be a string")
        elif context_val not in VALID_CONTEXTS:
            errors.append(f"'context' の値が無効です: '{context_val}'（有効値: {', '.join(sorted(VALID_CONTEXTS))}）")

    # Validate agent field value (if present)
    if 'agent' in frontmatter:
        agent_val = frontmatter['agent']
        if not isinstance(agent_val, str):
            errors.append("'agent' must be a string")
        elif agent_val not in VALID_AGENTS:
            errors.append(f"'agent' の値が無効です: '{agent_val}'（有効値: {', '.join(sorted(VALID_AGENTS))}）")

    # Validate argument-hint field (if present)
    if 'argument-hint' in frontmatter:
        argument_hint = frontmatter['argument-hint']
        if not isinstance(argument_hint, str):
            errors.append("'argument-hint' must be a string")

    # Warn about unknown fields
    unknown_fields = set(frontmatter.keys()) - KNOWN_FIELDS
    for field in sorted(unknown_fields):
        warnings.append(f"unknown field: '{field}'")

    # Validate Markdown body
    body_stripped = body.strip()
    if not body_stripped:
        errors.append("Markdown body is empty")

    # Validate forbidden patterns in bash code blocks
    bash_errors = validate_bash_safety(content)
    errors.extend(bash_errors)

    # Validate consistency between allowed-tools and scripts/
    scripts_dir = file_path.parent.parent.parent / 'scripts'
    tool_errors = validate_allowed_tools_scripts(frontmatter, scripts_dir)
    errors.extend(tool_errors)

    # Validate script path references in Markdown body
    body_script_errors = validate_body_script_paths(body, scripts_dir)
    errors.extend(body_script_errors)

    # Validate that scripts referenced in body are also in allowed-tools
    allowed_tools_value = frontmatter.get('allowed-tools', '')
    if isinstance(allowed_tools_value, str):
        script_allowed_errors = validate_body_scripts_in_allowed_tools(body, allowed_tools_value)
        errors.extend(script_allowed_errors)

    # Validate that tools used in body are listed in allowed-tools
    if isinstance(allowed_tools_value, str):
        tools_allowed_errors = validate_body_tools_in_allowed_tools(body, allowed_tools_value)
        errors.extend(tools_allowed_errors)

    # Validate shell-sensitive characters outside code fences
    shell_char_errors = validate_shell_sensitive_chars(body)
    errors.extend(shell_char_errors)

    # Validate decimal steps
    decimal_step_errors = validate_decimal_steps(body)
    errors.extend(decimal_step_errors)

    # Validate Phase-only headings
    phase_heading_errors = validate_phase_headings(body)
    errors.extend(phase_heading_errors)

    # Validate ~/.claude/scripts paths in command hints
    command_hint_errors = validate_command_hint_paths(body)
    errors.extend(command_hint_errors)

    # Validate verify hint syntax (command name and argument count)
    verify_hint_errors = validate_verify_hints(body)
    errors.extend(verify_hint_errors)

    return errors, warnings


def validate_bash_safety(content: str) -> List[str]:
    """
    Validates that bash code blocks in SKILL.md body do not contain forbidden patterns.
    Comment lines (starting with #) are skipped.

    Returns:
        List of error messages
    """
    errors: List[str] = []

    # Extract bash code blocks
    for block_match in BASH_CODEBLOCK_PATTERN.finditer(content):
        block_content = block_match.group(1)
        # Calculate line number from block start position
        block_start_line = content[:block_match.start()].count('\n') + 2  # line after ```bash

        for line_offset, line in enumerate(block_content.split('\n')):
            stripped_line = line.strip()

            # Skip comment lines (to avoid false positives on example comments)
            if stripped_line.startswith('#'):
                continue

            for pattern, message in FORBIDDEN_BASH_PATTERNS:
                if pattern.search(line):
                    # Exclude gh issue create --body (direct issue creation commands are allowed)
                    if 'gh issue create' in line and '--body' in line:
                        continue
                    line_num = block_start_line + line_offset
                    errors.append(f"line {line_num}: forbidden pattern detected — {message}")

    return errors


def validate_allowed_tools_scripts(frontmatter: Dict[str, Any], scripts_dir: Path) -> List[str]:
    """
    Validates that script paths listed in allowed-tools exist in the scripts/ directory.

    Returns:
        List of error messages
    """
    errors: List[str] = []

    allowed_tools = frontmatter.get('allowed-tools', '')
    if not isinstance(allowed_tools, str):
        return errors

    # Extract ~/.claude/scripts/*.sh paths from allowed-tools
    for match in SCRIPT_PATH_PATTERN.finditer(allowed_tools):
        script_name = match.group(1)
        script_path = scripts_dir / script_name

        if not script_path.exists():
            errors.append(f"script listed in allowed-tools does not exist: scripts/{script_name}")

    return errors


def validate_allowed_tools_names(allowed_tools: str) -> List[str]:
    """
    Validates that base tool names in allowed-tools are in KNOWN_TOOLS.

    Splits the allowed-tools value (e.g. "Bash(gh issue view:*, git checkout:*), Read, Glob")
    by commas and validates only the base tool name (the part before parentheses) of each entry.

    Returns:
        List of error messages
    """
    errors: List[str] = []

    # Split by top-level commas, respecting parenthesis nesting
    entries = _split_allowed_tools(allowed_tools)

    for entry in entries:
        entry = entry.strip()
        if not entry:
            continue

        # Extract base tool name (part before parentheses)
        paren_idx = entry.find('(')
        if paren_idx >= 0:
            base_name = entry[:paren_idx].strip()
        else:
            base_name = entry.strip()

        if base_name and base_name in FORBIDDEN_ALLOWED_TOOLS:
            errors.append(
                f"forbidden tool in allowed-tools: '{base_name}'"
                f" (built-in tool; including it in allowed-tools breaks the UI. claude-code#29547)"
            )
        elif base_name and base_name not in KNOWN_TOOLS and not base_name.startswith('mcp__'):
            errors.append(f"unknown tool name in allowed-tools: '{base_name}'")

    return errors


def _split_allowed_tools(value: str) -> List[str]:
    """
    Splits the allowed-tools value by top-level commas, respecting parenthesis nesting.

    Example: "Bash(gh issue view:*, git:*), Read" -> ["Bash(gh issue view:*, git:*)", "Read"]
    """
    entries: List[str] = []
    depth = 0
    current = []

    for char in value:
        if char == '(':
            depth += 1
            current.append(char)
        elif char == ')':
            depth = max(0, depth - 1)
            current.append(char)
        elif char == ',' and depth == 0:
            entries.append(''.join(current))
            current = []
        else:
            current.append(char)

    if current:
        entries.append(''.join(current))

    return entries


def validate_shell_sensitive_chars(body: str) -> List[str]:
    """
    Validates that the SKILL.md body does not contain shell-sensitive characters outside code fences.

    The Claude Code Bash permission checker may misdetect `!` and similar characters in
    SKILL.md text as shell operators, so their use outside code fences is forbidden.

    Returns:
        List of error messages
    """
    errors: List[str] = []

    # Remove code fences -> inline code -> HTML comments (excluded from inspection)
    # Note: remove inline code before HTML comments to avoid breaking <!-- ... --> inside backticks
    body_without_fences = ALL_CODEBLOCK_PATTERN.sub('', body)
    body_without_fences = INLINE_CODE_PATTERN.sub('', body_without_fences)
    body_without_fences = HTML_COMMENT_PATTERN.sub('', body_without_fences)

    for match in SHELL_SENSITIVE_CHAR_PATTERN.finditer(body_without_fences):
        # Estimate line number from match position
        line_num = body_without_fences[:match.start()].count('\n') + 1
        errors.append(
            f"body line {line_num}: shell-sensitive character '!' found outside code fence."
            " The Claude Code Bash permission checker may misdetect this;"
            " replace with a fullwidth character or rephrase"
        )

    return errors


def validate_decimal_steps(body: str) -> List[str]:
    """
    Validates that the SKILL.md body does not contain decimal steps (### Step N.M:) outside code fences.

    Returns:
        List of error messages
    """
    errors: List[str] = []

    # Remove code fences -> inline code -> HTML comments
    body_stripped = ALL_CODEBLOCK_PATTERN.sub('', body)
    body_stripped = INLINE_CODE_PATTERN.sub('', body_stripped)
    body_stripped = HTML_COMMENT_PATTERN.sub('', body_stripped)

    pattern = re.compile(r'###\s+Step\s+\d+\.\d+[:\s]')
    for match in pattern.finditer(body_stripped):
        line_num = body_stripped[:match.start()].count('\n') + 1
        errors.append(
            f"body line {line_num}: 小数ステップ（Step N.M 形式）は禁止されています。"
            " 整数ステップ（Step N: 形式）に変更してください"
        )

    return errors


def validate_phase_headings(body: str) -> List[str]:
    """
    Validates that the SKILL.md body does not contain Phase-only headings (### Phase N:) outside code fences.

    Returns:
        List of error messages
    """
    errors: List[str] = []

    # Remove code fences -> inline code -> HTML comments
    body_stripped = ALL_CODEBLOCK_PATTERN.sub('', body)
    body_stripped = INLINE_CODE_PATTERN.sub('', body_stripped)
    body_stripped = HTML_COMMENT_PATTERN.sub('', body_stripped)

    pattern = re.compile(r'###\s+Phase\s+\d+[:\s]')
    for match in pattern.finditer(body_stripped):
        line_num = body_stripped[:match.start()].count('\n') + 1
        errors.append(
            f"body line {line_num}: Phase-only heading (### Phase N: format) is forbidden."
            " Use ### Step N: format instead"
        )

    return errors


# Known verify commands and argument counts (min_args, max_args)
# Source of truth: verify-executor.md translation table
KNOWN_VERIFY_COMMANDS: Dict[str, Tuple[int, int]] = {
    'file_exists': (1, 1),
    'file_not_exists': (1, 1),
    'dir_exists': (1, 1),
    'dir_not_exists': (1, 1),
    'file_contains': (2, 2),
    'file_not_contains': (2, 2),
    'grep': (2, 2),
    'command': (1, 1),
    'json_field': (3, 3),
    'section_contains': (3, 3),
    'section_not_contains': (3, 3),
    'symlink': (2, 2),
    'http_status': (2, 2),
    'http_header': (3, 3),
    'http_redirect': (3, 3),
    'build_success': (1, 1),
    'browser_check': (2, 3),
    'browser_screenshot': (2, 2),
    'mcp_call': (2, 2),
    'github_check': (2, 2),
}


def _parse_verify_args(args_str: str) -> List[str]:
    """
    Parses the argument string of a verify hint and returns a list of arguments.
    Handles double-quoted arguments with escape sequences.

    Raises:
        ValueError: if an unclosed quote or invalid escape sequence is detected
    """
    args: List[str] = []
    i = 0
    s = args_str.strip()
    while i < len(s):
        if s[i] == '"':
            # Parse quoted argument
            i += 1
            buf = []
            closed = False
            while i < len(s):
                if s[i] == '\\':
                    if i + 1 >= len(s):
                        raise ValueError(f"unclosed double quote in verify argument: {args_str}")
                    nxt = s[i + 1]
                    if nxt not in {'"', '\\'}:
                        raise ValueError(
                            f"invalid escape sequence in verify argument"
                            f" (valid: \\\" and \\\\): {args_str}"
                        )
                    buf.append(nxt)
                    i += 2
                elif s[i] == '"':
                    i += 1
                    closed = True
                    break
                else:
                    buf.append(s[i])
                    i += 1
            if not closed:
                raise ValueError(f"unclosed double quote in verify argument: {args_str}")
            args.append(''.join(buf))
        elif s[i] == ' ':
            i += 1
        else:
            # Unquoted argument (up to next space)
            j = i
            while j < len(s) and s[j] != ' ':
                j += 1
            args.append(s[i:j])
            i = j
    return args


def validate_verify_hints(body: str) -> List[str]:
    """
    Validates <!-- verify: ... --> hints in the SKILL.md body.
    Hints inside code fences or inline code are excluded from validation.

    Returns:
        List of error messages
    """
    errors: List[str] = []

    # Remove code fences -> inline code (excluded from inspection)
    body_stripped = ALL_CODEBLOCK_PATTERN.sub('', body)
    body_stripped = INLINE_CODE_PATTERN.sub('', body_stripped)

    for comment_match in HTML_COMMENT_PATTERN.finditer(body_stripped):
        comment_text = comment_match.group(0)
        # Only process <!-- verify: ... --> format
        inner = comment_text[4:-3].strip()
        if not inner.startswith('verify:'):
            continue

        line_num = body_stripped[:comment_match.start()].count('\n') + 1
        verify_content = inner[len('verify:'):].strip()

        # Extract command name (up to first space)
        parts = verify_content.split(' ', 1)
        cmd = parts[0]
        args_str = parts[1] if len(parts) > 1 else ''

        # Command name is empty (e.g. <!-- verify: -->)
        if not cmd:
            errors.append(f"body line {line_num}: verify hint has no command name.")
            continue

        # Skip template placeholders ({...} format)
        if cmd.startswith('{'):
            continue

        if cmd not in KNOWN_VERIFY_COMMANDS:
            errors.append(
                f"body line {line_num}: 未知の verify コマンド '{cmd}'。"
                f" 既知コマンド: {', '.join(sorted(KNOWN_VERIFY_COMMANDS))}"
            )
            continue

        min_args, max_args = KNOWN_VERIFY_COMMANDS[cmd]
        try:
            _parse_verify_args(args_str)
        except ValueError as e:
            errors.append(f"body line {line_num}: 構文エラー in verify command '{cmd}': {e}")
            continue
        # Exclude --when modifier from argument count
        args_str_for_count = re.sub(r'\s*--when=(?:"[^"\\]*(?:\\.[^"\\]*)*"|[^\s]+)', '', args_str)
        try:
            parsed_args = _parse_verify_args(args_str_for_count)
        except ValueError:
            parsed_args = [a for a in _parse_verify_args(args_str) if not a.startswith('--when=')]
        num_args = len(parsed_args)

        if num_args < min_args:
            errors.append(
                f"body line {line_num}: 引数が不足 in verify command '{cmd}'"
                f" ({num_args} provided, minimum {min_args} required)"
            )
        elif num_args > max_args:
            errors.append(
                f"body line {line_num}: 引数が多すぎます in verify command '{cmd}'"
                f" ({num_args} provided, maximum {max_args})"
            )

    return errors


def validate_command_hint_paths(body: str) -> List[str]:
    """
    Validates that verify command hints in SKILL.md body do not contain plugin-internal
    script paths. Detects <!-- verify: command "${CLAUDE_PLUGIN_ROOT}/scripts/..." -->
    patterns in HTML comments. Command hints should use repository-relative paths (scripts/xxx).

    Returns:
        List of error messages
    """
    errors: List[str] = []

    # Remove code fences and inline code (HTML comments are search targets, keep them)
    body_stripped = ALL_CODEBLOCK_PATTERN.sub('', body)
    body_stripped = INLINE_CODE_PATTERN.sub('', body_stripped)

    # Search for ${CLAUDE_PLUGIN_ROOT}/scripts inside HTML comments
    for comment_match in HTML_COMMENT_PATTERN.finditer(body_stripped):
        comment_text = comment_match.group(0)
        if 'CLAUDE_PLUGIN_ROOT' in comment_text and '/scripts/' in comment_text:
            line_num = body_stripped[:comment_match.start()].count('\n') + 1
            errors.append(
                f"body line {line_num}: '{{CLAUDE_PLUGIN_ROOT}}/scripts' path found in verify command hint."
                " Use a repository-relative path (scripts/xxx) instead"
            )

    return errors


def validate_body_script_paths(body: str, scripts_dir: Path) -> List[str]:
    """
    Validates that ${CLAUDE_PLUGIN_ROOT}/scripts/*.sh path references in the Markdown body
    actually exist.

    Returns:
        List of error messages
    """
    errors: List[str] = []
    seen: set = set()

    for match in SCRIPT_PATH_PATTERN.finditer(body):
        script_name = match.group(1)
        if script_name in seen:
            continue
        seen.add(script_name)

        script_path = scripts_dir / script_name
        if not script_path.is_file():
            errors.append(f"本文中に参照されたスクリプトが存在しません: scripts/{script_name}")

    return errors


def validate_body_scripts_in_allowed_tools(body: str, allowed_tools: str) -> List[str]:
    """
    Validates that ${CLAUDE_PLUGIN_ROOT}/scripts/*.sh paths referenced in the Markdown body
    are also included in the allowed-tools Bash(...) pattern.

    Args:
        body: Markdown body (frontmatter excluded)
        allowed_tools: value of the allowed-tools field

    Returns:
        List of error messages
    """
    errors: List[str] = []
    seen: set = set()

    # Extract ${CLAUDE_PLUGIN_ROOT}/scripts/*.sh patterns from body
    for match in SCRIPT_PATH_PATTERN.finditer(body):
        script_name = match.group(1)
        if script_name in seen:
            continue
        seen.add(script_name)

        # Check if the script path is included in allowed-tools
        script_path_pattern = f"${{CLAUDE_PLUGIN_ROOT}}/scripts/{script_name}"
        if script_path_pattern not in allowed_tools:
            errors.append(
                f"本文中に参照されたスクリプト '{script_name}' が allowed-tools の Bash(...) パターンに含まれていません"
            )

    return errors


def validate_body_tools_in_allowed_tools(body: str, allowed_tools: str) -> List[str]:
    """
    Validates that tool names (KNOWN_TOOLS) used in the Markdown body
    are registered in the allowed-tools frontmatter.

    Excludes code fences, inline code, and HTML comments to reduce false positives
    (uses the same exclusion pattern as validate_shell_sensitive_chars).
    AskUserQuestion (FORBIDDEN_ALLOWED_TOOLS) and Task/Agent/Skill (BODY_TOOL_CHECK_SKIP)
    are excluded from matching.

    Args:
        body: Markdown body (frontmatter excluded)
        allowed_tools: value of the allowed-tools field (empty string means field is not set)

    Returns:
        List of error messages
    """
    errors: List[str] = []

    # Remove code fences -> inline code -> HTML comments
    body_stripped = ALL_CODEBLOCK_PATTERN.sub('', body)
    body_stripped = INLINE_CODE_PATTERN.sub('', body_stripped)
    body_stripped = HTML_COMMENT_PATTERN.sub('', body_stripped)

    # Build matching set excluding FORBIDDEN_ALLOWED_TOOLS and BODY_TOOL_CHECK_SKIP
    check_tools = KNOWN_TOOLS - FORBIDDEN_ALLOWED_TOOLS - BODY_TOOL_CHECK_SKIP

    for tool_name in sorted(check_tools):
        pattern = re.compile(r'\b' + re.escape(tool_name) + r'\b')
        if pattern.search(body_stripped):
            # Check for partial match in allowed-tools (handles Bash(...) patterns etc.)
            if tool_name not in allowed_tools:
                errors.append(
                    f"本文中でツール '{tool_name}' が使用されていますが allowed-tools に含まれていません"
                )

    return errors


def validate_modules_scripts_in_allowed_tools(skill_files: List[Path], modules_dir: Path) -> List[str]:
    """
    Validates that scripts referenced by modules/*.md are included in the allowed-tools
    of SKILL.md files that reference those modules.

    Args:
        skill_files: list of SKILL.md files to validate
        modules_dir: path to the modules/ directory

    Returns:
        List of error messages
    """
    errors: List[str] = []

    if not modules_dir.is_dir():
        return errors

    # Collect scripts referenced by each modules/*.md file
    modules_scripts: Dict[str, set] = {}
    for module_file in sorted(modules_dir.glob('*.md')):
        module_name = module_file.name
        try:
            content = module_file.read_text(encoding='utf-8')
        except Exception:
            continue
        scripts = set(SCRIPT_PATH_PATTERN.findall(content))
        if scripts:
            modules_scripts[module_name] = scripts

    if not modules_scripts:
        return errors

    # Check each SKILL.md's module references against allowed-tools
    for skill_file in skill_files:
        try:
            content = skill_file.read_text(encoding='utf-8')
        except Exception:
            continue

        frontmatter, body, parse_error = parse_frontmatter(content)
        if parse_error or frontmatter is None:
            continue

        allowed_tools = frontmatter.get('allowed-tools', '')
        if not isinstance(allowed_tools, str):
            allowed_tools = ''

        # Extract module file names referenced in SKILL.md body
        referenced_modules = set(MODULES_REF_PATTERN.findall(body))

        # Aggregate scripts from referenced modules and check
        for module_name in sorted(referenced_modules):
            scripts = modules_scripts.get(module_name, set())
            for script_name in sorted(scripts):
                script_path = f'${{CLAUDE_PLUGIN_ROOT}}/scripts/{script_name}'
                if script_path not in allowed_tools:
                    skill_rel = f'skills/{skill_file.parent.name}/SKILL.md'
                    errors.append(
                        f"{skill_rel}: script '{script_name}' referenced by modules/{module_name} is not included in allowed-tools"
                    )

    return errors


def find_skill_files(skills_dir: Path) -> List[Path]:
    """
    Finds files matching the skills/*/SKILL.md pattern.
    """
    skill_files: List[Path] = []
    if not skills_dir.is_dir():
        return skill_files

    for skill_dir in skills_dir.iterdir():
        if skill_dir.is_dir():
            skill_file = skill_dir / 'SKILL.md'
            if skill_file.exists():
                skill_files.append(skill_file)

    return sorted(skill_files)


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 validate-skill-syntax.py <path> [<path>...]", file=sys.stderr)
        sys.exit(1)

    input_paths = [Path(p) for p in sys.argv[1:]]

    skill_files_seen: set = set()
    skill_files: List[Path] = []
    modules_dir: Optional[Path] = None

    for path in input_paths:
        if not path.exists():
            print(f"Error: '{path}' does not exist", file=sys.stderr)
            sys.exit(1)

        # Case 1: direct SKILL.md file path (e.g. skills/triage/SKILL.md)
        if path.is_file() and path.name == 'SKILL.md':
            candidates = [path]
            inferred_modules = path.parent.parent.parent / 'modules'
        # Case 2: individual skill directory (e.g. skills/triage)
        elif path.is_dir() and (path / 'SKILL.md').exists():
            candidates = [path / 'SKILL.md']
            inferred_modules = path.parent.parent / 'modules'
        # Case 3: skills/ directory (existing behavior)
        else:
            candidates = find_skill_files(path)
            inferred_modules = path.parent / 'modules'

        for skill_file in candidates:
            resolved = skill_file.resolve()
            if resolved not in skill_files_seen:
                skill_files_seen.add(resolved)
                skill_files.append(skill_file)

        if modules_dir is None:
            modules_dir = inferred_modules

    if not skill_files:
        print("Error: no skill files found at the specified path(s)", file=sys.stderr)
        sys.exit(1)

    if modules_dir is None:
        modules_dir = Path('modules')

    total_errors = 0
    total_warnings = 0

    print(f"Validating: {len(skill_files)} skill(s)\n")

    for skill_file in skill_files:
        try:
            relative_path = skill_file.relative_to(Path.cwd())
        except ValueError:
            relative_path = skill_file
        errors, warnings = validate_skill(skill_file)

        if errors or warnings:
            print(f"📄 {relative_path}")
            for error in errors:
                print(f"  ❌ Error: {error}")
                total_errors += 1
            for warning in warnings:
                print(f"  ⚠️  Warning: {warning}")
                total_warnings += 1
            print()
        else:
            print(f"✅ {relative_path}")

    # Cross-file validation: check module-referenced scripts in allowed-tools
    modules_errors = validate_modules_scripts_in_allowed_tools(skill_files, modules_dir)
    if modules_errors:
        print("\n[Cross-file validation]")
        for error in modules_errors:
            print(f"  ❌ Error: {error}")
            total_errors += 1

    print(f"\nResult: {total_errors} error(s), {total_warnings} warning(s)")

    if total_errors > 0:
        sys.exit(1)
    sys.exit(0)


if __name__ == '__main__':
    main()
