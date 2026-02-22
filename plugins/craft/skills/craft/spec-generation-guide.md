# Spec Generation Guide

When the user provides a natural language description instead of a technical spec,
follow this guide to produce a `TECHNICAL-SPEC.md` before generating the PROMPT.md.

## Process

### 1. Clarify Scope (Brief)

Before writing the spec, confirm your understanding with the user in 2-3 sentences.
Do not ask an extensive questionnaire. Infer reasonable defaults for anything
not specified. Example:

> "I'll design a terminal emulator in Rust with tabs, panes, GPU-accelerated
> rendering, and a theme system. I'll use wgpu for rendering and a config
> file for themes. Sound right, or should I adjust anything?"

If the user says "just go", proceed with your best interpretation.

### 2. Generate the Technical Spec

Write `TECHNICAL-SPEC.md` in the project root with the following structure.
Target 500-1500 lines depending on project complexity.

#### Required Sections

```markdown
# Project Name — Technical Specification

## 1. Overview
- What the project is (1-2 paragraphs)
- Primary use cases
- Target platforms
- Key non-goals (what it explicitly does NOT do)

## 2. Architecture
- High-level component diagram (ASCII or description)
- Data flow between components
- Key technology choices with rationale

## 3. Data Model
- All data structures with exact field names and types
- Serialization formats
- Storage mechanisms
- Relationships between entities

## 4. Feature Specifications
(One subsection per feature, numbered 4.1, 4.2, etc.)

### 4.N Feature Name
- Behavior description
- Input/output formats
- Error cases and messages
- Edge cases
- Configuration options

## 5. External Interfaces
- CLI flags/subcommands (if applicable)
- API endpoints (if applicable)
- File formats
- Network protocols
- OS integrations

## 6. Error Handling
- Error types and hierarchy
- User-facing error messages (exact strings)
- Recovery strategies

## 7. Configuration
- Config file format and location
- All configuration keys with types and defaults
- Environment variable overrides

## 8. Testing Strategy
- Unit test approach
- Integration test scenarios
- Key test cases to verify

## 9. Build and Deployment
- Build commands and targets
- Dependencies and version constraints
- Release profile settings
- Platform-specific considerations

## 10. Implementation Notes
- Recommended crate/library choices
- Performance considerations
- Security considerations
- Known complexity areas
```

#### Quality Standards for Generated Specs

- **Be specific, not vague.** Write exact error messages, exact flag names, exact
  struct field names. An implementing agent should not need to make naming decisions.
- **Resolve ambiguity proactively.** When the description is vague, pick a
  reasonable approach and specify it completely. Document the choice.
- **Use concrete examples.** Show example inputs, outputs, config files, and
  command invocations.
- **Specify negative cases.** What happens when input is invalid? What errors
  are returned? What is explicitly not supported?
- **Size appropriately.** A simple CLI tool might be 400-600 lines. A complex
  application might be 1000-1500 lines. Do not pad with filler, but do not
  leave gaps that force implementing agents to guess.

### 3. Present and Confirm

After writing the spec, present a brief summary:
- Section count and total line estimate
- Major architectural decisions made
- Anything you were uncertain about

Ask the user: "Review `TECHNICAL-SPEC.md` and let me know if anything needs
adjustment, or say 'go' and I'll generate the PROMPT.md."

If the user provides feedback, update the spec. If they approve (or say
nothing specific), proceed to PROMPT.md generation.
