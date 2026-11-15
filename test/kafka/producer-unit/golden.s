package main
import "std.kafka"
// Independent Python struct packing + Castagnoli bit algorithm; not the S codec.
func golden_batch() string {
    return std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) +
        std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(61) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) +
        std.kafka.byte_string(2) + std.kafka.byte_string(230) + std.kafka.byte_string(65) + std.kafka.byte_string(164) + std.kafka.byte_string(75) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) +
        std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(1) + std.kafka.byte_string(139) + std.kafka.byte_string(207) +
        std.kafka.byte_string(229) + std.kafka.byte_string(104) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(1) + std.kafka.byte_string(139) + std.kafka.byte_string(207) +
        std.kafka.byte_string(229) + std.kafka.byte_string(104) + std.kafka.byte_string(0) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) +
        std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) + std.kafka.byte_string(255) +
        std.kafka.byte_string(255) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(0) + std.kafka.byte_string(1) + std.kafka.byte_string(22) + std.kafka.byte_string(0) + std.kafka.byte_string(0) +
        std.kafka.byte_string(0) + std.kafka.byte_string(1) + std.kafka.byte_string(10) + std.kafka.byte_string(104) + std.kafka.byte_string(101) + std.kafka.byte_string(108) + std.kafka.byte_string(108) + std.kafka.byte_string(111) +
        std.kafka.byte_string(0)
}
