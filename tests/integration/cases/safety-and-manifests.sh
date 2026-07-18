# shellcheck shell=bash
# shellcheck disable=SC2015,SC2154  # sourced integration cases share the orchestrator fixture
# --- safety: degenerate dir DEST rejected -----------------------------------
mkdir -p "$FAKE/modules/evil/files"; printf 'x\n' > "$FAKE/modules/evil/files/f"
printf 'keep\n' > "$H/precious.txt"
# shellcheck disable=SC2016
for d in '$HOME/.' '$HOME//' '$HOME/x/..' '$HOME'; do
    cat > "$FAKE/modules/evil/module.conf" <<EOF
NAME="evil"
DESC="Safety fixture"
ICON="!"
ORDER="999"
SOURCE="files"
DEST="${d}"
EOF
    rc_is "unsafe dir DEST rejected: ${d}" 1 df all
done
rm -rf "$FAKE/modules/evil"
check "\$HOME contents intact after evil manifest" test -f "$H/precious.txt"

# Source type is inferred from the filesystem; a directory is mirrored without
# any manifest type field.
mkdir -p "$FAKE/modules/evil/files"
printf 'x\n' > "$FAKE/modules/evil/files/config"
cat > "$FAKE/modules/evil/module.conf" <<EOF
NAME="evil"
DESC="Inferred directory fixture"
ICON="!"
ORDER="999"
SOURCE="files"
DEST="$H/.config/evil"
EOF
df evil >/dev/null 2>&1
check "directory SOURCE is inferred and mirrored" cmp -s \
    "$FAKE/modules/evil/files/config" "$H/.config/evil/config"
rm -rf "$H/.config/evil"

# Resolvers are named extensions for file sources only.
cat > "$FAKE/modules/evil/module.conf" <<EOF
NAME="evil"
DESC="Unknown resolver fixture"
ICON="!"
ORDER="999"
SOURCE="files/config"
DEST="$H/.config/evil/config"
RESOLVER="missing-resolver"
EOF
rc_is "unknown resolver is rejected" 1 df evil
cat > "$FAKE/modules/evil/module.conf" <<EOF
NAME="evil"
DESC="Directory resolver fixture"
ICON="!"
ORDER="999"
SOURCE="files"
DEST="$H/.config/evil"
RESOLVER="json-merge"
EOF
rc_is "resolver rejects a directory SOURCE" 1 df evil
cat > "$FAKE/modules/evil/module.conf" <<EOF
NAME="evil"
DESC="Valid companion fixture"
ICON="!"
ORDER="999"
SOURCE="files/config"
DEST="$H/.config/evil/config"
EOF

# A resolver that cannot render blocks the entire foreground batch before an
# earlier valid module can mutate its destination.
mkdir -p "$FAKE/modules/invalid-resolver/files"
printf '{invalid json\n' > "$FAKE/modules/invalid-resolver/files/config.json"
cat > "$FAKE/modules/invalid-resolver/module.conf" <<EOF
NAME="invalid-resolver"
DESC="Resolver preflight fixture"
ICON="!"
ORDER="998"
SOURCE="files/config.json"
DEST="$H/.config/invalid-resolver/config.json"
RESOLVER="json-merge"
REQUIRES="jq"
EOF
mkdir -p "$H/.config/multipkg"
printf 'preflight-keep\n' > "$H/.config/multipkg/config"
invalid_plan="$(df --config-only --json plan invalid-resolver)"
printf '%s' "$invalid_plan" | jq -e \
    ".modules[0].blockers | index(\"cannot resolve config with 'json-merge'\")" >/dev/null \
    && pass "plan reports a resolver blocker" \
    || fail "plan missed a resolver blocker (got '$invalid_plan')"
rc_is "resolver failure blocks the full foreground batch" 1 \
    df --config-only multipkg invalid-resolver
check "resolver preflight prevents earlier config mutation" \
    grep -qxF preflight-keep "$H/.config/multipkg/config"
rm -rf "$FAKE/modules/invalid-resolver"

cat > "$FAKE/modules/evil/module.conf" <<EOF
NAME="evil"
DESC="Incomplete config fixture"
ICON="!"
ORDER="999"
SOURCE="files/config"
EOF
rc_is "SOURCE without DEST is rejected" 1 df evil
rm -rf "$FAKE/modules/evil"

# A file deployment never copies into an existing directory by accident.
mkdir -p "$FAKE/modules/evil/files" "$H/.config/existing-dir"
printf 'x\n' > "$FAKE/modules/evil/files/config"
printf 'keep\n' > "$H/.config/existing-dir/keep"
cat > "$FAKE/modules/evil/module.conf" <<EOF
NAME="evil"
DESC="Destination type fixture"
ICON="!"
ORDER="999"
SOURCE="files/config"
DEST="$H/.config/existing-dir"
EOF
rc_is "file deployment rejects a directory destination" 1 df evil
check "directory destination remains intact" test -f "$H/.config/existing-dir/keep"
rm -rf "$FAKE/modules/evil"

