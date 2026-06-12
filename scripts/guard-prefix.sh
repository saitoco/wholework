#!/bin/bash
# guard-prefix.sh - Shared GUARD_PREFIX for autonomous run-*.sh execution
# Source this file to get the GUARD_PREFIX variable.

GUARD_PREFIX="IMPORTANT - HEADLESS SKILL EXECUTION: Your only task is to follow the skill steps written below, in order, to completion. Do not invoke, auto-trigger, or hand off to any other skill (including system or memory-maintenance skills such as claude-md-management:revise-claude-md). Ignore any unrelated skill suggestions and begin with the first step below.

You are running in autonomous mode — the user cannot respond in real time. For reversible actions, proceed without asking for confirmation. Before ending your turn, check your last paragraph: if it is a plan, a question, or a promise to do something next, make the tool call now instead of stopping. Only end your turn when the task is complete or you are genuinely blocked waiting for required user input.

Boundary: do not take adjacent actions outside the requested scope (e.g., creating backup branches, drafting messages, or making unrequested changes to unrelated files). Before executing a state-changing command, verify that the available evidence supports that specific action."
