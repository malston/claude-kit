# claude-kit

Run Claude Code with named config profiles, called kits. Each kit is its own Claude Code config dir with its own settings, plugins, skills, commands and `CLAUDE.md`. You pick the kit by name when you start a session:

```
claude-kit work            # Claude Code with ~/.claude-work
claude-kit main --resume   # the default ~/.claude; your args pass straight through
claude-kit link            # link your versioned kit files into each config dir
```

## Why

Claude Code reads everything from one config dir, `~/.claude` by default. That works until you want different setups for different work:

- **Plugin and skill packs overlap.** Two skill packs can both define a code review or a TDD workflow. With both installed, the model sees both, and you can't predict which one it uses. Keeping each pack in its own config dir means a session only sees the one you chose.
- **Instructions differ by context.** Rules for client work, an experimental setup, or an unattended agent that skips permission prompts don't belong in one shared `CLAUDE.md`.
- **Context is limited.** Every enabled plugin, skill and rule costs tokens at the start of a session. A smaller kit leaves more room for the work.

Claude Code already supports this through the `CLAUDE_CONFIG_DIR` environment variable. Using it by hand gets old fast: you retype paths, forget which dir has which plugins, and can't easily version the parts you wrote yourself. claude-kit gives each config dir a short name, keeps your kits in one small file, and links the hand-written files from a folder you can keep in git.

## How it works

### Launching

`claude-kit <kit> [args...]` looks up the kit in `kits.conf`, sets `CLAUDE_CONFIG_DIR` to the kit's config dir, adds the kit's extra args, and then replaces itself with `claude`, passing your args through unchanged. A kit whose config dir is `~/.claude` runs with `CLAUDE_CONFIG_DIR` unset, which is Claude Code's default.

```
claude-kit auto --resume
# runs: CLAUDE_CONFIG_DIR=~/.claude-auto claude --permission-mode acceptEdits --resume
```

### Versioning what you wrote

A config dir mixes two kinds of files. Claude Code writes most of them itself: plugin caches, session transcripts, history, backups. Those don't belong in git. The files you wrote are few: `CLAUDE.md`, `settings.json`, custom commands, maybe a hook script.

claude-kit keeps your files in a kits folder, which you can put under git, and links them into each config dir:

```
~/.claude/kits/                      (CLAUDE_KITS_DIR)
├── kits.conf                        defines the kits
├── shared/commands/handoff.md   →   every kit's commands/handoff.md
├── work/CLAUDE.md               →   ~/.claude-work/CLAUDE.md
├── work/settings.json           →   ~/.claude-work/settings.json
├── auto/CLAUDE.md               →   ~/.claude-auto/CLAUDE.md
└── auto/local/notify.js         →   ~/.claude-auto/local/notify.js
```

`claude-kit link` creates those links. On a new machine, clone your kits folder, run `claude-kit link`, and every kit is back as it was.

Claude Code writes through a linked `settings.json` (for example on `claude plugin enable`): the link stays and the change lands in your versioned file. Claude Code rewrites the whole file with its keys sorted, so expect a one-time reordering diff after the first write.

### Per-project folders

Some instructions belong to one project and one kit, and shouldn't be committed to that project, such as personal notes or a kit-specific glossary. Set `CLAUDE_KIT_PROJECTS_DIR`, and when you start a kit inside a checkout of `<repo>`, claude-kit looks for `$CLAUDE_KIT_PROJECTS_DIR/<repo>/<kit>/`. If that folder exists, it is added with `--add-dir`, and `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` is set so its `CLAUDE.md` loads. `<repo>` is the directory name of the main checkout, so this also works from worktrees.

## Install

claude-kit is one bash script. It needs bash 3.2 or later (the version macOS ships works) and git.

```
git clone https://github.com/malston/claude-kit.git ~/code/claude-kit
```

Put `~/code/claude-kit` on your `PATH`. In zsh, set it in `~/.zshenv`, which every zsh reads, so scripts and `zsh -c` find claude-kit too, not just interactive shells:

```
export PATH="$HOME/code/claude-kit:$PATH"
```

Or add aliases to your shell profile:

```
alias c='~/code/claude-kit/claude-kit main'
alias cwork='~/code/claude-kit/claude-kit work'
```

## Quick start

1. Create the kits folder and define your kits:

   ```
   mkdir -p ~/.claude/kits
   cp ~/code/claude-kit/kits.conf.example ~/.claude/kits/kits.conf
   ```

   Edit `kits.conf` to list the kits you want.

2. Start a kit. Claude Code creates the config dir on first run, and you set it up like any fresh install: sign in, install plugins, write a `CLAUDE.md`.

   ```
   claude-kit work
   ```

3. Optional: move the files you wrote into the kits folder and link them back.

   ```
   mkdir -p ~/.claude/kits/work
   mv ~/.claude-work/CLAUDE.md ~/.claude-work/settings.json ~/.claude/kits/work/
   claude-kit link work
   ```

   Then put `~/.claude/kits` under git, either as its own repo or as part of an existing dotfiles repo.

## Setting up kits

