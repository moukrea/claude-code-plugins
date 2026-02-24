# craft — Autonomous Implementation Prompts

Generates orchestration prompts that coordinate agent teams to implement entire projects from a technical specification.

## What it does

- Analyzes a technical spec and breaks it into self-contained module documents
- Designs a bottom-up build order and task dependency graph
- Generates a `PROMPT.md` that orchestrates multi-phase agent teams

## Usage

```
/craft @TECHNICAL-SPEC.md
```

Or describe what you want to build:

```
/craft A CLI tool that converts markdown files to PDF with custom themes
```

craft will generate a spec first, then produce the orchestration prompt.

## Installation

```
/plugin install craft@moukrea-plugins
```
