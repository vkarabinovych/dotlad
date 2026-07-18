# shellcheck shell=bash
# shellcheck disable=SC2015,SC2154  # sourced integration cases share the orchestrator fixture
# --- update one tool --------------------------------------------------------
df filecopy >/dev/null 2>&1
check "filecopy config deployed"        cmp -s "$FAKE/modules/filecopy/files/config.toml" "$H/.config/filecopy/config.toml"
check "declared requirement installed before deploy" command -v "$SB/brewprefix/bin/reqtool"
[[ "$(state_json filecopy)" == "ready 1" ]] && pass "after update: filecopy = ready, installed" || fail "after update: filecopy (got '$(state_json filecopy)')"

# --- update detection -------------------------------------------------------
printf 'repo = 2\n' > "$FAKE/modules/filecopy/files/config.toml"
[[ "$(state_json filecopy)" == "update 1" ]] && pass "repo edit → update available" || fail "repo edit → update (got '$(state_json filecopy)')"
df filecopy >/dev/null 2>&1
[[ "$(state_json filecopy)" == "ready 1" ]] && pass "re-update → ready" || fail "re-update → ready"

# --- backup before overwrite ------------------------------------------------
rm -rf "$H/.dotlad_backup"
printf 'repo = 3\n' > "$FAKE/modules/filecopy/files/config.toml"
df filecopy >/dev/null 2>&1
if find "$H/.dotlad_backup" -type f 2>/dev/null | grep -q .; then
    bk="$(find "$H/.dotlad_backup" -path '*filecopy*' -type f | head -1)"
    grep -q '^repo = 2$' "$bk" && pass "backup holds the pre-update file" || fail "backup content"
else
    fail "backup created before overwrite"
fi

# --- git merge keeps machine-local keys -------------------------------------
printf '[user]\n\tname = Local\n\temail = me@local\n[credential]\n\thelper = osxkeychain\n' > "$H/.gitconfig"
df git >/dev/null 2>&1
check "git: repo key wins"            sh -c "test \"\$(git config --file '$H/.gitconfig' user.name)\" = Repo"
check "git: automatic colour enabled" sh -c "test \"\$(git config --file '$H/.gitconfig' color.ui)\" = auto"
check "git: local-only key survives"  sh -c "test \"\$(git config --file '$H/.gitconfig' user.email)\" = me@local"
check "git: local credential survives" sh -c "test \"\$(git config --file '$H/.gitconfig' credential.helper)\" = osxkeychain"
[[ "$(state_json git)" == "ready 1" ]] && pass "git: ready after merge (local noise ignored)" || fail "git ready (got '$(state_json git)')"

# --- json merge keeps local keys --------------------------------------------
mkdir -p "$H/.config/jsonmerge"
printf '{"model":"old","localOnly":"x"}\n' > "$H/.config/jsonmerge/settings.json"
df jsonmerge >/dev/null 2>&1
check "jsonmerge: repo key wins"           jq -e '.model == "opus"' "$H/.config/jsonmerge/settings.json"
check "jsonmerge: local-only key survives" jq -e '.localOnly == "x"' "$H/.config/jsonmerge/settings.json"
printf '{"model":null}\n' > "$FAKE/modules/jsonmerge/files/settings.json"
df jsonmerge >/dev/null 2>&1
check "jsonmerge: explicit repo null wins" jq -e '.model == null' "$H/.config/jsonmerge/settings.json"
check "jsonmerge: local key survives a null overlay" jq -e '.localOnly == "x"' "$H/.config/jsonmerge/settings.json"

# --- dir mirror + prune of stale --------------------------------------------
df directory >/dev/null 2>&1
check "directory files deployed" cmp -s "$FAKE/modules/directory/files/lua/mod.lua" "$H/.config/directory/lua/mod.lua"
printf -- '-- changed\n' > "$FAKE/modules/directory/files/lua/mod.lua"
printf -- '-- stale\n' > "$H/.config/directory/stale.lua"
[[ "$(state_json directory)" == "update 1" ]] && pass "stale live file → update available" || fail "stale → update (got '$(state_json directory)')"
directory_counts="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" DOTLAD_PLAIN=1 /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/runtime.sh"; manifest_load
    i="$(manifest_find directory)"; dir_change_counts "$i"')"
