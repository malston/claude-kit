#!/usr/bin/env bats
# ABOUTME: Tests for claude-kit, which starts Claude Code with a named config profile.
# ABOUTME: A stand-in claude binary records the args and env it receives.

setup() {
    KIT="$BATS_TEST_DIRNAME/../claude-kit"
    WORK="$(mktemp -d)"
    export HOME="$WORK/home"
    export CLAUDE_KITS_DIR="$WORK/kits"
    mkdir -p "$HOME" "$CLAUDE_KITS_DIR"
    cat >"$CLAUDE_KITS_DIR/kits.conf" <<'CONF'
# kit   config dir       extra claude args
main    ~/.claude

work    ~/.claude-work
auto    ~/.claude-auto   --permission-mode acceptEdits
CONF

    export CLAUDE_BIN="$WORK/fake-claude"
    cat >"$CLAUDE_BIN" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR-<unset>}"
echo "ADDITIONAL_DIRS_CLAUDE_MD=${CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD-<unset>}"
for a in "$@"; do echo "ARG=$a"; done
SH
    chmod +x "$CLAUDE_BIN"

    REPO="$WORK/code/acme-app"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    unset CLAUDE_CONFIG_DIR CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD CLAUDE_KIT_PROJECTS_DIR
}

teardown() {
    rm -rf "$WORK"
}

# --- launching ---

@test "help describes launching and link, and lists the configured kits" {
    run "$KIT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: claude-kit <kit>"* ]]
    [[ "$output" == *"claude-kit link [<kit>...]"* ]]
    [[ "$output" == *"main work auto"* ]]
}

@test "help still works without a kits.conf" {
    rm "$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: claude-kit <kit>"* ]]
}

@test "no arguments prints usage and fails" {
    run "$KIT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage: claude-kit <kit>"* ]]
}

@test "unknown kit fails and names the known kits" {
    run "$KIT" nope
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown kit 'nope' (known: main work auto)"* ]]
}

@test "a missing kits.conf fails and says where it looked" {
    rm "$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" work
    [ "$status" -eq 2 ]
    [[ "$output" == *"no kits defined: $CLAUDE_KITS_DIR/kits.conf not found"* ]]
}

@test "the kits folder defaults to ~/.claude/kits" {
    unset CLAUDE_KITS_DIR
    mkdir -p "$HOME/.claude/kits"
    echo "home ~/.claude-home" >"$HOME/.claude/kits/kits.conf"
    cd "$REPO"
    run "$KIT" home
    [[ "$output" == *"CLAUDE_CONFIG_DIR=$HOME/.claude-home"* ]]
}

@test "a kit sets its config dir, with ~ meaning home" {
    cd "$REPO"
    run "$KIT" work
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLAUDE_CONFIG_DIR=$HOME/.claude-work"* ]]
}

@test "a kit can use an absolute config dir" {
    echo "abs $WORK/elsewhere" >>"$CLAUDE_KITS_DIR/kits.conf"
    cd "$REPO"
    run "$KIT" abs
    [[ "$output" == *"CLAUDE_CONFIG_DIR=$WORK/elsewhere"* ]]
}

@test "a kit whose config dir is ~/.claude leaves CLAUDE_CONFIG_DIR unset even if the caller set it" {
    cd "$REPO"
    CLAUDE_CONFIG_DIR="$HOME/.claude-work" run "$KIT" main
    [[ "$output" == *"CLAUDE_CONFIG_DIR=<unset>"* ]]
}

@test "a kit's extra args come before the caller's" {
    cd "$REPO"
    run "$KIT" auto --resume
    [[ "$output" == *$'ARG=--permission-mode\nARG=acceptEdits\nARG=--resume'* ]]
}

@test "caller args pass through to claude in order" {
    cd "$REPO"
    run "$KIT" work --resume "two words"
    [[ "$output" == *$'ARG=--resume\nARG=two words'* ]]
}

@test "kits.conf rejects a line without a config dir" {
    echo "broken" >>"$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" work
    [ "$status" -eq 2 ]
    [[ "$output" == *"kits.conf line 6: expected '<kit> <config dir> [extra claude args...]'"* ]]
}

@test "kits.conf rejects a kit defined twice" {
    echo "work ~/.claude-other" >>"$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" work
    [ "$status" -eq 2 ]
    [[ "$output" == *"kits.conf line 6: kit 'work' is already defined"* ]]
}

@test "kits.conf rejects a kit named like a subcommand" {
    echo "link ~/.claude-link" >>"$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" work
    [ "$status" -eq 2 ]
    [[ "$output" == *"kits.conf line 6: 'link' is a claude-kit command and can't be a kit name"* ]]
}

@test "kits.conf rejects a relative config dir" {
    echo "rel claude-rel" >>"$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" work
    [ "$status" -eq 2 ]
    [[ "$output" == *"kits.conf line 6: config dir 'claude-rel' must start with / or ~/"* ]]
}

@test "kits.conf rejects a kit name with odd characters" {
    echo "we/rd ~/.claude-weird" >>"$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" work
    [ "$status" -eq 2 ]
    [[ "$output" == *"kits.conf line 6: kit name 'we/rd' may only use letters, digits, - and _"* ]]
}

