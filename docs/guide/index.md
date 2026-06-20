---
type: project
---

English | [日本語](../ja/guide/index.md)

# 📖 Wholework User Guide

Welcome to the Wholework user guide. Wholework is a governance-and-verification harness for running autonomous coding agents safely on real GitHub repositories — it captures requirements in Issues, gates changes through human review, and verifies outcomes against acceptance criteria after merge. This guide is for anyone who uses Claude Code and GitHub Issues to drive their work: developers, technical writers, researchers, or anyone who wants a structured, auditable way to work with AI agents on a real repository.

## Who this guide is for

Wholework turns the governance-and-verification loop — from Issue creation through post-merge acceptance testing — into a set of composable Skills you can adopt one at a time. This guide assumes:

- You have Claude Code installed and running
- You have a GitHub repository you want to work with
- You are comfortable opening GitHub Issues

No prior Wholework experience required.

## 📚 Guide Pages

| Page | What you will learn |
|------|---------------------|
| [Quick Start](quick-start.md) | Install Wholework and run your first `/auto` in 10–15 minutes |
| [Workflow Overview](workflow.md) | Understand what each skill does and when to use it |
| [Customization](customization.md) | Configure `.wholework.yml`, project domains, and adapters |
| [Troubleshooting](troubleshooting.md) | Fix common issues: auth errors, plugin failures, verify failures |
| [Adapter Authoring Guide](adapter-guide.md) | Write project-specific adapters for MCP servers, CLI tools, and external services |
| [Figma Best Practices](figma-best-practices.md) | Design Figma files for optimal AI code generation accuracy |
| [Scripting Guide](scripting.md) | Shell scripting conventions: jq `// empty` guard, error handling |
| [Autonomy](autonomy.md) | Choose an autonomy tier (L1/L2/L3) governing how far skills may fire follow-on loops and write GitHub state |

## Terminology

Key terms used throughout this guide are defined in [docs/product.md — Terms](../product.md#terms).

## Related Resources

- [README](../../README.md) — project overview and installation
- [docs/workflow.md](../workflow.md) — developer-facing internal workflow phases and label transitions
- [docs/product.md](../product.md) — product vision, non-goals, full terminology reference
