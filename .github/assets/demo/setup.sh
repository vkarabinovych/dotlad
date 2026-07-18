#!/usr/bin/env bash
# Prepare a deterministic project and HOME for the README demo.
set -euo pipefail

DEMO_ROOT="${DOTLAD_DEMO_ROOT:-/tmp/dotlad-readme-demo}"
case "$DEMO_ROOT" in
    /tmp/dotlad-readme-demo*) ;;
    *) printf 'Refusing unsafe demo root: %s\n' "$DEMO_ROOT" >&2; exit 1 ;;
esac
rm -rf "$DEMO_ROOT"
mkdir -p "$DEMO_ROOT/home/.config/shell" "$DEMO_ROOT/project/tools" \
    "$DEMO_ROOT/project/profiles" "$DEMO_ROOT/bin" "$DEMO_ROOT/brew/bin" \
    "$DEMO_ROOT/brew/opt"

cat > "$DEMO_ROOT/bin/hostname" <<'EOF'
#!/bin/sh
printf 'demo\n'
EOF
cat > "$DEMO_ROOT/brew/bin/brew" <<'EOF'
#!/bin/sh
exit 0
EOF
for command_name in starship jq; do
    cat > "$DEMO_ROOT/bin/$command_name" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$DEMO_ROOT/bin/$command_name"
done
chmod +x "$DEMO_ROOT/bin/hostname" "$DEMO_ROOT/brew/bin/brew"
mkdir -p "$DEMO_ROOT/brew/opt/starship" "$DEMO_ROOT/brew/opt/zoxide" \
    "$DEMO_ROOT/brew/opt/jq" "$DEMO_ROOT/brew/opt/yq" \
    "$DEMO_ROOT/brew/opt/git" "$DEMO_ROOT/brew/opt/git-delta"

make_tool() {
    mkdir -p "$DEMO_ROOT/project/tools/$1/files"
}

make_tool shell
printf 'theme = "dracula"\n' > "$DEMO_ROOT/project/tools/shell/files/config.toml"
printf 'theme = "plain"\n' > "$DEMO_ROOT/home/.config/shell/config.toml"
cat > "$DEMO_ROOT/project/tools/shell/tool.conf" <<'EOF'
NAME="shell"
DESC="Prompt and navigation tools with a shared shell configuration."
ICON=""
ORDER="10"
BREW="starship zoxide"
CHECK="starship"
SOURCE="files/config.toml"
DEST="$HOME/.config/shell/config.toml"
EOF

make_tool git
printf '[color]\n\tui = auto\n' > "$DEMO_ROOT/project/tools/git/files/.gitconfig"
cp "$DEMO_ROOT/project/tools/git/files/.gitconfig" "$DEMO_ROOT/home/.gitconfig"
cat > "$DEMO_ROOT/project/tools/git/tool.conf" <<'EOF'
NAME="git"
DESC="Git defaults with readable diffs and machine-local values preserved."
ICON="󰊢"
ORDER="20"
BREW="git git-delta"
CHECK="git"
SOURCE="files/.gitconfig"
DEST="$HOME/.gitconfig"
EOF

make_tool editor
printf 'return { theme = "dracula" }\n' > "$DEMO_ROOT/project/tools/editor/files/init.lua"
cat > "$DEMO_ROOT/project/tools/editor/tool.conf" <<'EOF'
NAME="editor"
DESC="Editor configuration and syntax tooling."
ICON=""
ORDER="30"
BREW="neovim tree-sitter-cli"
CHECK="nvim"
SOURCE="files/init.lua"
DEST="$HOME/.config/editor/init.lua"
EOF

make_tool terminal
printf 'font-family = FiraCode Nerd Font\n' > "$DEMO_ROOT/project/tools/terminal/files/config"
cat > "$DEMO_ROOT/project/tools/terminal/tool.conf" <<'EOF'
NAME="terminal"
DESC="Terminal application and portable visual defaults."
ICON="󰆍"
ORDER="40"
BREW="ghostty font-fira-code-nerd-font"
CASK="1"
CHECK="$HOME/Applications/Ghostty.app"
SOURCE="files/config"
DEST="$HOME/.config/terminal/config"
EOF

mkdir -p "$DEMO_ROOT/project/tools/data"
cat > "$DEMO_ROOT/project/tools/data/tool.conf" <<'EOF'
NAME="data"
DESC="Command-line JSON and YAML processing."
ICON="󰆼"
ORDER="50"
BREW="jq yq"
CHECK="jq"
EOF

cat > "$DEMO_ROOT/project/profiles/core.conf" <<'EOF'
extends=""
tools="shell git data"
EOF
cat > "$DEMO_ROOT/project/profiles/full.conf" <<'EOF'
extends="core"
tools="editor terminal"
EOF
