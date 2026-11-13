#!/usr/bin/env bash
# Source this helper. The caller must install: trap kafka_stop EXIT
# Official broker/admin tools only; client protocol tests are written in S.
declare -a KAFKA_OWNED_PIDS=() KAFKA_OWNED_CONFIGS=()

kafka_prepare() {
    local tool archive actual
    for tool in java curl tar sha512sum awk tr; do
        command -v "$tool" >/dev/null || { echo "Kafka requires $tool" >&2; return 1; }
    done
    KAFKA_CACHE=${KAFKA_CACHE:-/tmp/s-kafka-3.9.1}
    KAFKA_HOME="$KAFKA_CACHE/kafka_2.13-3.9.1"
    archive="$KAFKA_CACHE/kafka_2.13-3.9.1.tgz"
    mkdir -p "$KAFKA_CACHE" || return
    # SHA512 published by Apache beside the pinned Scala 2.13 distribution.
    local expected=1ea204ba73411737a275429ca976d440f007ff0957b90b19be41dc5a4bae52617267769be9f0b5791714d0b3c4c760605bd426faea39edd90763585523fa2cfe
    if [[ ! -f "$archive" ]]; then
        curl -fsSL --retry 3 https://archive.apache.org/dist/kafka/3.9.1/kafka_2.13-3.9.1.tgz -o "$archive.part" || return
        mv "$archive.part" "$archive" || return
    fi
    actual=$(sha512sum "$archive" | awk '{print $1}') || return
    [[ "$actual" == "$expected" ]] || { echo "Kafka archive SHA512 mismatch: $archive" >&2; return 1; }
    if [[ ! -x "$KAFKA_HOME/bin/kafka-storage.sh" ]]; then
        tar -xzf "$archive" -C "$KAFKA_CACHE" || return
    fi
    export KAFKA_HOME
}

kafka_stop() {
    local i pid config
    for i in "${!KAFKA_OWNED_PIDS[@]}"; do
        pid=${KAFKA_OWNED_PIDS[$i]}
        config=${KAFKA_OWNED_CONFIGS[$i]}
        # Check identity as well as PID, avoiding a kill after PID reuse.
        if [[ -r /proc/$pid/cmdline ]] && tr '\0' '\n' < "/proc/$pid/cmdline" | grep -Fxq -- "$config"; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    for pid in "${KAFKA_OWNED_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    KAFKA_OWNED_PIDS=()
    KAFKA_OWNED_CONFIGS=()
}