[[ "$directory_counts" == "1 file to sync · 1 file to remove" ]] \
    && pass "directory update counts describe sync and removal" \
    || fail "directory update counts are ambiguous (got '$directory_counts')"
df directory >/dev/null 2>&1
checknot "stale file pruned" test -e "$H/.config/directory/stale.lua"
check "pruned file backed up" sh -c "find '$H/.dotlad_backup' -path '*directory/stale.lua' -type f | grep -q ."

# Empty directories are part of an exact directory mirror: they are created,
# retained, and distinguished from stale destination-only directories.
mkdir -p "$FAKE/modules/empty-tree/files/kept-empty"
cat > "$FAKE/modules/empty-tree/module.conf" <<EOF
NAME="empty-tree"
DESC="Empty directory mirror fixture"
ICON="!"
ORDER="997"
SOURCE="files"
DEST="$H/.config/empty-tree"
EOF
df --config-only empty-tree >/dev/null 2>&1
check "empty directory destination is created" test -d "$H/.config/empty-tree"
check "source empty directory is mirrored" test -d "$H/.config/empty-tree/kept-empty"
[[ "$(state_json empty-tree)" == "ready 0" ]] && pass "empty directory mirror reaches ready" \
    || fail "empty directory mirror remains pending"
mkdir -p "$H/.config/empty-tree/stale-empty"
[[ "$(state_json empty-tree)" == "update 0" ]] && pass "stale empty directory is detected" \
    || fail "stale empty directory was ignored"
df --config-only empty-tree >/dev/null 2>&1
checknot "stale empty directory is pruned" test -e "$H/.config/empty-tree/stale-empty"
check "declared empty directory survives prune" test -d "$H/.config/empty-tree/kept-empty"
rm -rf "$FAKE/modules/empty-tree" "$H/.config/empty-tree"

# A destination leaf may conflict with a source directory. The shared change
# model must back up that leaf and let the transactional mirror replace it.
mkdir -p "$FAKE/modules/tree-conflict/files/branch" "$H/.config/tree-conflict"
printf 'managed\n' > "$FAKE/modules/tree-conflict/files/branch/config"
printf 'local leaf\n' > "$H/.config/tree-conflict/branch"
cat > "$FAKE/modules/tree-conflict/module.conf" <<EOF
NAME="tree-conflict"
DESC="Directory conflict fixture"
ICON="!"
ORDER="997"
SOURCE="files"
DEST="$H/.config/tree-conflict"
EOF
df --config-only tree-conflict >/dev/null 2>&1
check "directory mirror replaces a conflicting leaf" test -d "$H/.config/tree-conflict/branch"
check "directory mirror deploys below the replaced leaf" \
    grep -qxF managed "$H/.config/tree-conflict/branch/config"
check "directory mirror backs up a conflicting leaf" sh -c \
    "find '$H/.dotlad_backup' -path '*/.config/tree-conflict/branch' -type f | grep -q ."
rm -rf "$FAKE/modules/tree-conflict" "$H/.config/tree-conflict"

transaction_probe="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" DOTLAD_PLAIN=1 /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/ui.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/manifest.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/backup.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/engine.sh"
    dest="$HOME/.transaction-dest"; mkdir -p "$dest"
    printf "old\n" > "$dest/config"
    stage="$(mktemp -d "$HOME/.transaction-stage.XXXXXX")"
    rc=0; replace_directory_transaction "$stage" "$stage/missing" "$dest" >/dev/null 2>&1 || rc=$?
    content="$(tr -d "\n" < "$dest/config")"
    [[ -e "$stage" ]] && left=yes || left=no
    printf "%s|%s|%s" "$rc" "$content" "$left"')"
[[ "$transaction_probe" == "1|old|no" ]] \
    && pass "directory transaction rolls back a failed swap" \
    || fail "directory transaction rollback (got '$transaction_probe')"

