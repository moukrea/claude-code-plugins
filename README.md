# moukrea-plugins

Productivity and security plugins for [Claude Code](https://claude.ai/code).

## Plugins

| Plugin | Description |
|--------|-------------|
| [opaq](plugins/opaq/) | Secure credential access — use secrets in commands without ever exposing them |
| [git-pilot](plugins/git-pilot/) | Automated git workflow — branch creation, commit formatting, push and MR prompts |
| [craft](plugins/craft/) | Generate multi-phase implementation prompts from technical specs |
| [harness](plugins/harness/) | Agent orchestration harness — task classification, verification gates, session bridging |

## Installation

### Remote (recommended)

Add the marketplace source (one-time):

```
/plugin marketplace add moukrea/claude-code-plugins
```

Install plugins:

```
/plugin install opaq@moukrea-plugins
/plugin install git-pilot@moukrea-plugins
/plugin install craft@moukrea-plugins
/plugin install harness@moukrea-plugins
```

### From a local clone

```bash
git clone https://github.com/moukrea/claude-code-plugins.git
```

Add the local directory as a marketplace source:

```
/plugin marketplace add ./claude-code-plugins
```

Then install plugins using the same commands as above.

## License

[MIT](LICENSE)
