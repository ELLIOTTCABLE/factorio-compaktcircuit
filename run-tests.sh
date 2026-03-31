#!/bin/sh
set -eu

# Headless test-runner for compaktcircuit using factorio-test.
# Runs from WSL; launches Windows factorio.exe via --benchmark.
# Requires: fmtk (npm i -g factoriomod-debug), wslpath, cmd.exe

cd "$(dirname "$0")"
MOD_DIR="$(pwd)"
MOD_NAME="$(sed -n 's/.*"name" *: *"\([^"]*\)".*/\1/p' info.json | head -1)"

MODS_DIR="$(cd ..; pwd)"
DATA_DIR="$MOD_DIR/factorio-test-data-dir"
TEST_MODS="$DATA_DIR/mods"
SAVE="$MODS_DIR/FactorioTest/cli/headless-save.zip"

FACTORIO="${FACTORIO:-}"
if [ -z "$FACTORIO" ]; then
   for p in \
      "/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" \
      "/mnt/c/Program Files/Factorio/bin/x64/factorio.exe" \
   ; do
      if [ -f "$p" ]; then FACTORIO="$p"; break; fi
   done
fi
if [ -z "$FACTORIO" ]; then
   echo "Cannot find factorio.exe. Set FACTORIO=/path/to/factorio.exe" >&2
   exit 1
fi

win() { wslpath -w "$1"; }

# --- Parse required (non-optional) dependencies from info.json ---
copy_deps() {
   sed -n '/"dependencies"/,/]/p' info.json |
      grep -v '"dependencies"' |
      sed -n 's/.*"\([^"]*\)".*/\1/p' |
      grep -v '^[?!(~]' |
      while read -r dep; do
         name="${dep%% *}"
         case "$name" in base|quality|elevated-rails|space-age|"") continue ;; esac
         match="$(find "$MODS_DIR" -maxdepth 1 \( -name "${name}_*.zip" -o -name "${name}" -type d \) | head -1)"
         if [ -z "$match" ]; then
            echo "  warning: dependency '$name' not found in $MODS_DIR" >&2
            continue
         fi
         case "$match" in
            *.zip) cp "$match" "$TEST_MODS/" ;;
            *)     cmd.exe /C "mklink /J $(win "$TEST_MODS/$name") $(win "$match")" >/dev/null 2>&1 ;;
         esac
      done
}

# --- Bootstrap: create isolated data dir (idempotent) ---
bootstrap() {
   if [ -f "$TEST_MODS/mod-settings.dat" ]; then return 0; fi

   echo "Bootstrapping test data directory ..."
   mkdir -p "$TEST_MODS"

   # Junction for mod-under-test (Windows junctions work; WSL symlinks don't)
   if [ ! -e "$TEST_MODS/$MOD_NAME" ]; then
      cmd.exe /C "mklink /J $(win "$TEST_MODS/$MOD_NAME") $(win "$MOD_DIR")" >/dev/null 2>&1
   fi

   # factorio-test mod
   ft_zip="$(find "$MODS_DIR" -maxdepth 1 -name 'factorio-test_*.zip' | head -1)"
   if [ -z "$ft_zip" ]; then
      echo "factorio-test zip not found in $MODS_DIR" >&2; exit 1
   fi
   cp "$ft_zip" "$TEST_MODS/"

   copy_deps

   fmtk mods adjust --modsPath "$TEST_MODS" --disableExtra \
      "${MOD_NAME}=true" factorio-test=true base=true

   cat > "$DATA_DIR/config.ini" <<-EOF
	[path]
	read-data=__PATH__executable__/../../data
	write-data=$(win "$DATA_DIR")
	EOF

   # Generate mod-settings.dat (factorio --create writes it as a side-effect)
   dummy="$DATA_DIR/____dummy.zip"
   "$FACTORIO" --create "$(win "$dummy")" \
      --mod-directory "$(win "$TEST_MODS")" \
      -c "$(win "$DATA_DIR/config.ini")" >/dev/null 2>&1
   rm -f "$dummy"

   echo "Bootstrap complete."
}

# --- Run tests ---
run() {
   autostart='{"mod":"'"$MOD_NAME"'","headless":true}'
   fmtk settings set startup factorio-test-auto-start-config "$autostart" \
      --modsPath "$TEST_MODS"

   output="$DATA_DIR/test-output.log"

   "$FACTORIO" --benchmark "$(win "$SAVE")" \
      --benchmark-ticks 1000000000 \
      --mod-directory "$(win "$TEST_MODS")" \
      -c "$(win "$DATA_DIR/config.ini")" \
      2>&1 | tee "$output"

   # Reset auto-start so a stale data-dir doesn't surprise anyone
   fmtk settings set startup factorio-test-auto-start-config '{}' \
      --modsPath "$TEST_MODS" 2>/dev/null || true

   if grep -q 'FACTORIO-TEST-RESULT:passed' "$output"; then
      echo ""
      echo "=== TESTS PASSED ==="
      return 0
   elif grep -q 'FACTORIO-TEST-RESULT:' "$output"; then
      result="$(grep 'FACTORIO-TEST-RESULT:' "$output" | head -1)"
      echo ""
      echo "=== TESTS FAILED: ${result#*RESULT:} ==="
      return 1
   else
      echo ""
      echo "=== NO TEST RESULT FOUND ==="
      echo "Check $DATA_DIR/factorio-current.log for errors"
      return 2
   fi
}

bootstrap
run