# A leaf symlink is replaced safely, preserved as a symlink, and restorable.
mkdir -p "$FAKE/modules/linked/files" "$H/.config/linked" "$SB/outside"
printf 'managed\n' > "$FAKE/modules/linked/files/config"
printf 'local\n' > "$SB/outside/linked.conf"
ln -s "$SB/outside/linked.conf" "$H/.config/linked/config"
cat > "$FAKE/modules/linked/module.conf" <<EOF
NAME="linked"
DESC="Symlink backup fixture"
ICON="!"
ORDER="998"
SOURCE="files/config"
DEST="$H/.config/linked/config"
EOF
df linked >/dev/null 2>&1
checknot "leaf symlink replaced by a real config" test -L "$H/.config/linked/config"
linked_backup="$(find "$H/.dotlad_backup" -path '*/.config/linked/config' -type l | head -1)"
check "replaced symlink preserved in backup" test -L "$linked_backup"
backup_rel="${linked_backup#"$H/.dotlad_backup"/}"; backup_name="${backup_rel%%/*}"
backup_list="$(df backups)"
printf '%s\n' "$backup_list" | grep -qF "$backup_name" \
    && pass "backup CLI lists restore points" || fail "backup CLI list"
rc_is "backup CLI rejects an invalid restore name" 1 df --yes restore ../outside
rc_is "backup CLI rejects an invalid delete name" 1 df --yes backup delete ../outside
df --yes restore "$backup_name" >/dev/null 2>&1
check "backup restore recreates the symlink" test -L "$H/.config/linked/config"
[[ "$(readlink "$H/.config/linked/config")" == "$SB/outside/linked.conf" ]] \
    && pass "restored symlink keeps its target" || fail "restored symlink target"
rm -rf "$FAKE/modules/linked"

# A backup path below HOME may not traverse a symlinked parent.
mkdir -p "$SB/outside-backups"
ln -s "$SB/outside-backups" "$H/.backup-link"
mkdir -p "$H/.config/multipkg"
printf 'backup-root-keep\n' > "$H/.config/multipkg/config"
rc_is "backup root with a symlinked parent is rejected" 1 \
    df --backup-root "$H/.backup-link/store" --config-only multipkg
check "unsafe backup root prevents config mutation" grep -qxF backup-root-keep "$H/.config/multipkg/config"
checknot "unsafe backup root writes nothing outside HOME" test -e "$SB/outside-backups/store"
rm -f "$H/.backup-link" "$H/.config/multipkg/config"

# Snapshot allocation is collision-safe, and a run preserves only the first
# version of any path even when it is touched more than once.
backup_probe="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" DOTLAD_PLAIN=1 /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/ui.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/manifest.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/backup.sh"
    BACKUP_ROOT="$HOME/probe-backups"; BACKUP_DIR=""; N_BACKED=0
    first="$(new_backup_dir)"; second="$(new_backup_dir)"
    target="$HOME/probe.conf"; printf "first\n" > "$target"
    BACKUP_ROOT="$HOME/version-backups"; backup_path "$target"
    printf "second\n" > "$target"; backup_path "$target"
    preserved="$(tr -d "\n" < "$BACKUP_DIR/probe.conf")"
    printf "%s %s %s %s" "${first##*/}" "${second##*/}" "$preserved" "$N_BACKED"')"
read -r probe_first probe_second probe_content probe_count <<< "$backup_probe"
[[ "$probe_first" != "$probe_second" ]] && pass "backup directory names are collision-safe" \
    || fail "backup directory collision: $backup_probe"
[[ "$probe_content $probe_count" == "first 1" ]] && pass "a snapshot preserves the first version only" \
    || fail "snapshot version preservation: $backup_probe"

# A restore point is successful only when every entry was restored.
partial_backup="20000101_000000"
mkdir -p "$H/.dotlad_backup/$partial_backup/.restore-ok" \
    "$H/.dotlad_backup/$partial_backup/.restore-unsafe" "$SB/restore-outside"
printf 'safe\n' > "$H/.dotlad_backup/$partial_backup/.restore-ok/config"
printf 'unsafe\n' > "$H/.dotlad_backup/$partial_backup/.restore-unsafe/config"
ln -s "$SB/restore-outside" "$H/.restore-unsafe"
rc_is "partial backup restore exits non-zero" 1 restore "$partial_backup"
check "partial backup restores safe entries" grep -qxF safe "$H/.restore-ok/config"
checknot "partial backup never follows an unsafe parent" test -e "$SB/restore-outside/config"
restore_toast="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" DOTLAD_PLAIN=1 /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/ui.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/manifest.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/backup.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/tui.sh"
    BACKUP_ROOT="$HOME/.dotlad_backup"; BACKUP_DIR=""; N_BACKED=0
    tui_confirm() { return 0; }
    tui_restore "'$partial_backup'"
    printf "%s" "$TOAST"')"
