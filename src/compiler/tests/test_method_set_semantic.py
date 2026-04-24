from __future__ import annotations

import unittest

from compiler.parser import parse_source
from compiler.semantic import check_source


class TestMethodSetSemantic(unittest.TestCase):
    def test_value_can_call_ref_method_when_addressable(self) -> None:
        source = """
package demo.receiver

struct box {
    int32 v
}

impl box {
    func peek(&box self) int32 {
        self.v
    }
}

func main() int32 {
    var b = box{ v: 3 }
    b.peek()
}
"""
        result = check_source(parse_source(source))
        self.assertTrue(result.ok, [d.message for d in result.diagnostics])

    def test_temporary_cannot_call_ref_method(self) -> None:
        source = """
package demo.receiver

struct box {
    int32 v
}

impl box {
    func peek(&box self) int32 {
        self.v
    }
}

func make_box() box {
    box{ v: 3 }
}

func main() int32 {
    make_box().peek()
}
"""
        result = check_source(parse_source(source))
        self.assertFalse(result.ok)
        self.assertIn("no method peek for box", [d.message for d in result.diagnostics])

    def test_trait_impl_receiver_mode_must_match(self) -> None:
        source = """
package demo.receiver

struct box {
    int32 v
}

trait reader {
    func peek(box self) int32;
}

impl reader for box {
    func peek(&box self) int32 {
        self.v
    }
}

func main() int32 {
    0
}
"""
        result = check_source(parse_source(source))
        self.assertFalse(result.ok)
        self.assertIn("impl method signature mismatch peek", [d.message for d in result.diagnostics])


if __name__ == "__main__":
    unittest.main()
