#!/bin/sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
WRAPPER="$REPO_ROOT/misc/AppRun-clientmods"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/luanti-apprun-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

APPDIR="$TMP_ROOT/app"
mkdir -p "$APPDIR"
cat > "$APPDIR/AppRun.luanti" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$TEST_ARGS_FILE"
EOF
chmod +x "$APPDIR/AppRun.luanti"

FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/zenity" <<'EOF'
#!/bin/sh
exit "${ZENITY_STATUS:-1}"
EOF
chmod +x "$FAKE_BIN/zenity"

NO_ZENITY_BIN="$TMP_ROOT/no-zenity-bin"
mkdir -p "$NO_ZENITY_BIN"
for tool in grep sed mkdir; do
	ln -s "$(command -v "$tool")" "$NO_ZENITY_BIN/$tool"
done

fail() {
	printf 'FAIL %s\n' "$1" >&2
	exit 1
}

run_wrapper() {
	run_wrapper_with_args --world "$TMP_ROOT/world"
}

run_wrapper_with_args() {
	APPDIR="$APPDIR" \
	TEST_ARGS_FILE="$TMP_ROOT/args" \
	PATH="$FAKE_BIN:$PATH" \
	"$WRAPPER" "$@"
}

unset LUANTI_USER_PATH MINETEST_USER_PATH
HOME="$TMP_ROOT/home-fresh"
export HOME
run_wrapper
test ! -e "$HOME/.minetest/minetest.conf" ||
	fail "fresh profile does not persistently enable client modding"
grep -Fx 'load_mod_ext_menu = true' "$HOME/.minetest/clientmods/mods.conf" >/dev/null ||
	fail "fresh profile enables ext_menu"
grep -Fx 'load_mod_chest_dupe = true' "$HOME/.minetest/clientmods/mods.conf" >/dev/null ||
	fail "fresh profile enables chest_dupe"
grep -Fx -- '--world' "$TMP_ROOT/args" >/dev/null ||
	fail "original AppRun receives arguments"

HOME="$TMP_ROOT/home-version"
export HOME
mkdir -p "$HOME/.minetest"
printf 'enable_client_modding = false\n' > "$HOME/.minetest/minetest.conf"
ZENITY_STATUS=0
export ZENITY_STATUS
run_wrapper_with_args --version
grep -Fx 'enable_client_modding = false' "$HOME/.minetest/minetest.conf" >/dev/null ||
	fail "--version does not modify client-mod settings"
run_wrapper_with_args --gameid list
grep -Fx 'enable_client_modding = false' "$HOME/.minetest/minetest.conf" >/dev/null ||
	fail "--gameid list does not modify client-mod settings"
run_wrapper_with_args --worldlist name
grep -Fx 'enable_client_modding = false' "$HOME/.minetest/minetest.conf" >/dev/null ||
	fail "--worldlist does not modify client-mod settings"

HOME="$TMP_ROOT/home-no"
export HOME
mkdir -p "$HOME/.minetest"
printf 'enable_client_modding = false\n' > "$HOME/.minetest/minetest.conf"
ZENITY_STATUS=1
export ZENITY_STATUS
run_wrapper
grep -Fx 'enable_client_modding = false' "$HOME/.minetest/minetest.conf" >/dev/null ||
	fail "declining opt-in preserves explicit false"

HOME="$TMP_ROOT/home-no-zenity"
export HOME
mkdir -p "$HOME/.minetest"
printf 'enable_client_modding = false\n' > "$HOME/.minetest/minetest.conf"
APPDIR="$APPDIR" \
TEST_ARGS_FILE="$TMP_ROOT/args" \
PATH="$NO_ZENITY_BIN" \
"$WRAPPER" --world "$TMP_ROOT/world" 2>"$TMP_ROOT/no-zenity.err"
grep -Fx 'enable_client_modding = false' "$HOME/.minetest/minetest.conf" >/dev/null ||
	fail "missing zenity preserves explicit false"
grep -F 'set enable_client_modding = true manually' "$TMP_ROOT/no-zenity.err" >/dev/null ||
	fail "missing zenity explains manual opt-in"

HOME="$TMP_ROOT/home-yes"
export HOME
mkdir -p "$HOME/.minetest"
printf 'enable_client_modding = false\n' > "$HOME/.minetest/minetest.conf"
ZENITY_STATUS=0
export ZENITY_STATUS
run_wrapper
grep -Fx 'enable_client_modding = true' "$HOME/.minetest/minetest.conf" >/dev/null ||
	fail "accepting opt-in enables client modding"