# Modules may not own the same destination or nest under another module.
for module in overlap-a overlap-b; do
    mkdir -p "$FAKE/modules/$module/files"
    printf 'x\n' > "$FAKE/modules/$module/files/config"
done
cat > "$FAKE/modules/overlap-a/module.conf" <<EOF
NAME="overlap-a"
DESC="Overlap fixture A"
ICON="!"
ORDER="997"
SOURCE="files/config"
DEST="$H/.config/shared"
EOF
cat > "$FAKE/modules/overlap-b/module.conf" <<EOF
NAME="overlap-b"
DESC="Overlap fixture B"
ICON="!"
ORDER="998"
SOURCE="files/config"
DEST="$H/.config/shared/child"
EOF
rc_is "overlapping module destinations are rejected" 1 df all
rm -rf "$FAKE/modules/overlap-a" "$FAKE/modules/overlap-b"

# Existing parent symlinks must not redirect a deployment outside HOME.
mkdir -p "$SB/outside" "$FAKE/modules/evil/files"
ln -s "$SB/outside" "$H/.unsafe"
printf 'escape\n' > "$FAKE/modules/evil/files/config"
cat > "$FAKE/modules/evil/module.conf" <<EOF
NAME="evil"
DESC="Safety fixture"
ICON="!"
ORDER="999"
SOURCE="files/config"
DEST="$H/.unsafe/config"
EOF
rc_is "symlink parent destination rejected" 1 df evil
checknot "symlink escape wrote nothing outside HOME" test -e "$SB/outside/config"
rm -rf "$FAKE/modules/evil"

# SOURCE may not escape its module through an intermediate symlink.
mkdir -p "$FAKE/modules/evil" "$SB/source-outside"
printf 'outside\n' > "$SB/source-outside/config"
ln -s "$SB/source-outside" "$FAKE/modules/evil/files"
cat > "$FAKE/modules/evil/module.conf" <<EOF
NAME="evil"
DESC="Source symlink fixture"
ICON="!"
ORDER="999"
SOURCE="files/config"
DEST="$H/.config/source-escape"
EOF
rc_is "symlink parent SOURCE is rejected" 1 df evil
checknot "source symlink copied nothing" test -e "$H/.config/source-escape"
rm -rf "$FAKE/modules/evil"

# Manifests and profiles must be real project files, not links to external
# data that happen to parse as valid declarations.
mkdir -p "$SB/external-module"
cat > "$SB/external-module/module.conf" <<'EOF'
NAME="linked-module"
DESC="External module fixture"
ICON="!"
BREW="linked-module"
EOF
ln -s "$SB/external-module" "$FAKE/modules/linked-module"
rc_is "symlinked module directory is rejected" 1 df all
rm -f "$FAKE/modules/linked-module"
mkdir -p "$FAKE/modules/linked-manifest"
cat > "$SB/external-manifest.conf" <<'EOF'
NAME="linked-manifest"
DESC="External manifest fixture"
ICON="!"
BREW="linked-manifest"
EOF
ln -s "$SB/external-manifest.conf" "$FAKE/modules/linked-manifest/module.conf"
rc_is "symlinked module manifest is rejected" 1 df all
rm -rf "$FAKE/modules/linked-manifest"
printf 'extends=""\nmodules="multipkg"\n' > "$SB/external-profile.conf"
ln -s "$SB/external-profile.conf" "$FAKE/profiles/linked-profile.conf"
rc_is "symlinked profile is rejected" 1 df profile linked-profile
rm -f "$FAKE/profiles/linked-profile.conf"

# Required presentation metadata fails fast instead of producing broken rows.
mkdir -p "$FAKE/modules/evil"
cat > "$FAKE/modules/evil/module.conf" <<'EOF'
NAME="evil"
DESC="Missing icon fixture"
ORDER="999"
EOF
rc_is "module without an icon is rejected" 1 df all
rm -rf "$FAKE/modules/evil"

# Every accepted module must own an installation or config action.
mkdir -p "$FAKE/modules/empty-module"
cat > "$FAKE/modules/empty-module/module.conf" <<'EOF'
NAME="empty-module"
DESC="No-op fixture"
ICON="!"
ORDER="999"
EOF
rc_is "module without package or config is rejected" 1 df all
rm -rf "$FAKE/modules/empty-module"

