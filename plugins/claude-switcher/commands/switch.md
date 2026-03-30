---
name: switch
description: "Switch to a different Claude Code account profile. Use when the user wants to change which Claude subscription they're using (e.g., switching between work and personal accounts)."
argument-hint: "[profile-name | prev]"
allowed-tools: Bash
---

# Switch Claude Code Account Profile

The user wants to switch their Claude Code account. Run the switcher command:

```bash
$CLAUDE_PLUGIN_ROOT/scripts/claude-switcher.sh use $ARGUMENTS
```

After switching:
1. Report the result to the user (which profile is now active, the email and subscription type)
2. Note that the switch takes effect for NEW Claude Code sessions -- the current session may still use the previous account's tokens until restarted
3. If the user ran `/switch prev` or `/switch -`, explain they switched back to their previous profile

If no argument was provided, show the available profiles:
```bash
$CLAUDE_PLUGIN_ROOT/scripts/claude-switcher.sh list
```

Then ask the user which profile they want to switch to.