# --- per-project folders ---

@test "without CLAUDE_KIT_PROJECTS_DIR there is no --add-dir" {
    mkdir -p "$WORK/projects/acme-app/work"
    cd "$REPO"
    run "$KIT" work
    [[ "$output" != *"--add-dir"* ]]
    [[ "$output" == *"ADDITIONAL_DIRS_CLAUDE_MD=<unset>"* ]]
}

@test "with a project folder for the kit it adds the dir and loads its CLAUDE.md" {
    export CLAUDE_KIT_PROJECTS_DIR="$WORK/projects"
    mkdir -p "$WORK/projects/acme-app/work"
    cd "$REPO"
    run "$KIT" work
    [[ "$output" == *$'ARG=--add-dir\nARG='"$WORK/projects/acme-app/work"* ]]
    [[ "$output" == *"ADDITIONAL_DIRS_CLAUDE_MD=1"* ]]
}

@test "a project folder for another kit is ignored" {
    export CLAUDE_KIT_PROJECTS_DIR="$WORK/projects"
    mkdir -p "$WORK/projects/acme-app/auto"
    cd "$REPO"
    run "$KIT" work
    [[ "$output" != *"--add-dir"* ]]
}

@test "the project is found from a subdirectory of the checkout" {
    export CLAUDE_KIT_PROJECTS_DIR="$WORK/projects"
    mkdir -p "$WORK/projects/acme-app/work" "$REPO/src/deep"
    cd "$REPO/src/deep"
    run "$KIT" work
    [[ "$output" == *"ARG=$WORK/projects/acme-app/work"* ]]
}

@test "the project is found from a linked worktree inside the checkout" {
    export CLAUDE_KIT_PROJECTS_DIR="$WORK/projects"
    mkdir -p "$WORK/projects/acme-app/work"
    git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
    git -C "$REPO" worktree add -q --detach "$REPO/worktrees/feature"
    cd "$REPO/worktrees/feature"
    run "$KIT" work
    [[ "$output" == *"ARG=$WORK/projects/acme-app/work"* ]]
}

@test "outside a git repo it launches plainly" {
    export CLAUDE_KIT_PROJECTS_DIR="$WORK/projects"
    mkdir -p "$WORK/not-a-repo"
    cd "$WORK/not-a-repo"
    run "$KIT" work
    [ "$status" -eq 0 ]
    [[ "$output" != *"--add-dir"* ]]
}

# --- link ---

make_kit_files() {
    mkdir -p "$CLAUDE_KITS_DIR/shared/commands" "$CLAUDE_KITS_DIR/work" "$CLAUDE_KITS_DIR/auto/local"
    echo "shared command" >"$CLAUDE_KITS_DIR/shared/commands/handoff.md"
    echo "work rules" >"$CLAUDE_KITS_DIR/work/CLAUDE.md"
    echo '{}' >"$CLAUDE_KITS_DIR/work/settings.json"
    echo "auto rules" >"$CLAUDE_KITS_DIR/auto/CLAUDE.md"
    echo "// hook" >"$CLAUDE_KITS_DIR/auto/local/notify.js"
}

@test "link links the kit's files and the shared files into its config dir" {
    make_kit_files
    run "$KIT" link work
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.claude-work/CLAUDE.md")" = "$CLAUDE_KITS_DIR/work/CLAUDE.md" ]
    [ "$(readlink "$HOME/.claude-work/settings.json")" = "$CLAUDE_KITS_DIR/work/settings.json" ]
    [ "$(readlink "$HOME/.claude-work/commands/handoff.md")" = "$CLAUDE_KITS_DIR/shared/commands/handoff.md" ]
    [[ "$output" == *"linked work into ~/.claude-work"* ]]
    [[ "$output" == *"  linked CLAUDE.md"* ]]
}

@test "link shows an absolute config dir as is" {
    make_kit_files
    echo "abs $WORK/elsewhere" >>"$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" link abs
    [ "$status" -eq 0 ]
    [[ "$output" == *"linked abs into $WORK/elsewhere"* ]]
    [ "$(readlink "$WORK/elsewhere/commands/handoff.md")" = "$CLAUDE_KITS_DIR/shared/commands/handoff.md" ]
}

@test "link creates folders for nested kit files" {
    make_kit_files
    "$KIT" link auto
    [ "$(readlink "$HOME/.claude-auto/local/notify.js")" = "$CLAUDE_KITS_DIR/auto/local/notify.js" ]
}

@test "a kit's own file wins over a shared file at the same path" {
    make_kit_files
    mkdir -p "$CLAUDE_KITS_DIR/work/commands"
    echo "work command" >"$CLAUDE_KITS_DIR/work/commands/handoff.md"
    "$KIT" link work
    [ "$(readlink "$HOME/.claude-work/commands/handoff.md")" = "$CLAUDE_KITS_DIR/work/commands/handoff.md" ]
}

