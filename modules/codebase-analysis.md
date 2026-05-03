# codebase-analysis

Cross-codebase analysis module.

## Purpose

Analyze the codebase across files to extract entry points, directory structure, dependencies, test specifications, and documentation information. Callers: `/doc sync --deep`, `/audit`

## Input

The following information is passed from the caller (or obtained from the caller's context):

- **Codebase directory path**: Root directory to analyze (defaults to current directory if omitted)

## Processing Steps

Execute the following 5 analyses in order:

### Step 1: Entry Point Analysis

Search for `main.*`, `index.*`, `app.*`, `server.*` using Glob with `path` set to the codebase directory, and Read up to 5 found files to infer the architecture.

**Output**: Entry point file list and inferred architecture (monolithic / microservices / library, etc.)

### Step 2: Directory Structure Semantic Analysis

Get the top-level directory list with `ls` and Read 1 representative file from each directory to infer its role.

**Output**: Table of directory names and inferred roles (e.g., `src/` → application code, `tests/` → test suite)

### Step 3: Dependency Graph Extraction

Search for `import`/`require`/`from` patterns limited to source directories (existing ones: `src/`, `lib/`, `app/`, etc.) using Grep with `path` set to each source directory (max 30 results), and extract dependencies between major modules.

**Output**: Module dependency list ("A depends on B" format)

### Step 4: Test File Analysis

Search under `test/`, `spec/`, `__tests__/` using Glob with each directory as `path` argument (max 10 results), and extract behavioral specifications by Grepping for describe/it/test statements.

**Output**: List of tested features and behavioral specifications

### Step 5: Comment/Docstring Extraction

Search for `/**`, `"""`, `///` patterns limited to files near entry points using Grep with `path` set to the entry point directory (max 20 results), and extract function/class-level documentation.

**Output**: Documentation list for major functions and classes

## Output

Integrate results from each step and return to the caller:

- **Entry point list**: File paths and inferred architecture
- **Directory role table**: Mapping of directory names to roles
- **Dependency graph**: Dependencies between major modules
- **Test specifications**: Tested features and behavioral specs
- **Docstring information**: Documentation for major functions and classes

The caller uses these analysis results to reflect findings into respective documents (`tech.md`, `structure.md`, `product.md`, etc.).