kafka_start() {
    [[ $# -ge 4 && $# -le 5 ]] || { echo 'usage: kafka_start WORKDIR BROKER1_PORT BROKER2_PORT CONTROLLER_PORT [TLS_PORT]' >&2; return 1; }
    local directory=$1 first=$2 second=$3 controller=$4 tls=${5:-} port id config cluster deadline
    for port in "$first" "$second" "$controller" ${tls:+"$tls"}; do
        [[ "$port" =~ ^[0-9]+$ && "$port" -gt 0 && "$port" -lt 65536 ]] || { echo "Invalid Kafka port: $port" >&2; return 1; }
    done
    [[ "$first" != "$second" && "$first" != "$controller" && "$second" != "$controller" ]] || return 1
    [[ -z "$tls" || ( "$tls" != "$first" && "$tls" != "$second" && "$tls" != "$controller" ) ]] || return 1
    [[ ${#KAFKA_OWNED_PIDS[@]} -eq 0 ]] || { echo 'Call kafka_stop before kafka_start' >&2; return 1; }
    kafka_prepare || return
    mkdir -p "$directory" || return
    KAFKA_WORKDIR=$(cd "$directory" && pwd) || return
    KAFKA_BOOTSTRAP="127.0.0.1:$first"
    KAFKA_BROKER2="127.0.0.1:$second"
    KAFKA_TLS_BOOTSTRAP=""
    export KAFKA_WORKDIR KAFKA_BOOTSTRAP KAFKA_BROKER2 KAFKA_TLS_BOOTSTRAP
    printf "request.timeout.ms=3000\ndefault.api.timeout.ms=5000\n" > "$KAFKA_WORKDIR/admin.properties"
    if [[ -n "$tls" ]]; then
        command -v openssl >/dev/null || { echo 'TLS requires openssl' >&2; return 1; }
        if [[ ! -f "$KAFKA_WORKDIR/server.pem" ]]; then
            openssl req -x509 -newkey rsa:2048 -nodes -keyout "$KAFKA_WORKDIR/server.key" -out "$KAFKA_WORKDIR/server.crt" -days 2 -subj /CN=localhost -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' > "$KAFKA_WORKDIR/openssl.log" 2>&1 || return
            cat "$KAFKA_WORKDIR/server.key" "$KAFKA_WORKDIR/server.crt" > "$KAFKA_WORKDIR/server.pem" || return
            chmod 600 "$KAFKA_WORKDIR/server.key" "$KAFKA_WORKDIR/server.pem"
        fi
        KAFKA_TLS_BOOTSTRAP="127.0.0.1:$tls"
        export KAFKA_TLS_BOOTSTRAP
    fi
    if [[ ! -s "$KAFKA_WORKDIR/cluster.id" ]]; then
        "$KAFKA_HOME/bin/kafka-storage.sh" random-uuid > "$KAFKA_WORKDIR/cluster.id" || return
    fi
    cluster=$(cat "$KAFKA_WORKDIR/cluster.id")
    for id in 1 2 3; do
        config="$KAFKA_WORKDIR/node-$id.properties"
        {
            echo "node.id=$id"
            echo "controller.quorum.voters=3@127.0.0.1:$controller"
            echo 'controller.listener.names=CONTROLLER'
            echo 'inter.broker.listener.name=PLAINTEXT'
            echo "log.dirs=$KAFKA_WORKDIR/data-$id"
            echo 'offsets.topic.replication.factor=2'
            echo 'transaction.state.log.replication.factor=2'
            echo 'transaction.state.log.min.isr=1'
            echo 'group.initial.rebalance.delay.ms=0'
            echo 'auto.create.topics.enable=false'
            echo 'num.network.threads=2'
            echo 'num.io.threads=2'
            if [[ $id == 3 ]]; then
                echo 'process.roles=controller'
                echo "listeners=CONTROLLER://127.0.0.1:$controller"
                echo 'listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT'
            else
                port=$first
                [[ $id == 1 ]] || port=$second
                echo 'process.roles=broker'
                if [[ $id == 1 && -n "$tls" ]]; then
                    echo "listeners=PLAINTEXT://127.0.0.1:$port,SSL://127.0.0.1:$tls"
                    echo "advertised.listeners=PLAINTEXT://127.0.0.1:$port,SSL://127.0.0.1:$tls"
                    echo 'listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL'
                    echo 'ssl.keystore.type=PEM'
                    echo "ssl.keystore.location=$KAFKA_WORKDIR/server.pem"
                    echo 'ssl.client.auth=none'
                else
                    echo "listeners=PLAINTEXT://127.0.0.1:$port"
                    echo "advertised.listeners=PLAINTEXT://127.0.0.1:$port"
                    echo 'listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT'
                fi
            fi
        } > "$config" || return
        if [[ ! -f "$KAFKA_WORKDIR/data-$id/meta.properties" ]]; then
            "$KAFKA_HOME/bin/kafka-storage.sh" format -t "$cluster" -c "$config" > "$KAFKA_WORKDIR/format-$id.log" 2>&1 || { cat "$KAFKA_WORKDIR/format-$id.log" >&2; return 1; }
        fi
    done
    KAFKA_OWNED_PIDS=()
    KAFKA_OWNED_CONFIGS=()
    for id in 3 1 2; do
        config="$KAFKA_WORKDIR/node-$id.properties"
        KAFKA_HEAP_OPTS='-Xms128m -Xmx256m' LOG_DIR="$KAFKA_WORKDIR/logs-$id" "$KAFKA_HOME/bin/kafka-server-start.sh" "$config" >> "$KAFKA_WORKDIR/node-$id.log" 2>&1 &
        KAFKA_OWNED_PIDS+=("$!")
        KAFKA_OWNED_CONFIGS+=("$config")
    done
    deadline=$((SECONDS + 90))
    while (( SECONDS < deadline )); do
        for id in "${KAFKA_OWNED_PIDS[@]}"; do
            kill -0 "$id" 2>/dev/null || { tail -60 "$KAFKA_WORKDIR"/node-*.log >&2; kafka_stop; return 1; }
        done
        if "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --command-config "$KAFKA_WORKDIR/admin.properties" --list > "$KAFKA_WORKDIR/readiness.log" 2>&1 &&
            "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BROKER2" --command-config "$KAFKA_WORKDIR/admin.properties" --list >> "$KAFKA_WORKDIR/readiness.log" 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "Kafka readiness timed out: $KAFKA_WORKDIR" >&2
    tail -60 "$KAFKA_WORKDIR"/node-*.log >&2
    kafka_stop
    return 1
}

kafka_create_topic() {
    [[ $# -ge 1 && $# -le 3 ]] || { echo 'usage: kafka_create_topic TOPIC [PARTITIONS=2] [REPLICATION=2]' >&2; return 1; }
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$KAFKA_BOOTSTRAP" --create --if-not-exists --topic "$1" --partitions "${2:-2}" --replication-factor "${3:-2}"
}