@test "a kit with no folder of its own still gets the shared files" {
    make_kit_files
    rm -r "$CLAUDE_KITS_DIR/auto"
    "$KIT" link auto
    [ "$(readlink "$HOME/.claude-auto/commands/handoff.md")" = "$CLAUDE_KITS_DIR/shared/commands/handoff.md" ]
}

@test "link with no kits links every kit except one using ~/.claude" {
    make_kit_files
    run "$KIT" link
    [ "$status" -eq 0 ]
    [ -L "$HOME/.claude-work/commands/handoff.md" ]
    [ -L "$HOME/.claude-auto/commands/handoff.md" ]
    [ ! -e "$HOME/.claude" ]
}

@test "link twice changes nothing the second time" {
    make_kit_files
    "$KIT" link work
    run "$KIT" link work
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.claude-work/CLAUDE.md")" = "$CLAUDE_KITS_DIR/work/CLAUDE.md" ]
}

@test "link refuses, changing nothing, when a real file sits where a link goes" {
    make_kit_files
    mkdir -p "$HOME/.claude-work"
    echo "hand edited" >"$HOME/.claude-work/settings.json"
    run "$KIT" link work
    [ "$status" -eq 2 ]
    [[ "$output" == *"~/.claude-work/settings.json already exists"* ]]
    [ "$(cat "$HOME/.claude-work/settings.json")" = "hand edited" ]
    [ ! -e "$HOME/.claude-work/CLAUDE.md" ]
}

@test "link refuses, changing nothing, when a link points somewhere else" {
    make_kit_files
    mkdir -p "$HOME/.claude-work"
    ln -s /tmp/elsewhere "$HOME/.claude-work/CLAUDE.md"
    run "$KIT" link work
    [ "$status" -eq 2 ]
    [[ "$output" == *"~/.claude-work/CLAUDE.md already exists"* ]]
    [ "$(readlink "$HOME/.claude-work/CLAUDE.md")" = /tmp/elsewhere ]
    [ ! -e "$HOME/.claude-work/settings.json" ]
    [ ! -e "$HOME/.claude-work/commands" ]
}

@test "link refuses, changing nothing, when a link's parent is not a directory" {
    make_kit_files
    mkdir -p "$HOME/.claude-work"
    echo "not a dir" >"$HOME/.claude-work/commands"
    run "$KIT" link work
    [ "$status" -eq 2 ]
    [[ "$output" == *"~/.claude-work/commands is not a directory"* ]]
    [ ! -e "$HOME/.claude-work/CLAUDE.md" ]
}

@test "link refuses a kit that uses ~/.claude" {
    make_kit_files
    run "$KIT" link main
    [ "$status" -eq 2 ]
    [[ "$output" == *"main uses ~/.claude, Claude Code's default config dir; link does not manage it"* ]]
}

@test "link with an unknown kit fails" {
    make_kit_files
    run "$KIT" link nope
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown kit 'nope'"* ]]
}

@test "link skips .DS_Store files" {
    make_kit_files
    echo junk >"$CLAUDE_KITS_DIR/work/.DS_Store"
    echo junk >"$CLAUDE_KITS_DIR/shared/commands/.DS_Store"
    "$KIT" link work
    [ ! -e "$HOME/.claude-work/.DS_Store" ] && [ ! -L "$HOME/.claude-work/.DS_Store" ]
    [ ! -e "$HOME/.claude-work/commands/.DS_Store" ] && [ ! -L "$HOME/.claude-work/commands/.DS_Store" ]
}

@test "link handles a tab in a file name" {
    make_kit_files
    echo note >"$CLAUDE_KITS_DIR/work/a"$'\t'"b.md"
    run "$KIT" link work
    [ "$status" -eq 0 ]
    [ "$(readlink "$HOME/.claude-work/a"$'\t'"b.md")" = "$CLAUDE_KITS_DIR/work/a"$'\t'"b.md" ]
}

@test "link does not link kits.conf itself" {
    make_kit_files
    "$KIT" link work
    [ ! -e "$HOME/.claude-work/kits.conf" ] && [ ! -L "$HOME/.claude-work/kits.conf" ]
}

# --- kits ---

@test "kits prints each kit's name, config dir and extra args, tab-separated" {
    run "$KIT" kits
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "main"$'\t'"$HOME/.claude"$'\t' ]
    [ "${lines[1]}" = "work"$'\t'"$HOME/.claude-work"$'\t' ]
    [ "${lines[2]}" = "auto"$'\t'"$HOME/.claude-auto"$'\t'"--permission-mode acceptEdits" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "kits fails like launching does when kits.conf is broken" {
    echo "broken" >>"$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" kits
    [ "$status" -eq 2 ]
    [[ "$output" == *"kits.conf line 6:"* ]]
}

@test "kits.conf rejects a kit named kits" {
    echo "kits ~/.claude-kits" >>"$CLAUDE_KITS_DIR/kits.conf"
    run "$KIT" work
    [ "$status" -eq 2 ]
    [[ "$output" == *"kits.conf line 6: 'kits' is a claude-kit command and can't be a kit name"* ]]
}

@test "help describes kits" {
    run "$KIT" --help
    [[ "$output" == *"claude-kit kits"* ]]
}
