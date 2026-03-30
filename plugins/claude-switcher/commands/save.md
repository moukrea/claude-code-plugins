---
name: save
description: "Save the currently logged-in Claude Code account as a named profile. Use when the user wants to save their current credentials for later switching."
argument-hint: "<profile-name> [--force]"
allowed-tools: Bash
---

# Save Claude Code Account Profile

Save the user's currently logged-in account as a named profile.

If an argument was provided, save directly:
```bash
~/.claude-switcher/cli save $ARGUMENTS
```

If no argument was provided, ask the user for a profile name (e.g., "work" or "personal"), then run the save command.

After saving:
1. Confirm which profile was saved and show the email/org associated with it
2. If this is their first profile, suggest they log in to their other account and save that too:
   - The user should run `! claude auth logout && claude auth login` from the prompt to log in with a different account
   - Then use `/save <name>` to save the second profile
3. If they now have 2+ profiles and auto-switch isn't configured, suggest `/auto-config` to set it up

If the save fails because the profile already exists, suggest using `--force` to overwrite.
