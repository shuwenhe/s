#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$project_root" <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOL = Path(sys.argv.pop(1)) / "script/canonical_closure.py"


class ClosureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="s-closure-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def source(self, path, text):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text, encoding="utf-8")

    def run_closure(self, entry="src/main.s", output="out"):
        out = self.root / output
        result = subprocess.run(
            [sys.executable, str(TOOL), "--root", str(self.root),
             "--entry", entry, "--out-dir", str(out)],
            text=True, capture_output=True,
        )
        self.assertIn(result.returncode, (0, 2), result.stdout + result.stderr)
        return result.returncode, json.loads((out / "canonical-closure.json").read_text())

    def test_package_import_includes_all_package_files(self):
        self.source("src/main.s", 'package entry\nimport ("compile.internal.pipeline")\n')
        self.source("src/pipeline/one.s", 'package compile.internal.pipeline\n')
        self.source("src/pipeline/two.s", 'package compile.internal.pipeline\n')
        rc, report = self.run_closure()
        self.assertEqual(rc, 0)
        self.assertEqual([f["path"] for f in report["files"]],
                         ["src/main.s", "src/pipeline/one.s", "src/pipeline/two.s"])

    def test_import_spellings_and_multiline_comments_preserve_statement_boundaries(self):
        self.source("src/main.s", 'package entry /* a comment\nends here */ import compile.internal.pipeline\n'
                    'import (other "pkg.other"; "pkg.third")\n')
        self.source("src/pipeline.s", 'package compile.internal.pipeline\n')
        self.source("src/other.s", 'package pkg.other\n')
        self.source("src/third.s", 'package pkg.third\n')
        rc, report = self.run_closure()
        self.assertEqual(rc, 0)
        self.assertEqual([f["path"] for f in report["files"]],
                         ["src/main.s", "src/other.s", "src/pipeline.s", "src/third.s"])

    def test_symbols_resolve_by_package_and_declaration_not_filename(self):
        self.source("src/main.s", "package entry\n"
                    "use compile.internal.core.build as backend_build\n"
                    "use compile.internal.compiler.main as compiler_main\n")
        self.source("src/core/backend.s", "package compile.internal.core\n"
                    "func build() int { return 0 }\n")
        self.source("src/compiler/compiler.s", "package compile.internal.compiler\n"
                    "func main() int { return 0 }\n")
        self.source("src/compiler/main.s", "package compile.compiler\n"
                    "func compiler_main() int { return 0 }\n")
        rc, report = self.run_closure()
        self.assertEqual(rc, 0)
        files = {f["path"] for f in report["files"]}
        self.assertIn("src/compiler/compiler.s", files)
        self.assertNotIn("src/compiler/main.s", files)
        core = next(e for e in report["edges"]["src/main.s"] if e.get("symbol") == "build")
        self.assertEqual((core["dependency"], core["declaration_line"], core["line"]),
                         ("src/core/backend.s", 2, 2))
        self.assertEqual(core["package"], "compile.internal.core")
        self.assertEqual(core["alias"], "backend_build")

    def test_missing_package_keeps_both_source_locations(self):
        self.source("src/main.s", 'package entry\nimport "providers"\n')
        self.source("src/providers/a.s", 'package providers\nimport "compile.internal.syntax"\n')
        self.source("src/providers/b.s", 'package providers\nimport "compile.internal.syntax"\n')
        self.source("src/parent.s", 'package compile.internal\nfunc syntax() int { return 0 }\n')
        self.source("src/parser/syntax/syntax.s", 'package compile.internal.parser.syntax\n')
        rc, report = self.run_closure()
        self.assertEqual(rc, 2)
        unresolved = report["unresolved_imports"]
        self.assertEqual([(u["source"], u["line"], u["reason"]) for u in unresolved],
                         [("src/providers/a.s", 2, "missing_package"),
                          ("src/providers/b.s", 2, "missing_package")])
        self.assertTrue(all(u["package"] == "compile.internal.syntax" and
                            u["symbol"] is None for u in unresolved))

    def test_missing_symbol_fails_even_if_named_file_exists(self):
        self.source("src/main.s", "package entry\nuse pkg.missing as call\n")
        self.source("src/pkg/missing.s", "package pkg\nfunc other() int { return 0 }\n")
        rc, report = self.run_closure()
        self.assertEqual(rc, 2)
        failure = report["unresolved_imports"][0]
        self.assertEqual((failure["reason"], failure["package"], failure["symbol"]),
                         ("missing_symbol", "pkg", "missing"))

    def test_use_assign_enum_comments_and_strings_are_not_dependencies(self):
        self.source("src/main.s", '''package entry
enum operation {
    use
    assign
}
// use absent.comment
/* import "absent.block" */
func main() int {
    assign := 1
    text := `
import "absent.string"
use absent.string
`
    return assign
}
''')
        rc, report = self.run_closure()
        self.assertEqual(rc, 0)
        self.assertEqual(report["unresolved_imports"], [])
        self.assertEqual(report["edges"].get("src/main.s", []), [])

    def test_method_is_not_a_package_function(self):
        self.source("src/main.s", "package entry\nuse pkg.build\n")
        self.source("src/pkg/method.s", "package pkg\n"
                    "func (thing* self) build() int { return 0 }\n")
        rc, report = self.run_closure()
        self.assertEqual(rc, 2)
        self.assertEqual(report["unresolved_imports"][0]["reason"], "missing_symbol")

    def test_function_text_in_string_is_not_a_symbol_provider(self):
        self.source("src/main.s", "package entry\nuse pkg.build\n")
        self.source("src/pkg/quoted.s", 'package pkg\nconst text = `\nfunc build() int { return 0 }\n`\n')
        rc, report = self.run_closure()
        self.assertEqual(rc, 2)
        self.assertEqual(report["unresolved_imports"][0]["reason"], "missing_symbol")

    def test_duplicate_symbol_fails_with_candidate_locations(self):
        self.source("src/main.s", "package entry\nuse pkg.build\n")
        for name in ("a", "b"):
            self.source(f"src/pkg/{name}.s", "package pkg\nfunc build() int { return 0 }\n")
        rc, report = self.run_closure()
        self.assertEqual(rc, 2)
        failure = report["unresolved_imports"][0]
        self.assertEqual(failure["reason"], "ambiguous_symbol")
        self.assertEqual([c["source"] for c in failure["candidates"]],
                         ["src/pkg/a.s", "src/pkg/b.s"])

    def test_unsupported_use_syntax_is_reported(self):
        self.source("src/main.s", "package entry\nuse pkg.{one, two}\n")
        self.source("src/pkg/one.s", "package pkg\nfunc one() int { return 0 }\n")
        rc, report = self.run_closure()
        self.assertEqual(rc, 2)
        self.assertEqual(report["unresolved_imports"][0]["reason"], "unsupported_dependency_syntax")

    def test_two_runs_byte_identical_and_content_changes_manifest_hash(self):
        self.source("src/main.s", "package entry\nfunc main() int { return 1 }\n")
        rc, first = self.run_closure(output="one")
        rc2, second = self.run_closure(entry="src/../src/main.s", output="two")
        self.assertEqual((rc, rc2), (0, 0))
        self.assertEqual(first, second)
        for path in (self.root / "one").iterdir():
            self.assertEqual(path.read_bytes(), (self.root / "two" / path.name).read_bytes())
        self.assertEqual(first["files"][0]["sha256"],
                         hashlib.sha256((self.root / "src/main.s").read_bytes()).hexdigest())
        self.assertEqual(first["manifest_sha256"],
                         hashlib.sha256((self.root / "one/canonical-manifest.json").read_bytes()).hexdigest())
        self.source("src/main.s", "package entry\nfunc main() int { return 2 }\n")
        _, third = self.run_closure(output="three")
        self.assertNotEqual(first["manifest_sha256"], third["manifest_sha256"])


unittest.main(verbosity=2)
PY