# module.conf is parsed as data: unknown/duplicate fields and shell
# substitutions are rejected without executing project code.
mkdir -p "$FAKE/modules/strict-manifest/files"
printf 'strict\n' > "$FAKE/modules/strict-manifest/files/config"
cat > "$FAKE/modules/strict-manifest/module.conf" <<EOF
NAME="strict-manifest"
DESC="Strict manifest fixture"
ICON="!"
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
UNKNOWN="nope"
EOF
rc_is "strict manifest rejects unknown fields" 1 df all
cat > "$FAKE/modules/strict-manifest/module.conf" <<EOF
NAME="strict-manifest"
NAME="strict-manifest"
DESC="Strict manifest fixture"
ICON="!"
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
EOF
rc_is "strict manifest rejects duplicate fields" 1 df all
cat > "$FAKE/modules/strict-manifest/module.conf" <<EOF
NAME="strict-manifest"
DESC="broken"quote"
ICON="!"
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
EOF
rc_is "strict manifest rejects unescaped inner quotes" 1 df all
marker="$SB/manifest-executed"
cat > "$FAKE/modules/strict-manifest/module.conf" <<EOF
NAME="strict-manifest"
DESC="\$(touch $marker)"
ICON="!"
SOURCE="files/config"
DEST="\$HOME/.config/strict-manifest"
EOF
rc_is "strict manifest rejects command substitution" 1 df all
checknot "strict manifest executes no project code" test -e "$marker"
cat > "$FAKE/modules/strict-manifest/module.conf" <<'EOF'
NAME="strict-manifest"
DESC="Strict manifest fixture"
ICON="!"
SOURCE="files/config"
DEST="$HOME/.config/strict-manifest"
EOF
df --config-only strict-manifest >/dev/null 2>&1
check "strict manifest expands HOME without eval" grep -qxF strict "$H/.config/strict-manifest"
rm -rf "$FAKE/modules/strict-manifest"

# A runtime install failure must reach automation as a non-zero command status.
mkdir -p "$FAKE/modules/broken"
cat > "$FAKE/modules/broken/module.conf" <<'EOF'
NAME="broken"
DESC="Failure propagation fixture"
ICON="!"
ORDER="999"
BREW="broken"
EOF
printf 'broken\n' > "$BREW_FAIL_FILE"
rc_is "foreground install failure exits non-zero" 1 df broken
rm -f "$BREW_FAIL_FILE"; rm -rf "$FAKE/modules/broken"

# Package-manager success is not enough when CHECK still says the tool is
# absent; automation must receive a failure instead of a false installed state.
mkdir -p "$FAKE/modules/unverified"
cat > "$FAKE/modules/unverified/module.conf" <<'EOF'
NAME="unverified"
DESC="Post-install verification fixture"
ICON="!"
ORDER="999"
BREW="unverified"
CHECK="definitely-not-created-by-the-fixture"
EOF
rc_is "post-install state is verified" 1 df unverified
rm -rf "$FAKE/modules/unverified" "$BREW_PREFIX/opt/unverified" "$BREW_PREFIX/bin/unverified"

# Re-loading in the same process replaces, rather than duplicates, the model.
reload_counts="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" DOTLAD_PLAIN=1 /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/ui.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/resolvers.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/manifest.sh"
    manifest_load; first="$T_COUNT"; manifest_load
    printf "%s %s" "$first" "$T_COUNT"')"
module_count="$(find "$FAKE/modules" -mindepth 2 -maxdepth 2 -name module.conf | wc -l | tr -d ' ')"
[[ "$reload_counts" == "$module_count $module_count" ]] \
    && pass "manifest reload is idempotent" || fail "manifest reload duplicated entries: $reload_counts"

# Profiles resolve inheritance without duplicates and only contain modules.
profile_out="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/ui.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/resolvers.sh"
    . "$DOTLAD_RUNTIME_ROOT/lib/manifest.sh"; manifest_load; profile_modules complete')"
[[ "$(printf '%s\n' "$profile_out" | sort -u | wc -l | tr -d ' ')" == "$module_count" ]] \
    && pass "complete profile resolves every module once" \
    || fail "complete profile resolution"
profile_marker="$SB/profile-executed"
cat > "$FAKE/profiles/strict-profile.conf" <<EOF
extends=""
modules="\$(touch $profile_marker)"
EOF
rc_is "strict profile rejects command substitution" 1 df profile strict-profile
checknot "strict profile executes no project code" test -e "$profile_marker"
rm -f "$FAKE/profiles/strict-profile.conf"
printf 'extends="cycle-b"\nmodules=""\n' > "$FAKE/profiles/cycle-a.conf"
printf 'extends="cycle-a"\nmodules=""\n' > "$FAKE/profiles/cycle-b.conf"
rc_is "profile inheritance cycle is rejected" 1 df profile cycle-a
rm -f "$FAKE/profiles/cycle-a.conf" "$FAKE/profiles/cycle-b.conf"
