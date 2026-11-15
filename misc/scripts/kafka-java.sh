#!/usr/bin/env bash
# Source to select/download the test-only runtime. Never installs system packages.
# Corretto archive fetched over HTTPS; pinned SHA256, with vendor checksum provenance
# documented in test/kafka/README.md. Writes only beneath .bootstrap/kafka-broker.
kafka_test_java() {
    local root base archive expected
    root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || return
    base="$root/.bootstrap/kafka-broker"
    if command -v java >/dev/null; then return 0; fi
    if [[ ! -x "$base/java/bin/java" ]]; then
        archive="$base/phase1/java.tar.gz"
        expected=8f9a2ddb131ec5317419f2b0769240fe22ce27f8a0ae43f5346d53e1c8aec6a0
        mkdir -p "$base/phase1" "$base/java" || return
        if [[ ! -f "$archive" ]]; then
            curl -fsSL --retry 3 https://corretto.aws/downloads/resources/17.0.21.0.11/amazon-corretto-17.0.21.0.11-linux-x64.tar.gz -o "$archive.part" || return
            mv "$archive.part" "$archive" || return
        fi
        printf '%s  %s\n' "$expected" "$archive" | sha256sum -c - || return
        tar -xzf "$archive" --strip-components=1 -C "$base/java" || return
    fi
    export JAVA_HOME="$base/java"
    export PATH="$JAVA_HOME/bin:$PATH"
    java -version
}