[[ "$restore_toast" == "✗ restored 1 · 1 failed" ]] \
    && pass "TUI reports partial restore counts" \
    || fail "TUI partial restore toast (got '$restore_toast')"
rm -f "$H/.restore-unsafe"
df --yes backup delete "$partial_backup" >/dev/null 2>&1
checknot "backup CLI deletes a restore point" test -e "$H/.dotlad_backup/$partial_backup"

# --- package install --------------------------------------------------------
df package >/dev/null 2>&1
[[ "$(state_json package)" == "pkg 1" ]] && pass "package installed after update" || fail "package installed (got '$(state_json package)')"

# Package activity wraps without dropping names when the terminal is narrow.
narrow_pkgs="multipkg alpha beta gamma delta vendor/tap/epsilon zeta eta"
narrow_out="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/ui.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/pick.sh"
    ACTIVITY_WIDTH=40
    wrapped_activity "" "↓" install "'"$narrow_pkgs"'"')"
if printf '%s\n' "$narrow_out" | lines_fit 40; then
    pass "narrow install activity stays within its width"
else
    fail "narrow install activity exceeded its width"
fi
missing_pkg=""
for pkg in $narrow_pkgs; do
    printf '%s\n' "$narrow_out" | grep -qF "$pkg" || missing_pkg="$pkg"
done
[[ -z "$missing_pkg" ]] && pass "narrow install activity keeps every package name" \
    || fail "narrow install activity lost package: $missing_pkg"
result_counts="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" DOTLAD_PLAIN=1 /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/runtime.sh"; manifest_load
    ACTIVITY_WIDTH=120
    DOTLAD_RUNDIR="$HOME/result-counts"; mkdir -p "$DOTLAD_RUNDIR"
    printf "8 0 8\n" > "$DOTLAD_RUNDIR/directory.result"
    i="$(manifest_find directory)"; tool_activity "$i" ""')"
if printf '%s\n' "$result_counts" | grep -qF '8 files synced · 8 files backed up' \
    && ! printf '%s\n' "$result_counts" | grep -qF '+8/-0'; then
    pass "completed update counts name synced files"
else
    fail "completed update counts are ambiguous: $result_counts"
fi
narrow_cfg="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/ui.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/pick.sh"
    ACTIVITY_WIDTH=48
    wrapped_activity "" "↑" update "modules/sample/files/config.toml → ~/Library/Application Support/sample/config.toml"')"
if printf '%s\n' "$narrow_cfg" | lines_fit 48 \
    && printf '%s\n' "$narrow_cfg" | grep -qF 'modules/sample/files/config.toml' \
    && printf '%s\n' "$narrow_cfg" | grep -qF 'Support/sample/config.toml'; then
    pass "narrow config activity wraps both source and destination"
else
    fail "narrow config activity lost or overflowed a path"
fi
narrow_tree="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/runtime.sh"; manifest_load
    ACTIVITY_WIDTH=40; i="$(manifest_find multipkg)"; tool_block "$i" ""')"
if printf '%s\n' "$narrow_tree" | grep -q '^  ├ .* install' \
    && printf '%s\n' "$narrow_tree" | grep -q '^  │   ' \
    && printf '%s\n' "$narrow_tree" | grep -q '^  └ + create' \
    && printf '%s\n' "$narrow_tree" | grep -qF '.config/multipkg/config'; then
    pass "wrapped tree uses vertical continuation only before later actions"
else
    fail "wrapped tree connector layout"
fi

# --- 'all' + idempotency ----------------------------------------------------
df all >/dev/null 2>&1
brew_before="$(wc -l < "$BREW_LOG" | tr -d ' ')"
out="$(df all 2>&1)"
brew_after="$(wc -l < "$BREW_LOG" | tr -d ' ')"
if printf '%s' "$out" | grep -q 'already up to date' && [[ "$brew_before" == "$brew_after" ]]; then
    pass "second 'all' is a no-op"
else
    fail "second 'all' repeated work"
fi
profile_run="$(df profile base 2>&1)" && pass "profile command runs inherited module set" \
    || fail "profile command runs inherited module set: $profile_run"
