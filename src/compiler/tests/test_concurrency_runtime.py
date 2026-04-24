from __future__ import annotations

import unittest

from compiler.interpreter import interpreter
from compiler.parser import parse_source


class TestConcurrencyRuntime(unittest.TestCase):
    def test_go_and_channel_delivery(self) -> None:
        source = """
package demo.conc

func worker(chan ch) int32 {
    chan_send(ch, 7)
    0
}

func main() int32 {
    var ch = chan_make(2)
    go("worker", ch)
    var ran = go_drain()
    var got =
        switch chan_recv(ch) {
            some(value) : value,
            none : 0,
        }
    ran * 10 + got
}
"""
        vm = interpreter(parse_source(source))
        self.assertEqual(vm.run_main(), 17)

    def test_select_round_robin_between_ready_channels(self) -> None:
        source = """
package demo.select

func main() int32 {
    var a = chan_make(2)
    var b = chan_make(2)
    chan_send(a, 11)
    chan_send(b, 22)
    var chans = vec[chan](a, b)

    var first =
        switch select_recv(chans) {
            some(rec) : rec.index,
            none : 99,
        }
    var second =
        switch select_recv(chans) {
            some(rec) : rec.index,
            none : 99,
        }

    first * 10 + second
}
"""
        vm = interpreter(parse_source(source))
        self.assertEqual(vm.run_main(), 1)


if __name__ == "__main__":
    unittest.main()