HOME="$TMP_ROOT/home-minetest-path"
MINETEST_USER_PATH="$TMP_ROOT/legacy-profile-minetest"
LUANTI_USER_PATH=
export HOME MINETEST_USER_PATH LUANTI_USER_PATH
mkdir -p "$MINETEST_USER_PATH"
printf 'enable_client_modding = false\n' > "$MINETEST_USER_PATH/minetest.conf"
ZENITY_STATUS=0
export ZENITY_STATUS
run_wrapper
grep -Fx 'enable_client_modding = true' "$MINETEST_USER_PATH/minetest.conf" >/dev/null ||
	fail "MINETEST_USER_PATH profile is selected"
test ! -e "$HOME/.minetest/minetest.conf" ||
	fail "default profile is untouched when MINETEST_USER_PATH is set"

HOME="$TMP_ROOT/home-luanti-path"
MINETEST_USER_PATH="$TMP_ROOT/legacy-profile-luanti"
LUANTI_USER_PATH="$TMP_ROOT/current-profile"
export HOME MINETEST_USER_PATH LUANTI_USER_PATH
mkdir -p "$LUANTI_USER_PATH"
printf 'enable_client_modding = false\n' > "$LUANTI_USER_PATH/minetest.conf"
mkdir -p "$MINETEST_USER_PATH"
printf 'enable_client_modding = false\n' > "$MINETEST_USER_PATH/minetest.conf"
run_wrapper
grep -Fx 'enable_client_modding = true' "$LUANTI_USER_PATH/minetest.conf" >/dev/null ||
	fail "LUANTI_USER_PATH takes precedence"
grep -Fx 'enable_client_modding = false' "$MINETEST_USER_PATH/minetest.conf" >/dev/null ||
	fail "legacy profile is untouched when LUANTI_USER_PATH is set"

HOME="$TMP_ROOT/home-custom-config"
LUANTI_USER_PATH="$TMP_ROOT/custom-config-profile"
CUSTOM_CONFIG="$TMP_ROOT/custom-settings.conf"
printf 'enable_client_modding = false\n' > "$CUSTOM_CONFIG"
ZENITY_STATUS=0
export HOME LUANTI_USER_PATH ZENITY_STATUS
APPDIR="$APPDIR" \
TEST_ARGS_FILE="$TMP_ROOT/args" \
PATH="$FAKE_BIN:$PATH" \
"$WRAPPER" --config "$CUSTOM_CONFIG"
grep -Fx 'enable_client_modding = true' "$CUSTOM_CONFIG" >/dev/null ||
	fail "--config file receives client-mod opt-in"
test ! -e "$LUANTI_USER_PATH/minetest.conf" ||
	fail "default config is untouched when --config is supplied"

HOME="$TMP_ROOT/home-custom-config-equals"
LUANTI_USER_PATH="$TMP_ROOT/custom-config-equals-profile"
CUSTOM_CONFIG="$TMP_ROOT/custom-settings-equals.conf"
printf 'enable_client_modding = false\n' > "$CUSTOM_CONFIG"
export HOME LUANTI_USER_PATH
APPDIR="$APPDIR" \
TEST_ARGS_FILE="$TMP_ROOT/args" \
PATH="$FAKE_BIN:$PATH" \
"$WRAPPER" "--config=$CUSTOM_CONFIG"
grep -Fx 'enable_client_modding = false' "$CUSTOM_CONFIG" >/dev/null ||
	fail "unsupported --config= syntax does not modify settings"
grep -Fx -- "--config=$CUSTOM_CONFIG" "$TMP_ROOT/args" >/dev/null ||
	fail "unsupported --config= syntax is passed through unchanged"

unset LUANTI_USER_PATH MINETEST_USER_PATH
HOME="$TMP_ROOT/home-module-opt-out"
export HOME
mkdir -p "$HOME/.minetest/clientmods"
printf 'load_mod_ext_menu = false\n' > "$HOME/.minetest/clientmods/mods.conf"
run_wrapper
grep -Fx 'load_mod_ext_menu = false' "$HOME/.minetest/clientmods/mods.conf" >/dev/null ||
	fail "explicit client-mod opt-out is preserved"

printf 'ALL PASS\n'
