#!/usr/bin/env bash
# Run in a clean Ubuntu container with only the extracted bundle mounted.
set -euo pipefail
bundle=$(cd "${1:?extracted binary bundle required}" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
prefix="$work/prefix with spaces"
python3 "$bundle/misc/scripts/install-distribution.py" --prefix "$prefix"
export PATH="$prefix/bin:/usr/bin:/bin"
export S_SOURCE_ROOT=/nonexistent-source-root
mkdir "$work/project"
cd "$work/project"
s --version
s --help
cat > main.s <<'S'
package main
func main(int value) int { return value * 3 + 4 }
S
s build main.s -o ./program
status=0; ./program 7 || status=$?
test "$status" -eq 25
status=0; s run main.s -- 7 || status=$?
test "$status" -eq 25
cat > passing_test.s <<'S'
package main
func main() int { return 0 }
S
s test
cat > failing_test.s <<'S'
package main
func main() int { return 9 }
S
if s test; then echo 'nonzero test unexpectedly passed' >&2; exit 1; fi
printf 'previous executable\n' > previous
sha256sum previous > previous.sha256
cat > invalid.s <<'S'
package main
func main() int { return missing_name }
S
if s build invalid.s -o previous; then echo 'invalid source unexpectedly compiled' >&2; exit 1; fi
sha256sum -c previous.sha256
S_TEST_COMPILER="$(dirname -- "$(readlink -f "$prefix/bin/s")")/s_compiler" \
    python3 "$bundle/test/stdlib-native/check.py" -v
python3 "$bundle/misc/scripts/install-distribution.py" --prefix "$prefix" --uninstall
test ! -e "$prefix/bin/s"
test ! -L "$prefix/bin/s"
echo 'Clean installed S build/run/test/failure-preservation/uninstall: PASS'