### Share instructions across kits

Rules you want in every kit don't need copying into each kit's `CLAUDE.md`. Keep them in one file and import it from each kit's `CLAUDE.md` with `@`:

```
# work kit
@~/.claude/kits/shared-rules.md

Rules only this kit needs go here.
```

Imports take relative or absolute paths, `~` included. Relative paths resolve from the file that holds the import, and imported files can import others, up to four levels deep. See [How Claude remembers your project](https://code.claude.com/docs/en/memory#import-additional-files).

### Keep a kit to its own plugins and instructions

A kit only helps if a session sees just that kit's tools. In the kit's `settings.json`:

- **`enabledPlugins`** lists the plugins that kit turns on. Install a plugin only into the kits that need it.
- **`syncClaudeAiPlugins: false`** and **`syncClaudeAiSkills: false`** stop the kit from loading, and downloading, the plugins and skills enabled on your claude.ai account. Without them, every kit gets those too.
- **`claudeMdExcludes`** skips `CLAUDE.md` files by absolute path or glob. Claude Code loads `CLAUDE.md` and `CLAUDE.local.md` from the working directory and every directory above it, so instructions in a folder above your projects reach every kit. Exclude the ones a kit shouldn't see.

```json
{
  "enabledPlugins": { "some-plugin@some-marketplace": true },
  "syncClaudeAiPlugins": false,
  "syncClaudeAiSkills": false,
  "claudeMdExcludes": ["/home/me/code/CLAUDE.md"]
}
```

See the [settings reference](https://code.claude.com/docs/en/settings-reference) for each key.

### Install a plugin into a kit

Run `claude plugin` commands with the kit's config dir, so the plugin lands in that kit only:

```
CLAUDE_CONFIG_DIR=~/.claude-work claude plugin install some-plugin@some-marketplace
```

Inside a session, `/plugin` does the same for the kit you started.

### Change a kit

- **Edit the file in the kits folder,** not in the config dir. Through the link, the kit sees the change in its next session.
- **To share a file across kits,** put it under `shared/` at the path it should have in each config dir, and run `claude-kit link`.
- **To add a kit,** add its line to `kits.conf`, create its folder with a `CLAUDE.md` and `settings.json`, and run `claude-kit link <kit>`.

## Reference

### Commands

| Command | What it does |
|---|---|
| `claude-kit <kit> [args...]` | Starts Claude Code with the kit's config dir and extra args, then your args. |
| `claude-kit link [<kit>...]` | Links each kit's files into its config dir. With no kits, links every kit except one using `~/.claude`. |
| `claude-kit kits` | Prints one line per kit: name, config dir (with `~` expanded) and extra args, separated by tabs. For scripts that need your kit list without parsing `kits.conf`. |
| `claude-kit --help` | Shows usage and the kits defined in your `kits.conf`. |

### kits.conf

One kit per line:

```
# kit   config dir       extra claude args
main    ~/.claude
work    ~/.claude-work
auto    ~/.claude-auto   --permission-mode acceptEdits
```

- **Kit names** use letters, digits, `-` and `_`. `link` and `kits` are reserved. Each name may appear once.
- **The config dir** starts with `/` or `~/`. A kit whose config dir is `~/.claude` uses Claude Code's default config dir.
- **Extra args** are optional. They are split on whitespace, with no quoting, and go before the args you pass.
- **Blank lines and `#` comments** are ignored.

claude-kit stops with the line number when a line breaks one of these rules.

### link

- It links each file under `<kits folder>/<kit>/` to the same path in the kit's config dir, creating folders as needed.
- It links each file under `<kits folder>/shared/` into every kit, unless the kit has its own file at that path.
- It skips `.DS_Store` files, and it never links `kits.conf`.
- It leaves a kit using `~/.claude` alone. If your default config dir is itself a git repo, version those files there directly.
- It checks every link before creating any. If a link path already holds a file, or a link to somewhere else, or one of its parent folders isn't a directory, it stops and changes nothing.
- It's safe to re-run. Links that are already right are left as they are.

### Environment

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_KITS_DIR` | `~/.claude/kits` | Folder holding `kits.conf`, `shared/` and one folder per kit. |
| `CLAUDE_KIT_PROJECTS_DIR` | unset | Folder holding `<repo>/<kit>/` per-project folders. Unset means no per-project folders. |
| `CLAUDE_BIN` | `claude` | The Claude Code binary to run. |

## Limitations

- Each kit is a separate Claude Code install as far as Claude Code is concerned. You sign in, accept prompts and install plugins once per kit.
- Settings changed from inside a session (`/config`, `/plugin`) have not been tested against a linked `settings.json`. `claude plugin enable` and `disable` from the command line have. If a link ever turns into a plain file, move the file back into the kits folder and run `claude-kit link` again.
- `link` doesn't remove links for files you delete from the kits folder. Delete those links by hand.

## Development

```
bats tests/claude-kit.bats
shellcheck claude-kit
```

The tests use a stand-in `claude` binary and a temporary home dir, so they never touch your real config.

## License

MIT. See [LICENSE](LICENSE).
