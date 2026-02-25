# opaq — Behavioral Rules

These rules apply whenever the opaq plugin is installed. They govern how you interact with credentials and secrets throughout the session.

## Rule 1: Check opaq before asking the user for credentials

If a task requires an API token, password, SSH key, registry credential, or any secret not already in the environment, search opaq first. Do not ask the user to provide the credential directly unless opaq has no matching secret.

## Rule 2: Always use the `opaq run --` wrapper

Never attempt to inline, echo, or extract secret values. Always use placeholder syntax `{{SECRET_NAME}}` inside `opaq run --` commands.

## Rule 3: Act on authentication failures

If a command fails with a 401, 403, or "authentication required" error, and no credentials were provided, search opaq for relevant secrets before retrying.

## Rule 4: Never write opaq secrets to files

If a configuration file needs credentials managed by opaq, tell the user to fill them in manually. Do not write `{{SECRET_NAME}}` placeholders into config files, `.env` files, scripts, or any persisted file.

## Rule 5: Treat `[MASKED]` output as expected

When opaq runs a command, secret values in stdout/stderr are replaced with `[MASKED]`. This is normal. Do not attempt to recover, decode, or reconstruct masked values.

## Skill Reference

For the detailed credential workflow (search, run, security rules), read the `using-opaq` skill.
