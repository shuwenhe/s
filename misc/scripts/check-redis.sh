#!/bin/sh
# The compiler/server lifecycle is shell tooling. All tests and peers are S.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"
mode=${1:-all}
case "$mode" in protocol|integration|all) ;; *) echo 'usage: test-redis.sh [protocol|integration|all]' >&2; exit 2 ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/s-redis-check.XXXXXXXX")
server_pid=
peer_pid=
cleanup() {
    if [ -n "$peer_pid" ]; then
        kill "$peer_pid" 2>/dev/null || :
        wait "$peer_pid" 2>/dev/null || :
    fi
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || :
        wait "$server_pid" 2>/dev/null || :
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

if [ "$mode" = protocol ] || [ "$mode" = all ]; then
    for abi in seed native; do
        sh misc/scripts/build-redis-test.sh "protocol-$abi" "$work/protocol-$abi"
        "$work/protocol-$abi"
    done
fi
if [ "$mode" = protocol ]; then
    exit 0
fi

for tool in redis-server openssl timeout; do
    command -v "$tool" >/dev/null || { echo "missing dependency: $tool" >&2; exit 1; }
done
sh misc/scripts/build-redis-test.sh suite "$work/suite"
sh misc/scripts/build-redis-test.sh peer "$work/peer"
sh misc/scripts/build-redis-test.sh basic "$work/basic"

wait_ready() {
    ready_log=$1
    ready_pid=$2
    ready_pattern=$3
    attempt=0
    while ! awk -v pattern="$ready_pattern" '$0 ~ pattern {found=1} END {exit !found}' "$ready_log"; do
        if ! kill -0 "$ready_pid" 2>/dev/null; then
            cat "$ready_log" >&2
            echo 'test process exited before readiness' >&2
            return 1
        fi
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 200 ]; then
            cat "$ready_log" >&2
            echo 'test process readiness timed out' >&2
            return 1
        fi
        sleep 0.05
    done
}
choose_port() {
    port=$(S_REDIS_PEER_MODE=port "$work/peer" | awk '/^READY / {print $2}')
    case "$port" in ''|*[!0-9]*) echo 'S port allocation failed' >&2; exit 1 ;; esac
}
start_redis() {
    redis-server "$work/redis.conf" > "$work/redis.log" 2>&1 &
    server_pid=$!
    wait_ready "$work/redis.log" "$server_pid" 'Ready to accept connections'
}
stop_redis() {
    kill "$server_pid"
    wait "$server_pid"
    server_pid=
}
base_config() {
    cat > "$work/redis.conf" <<CONFIG
bind 127.0.0.1
protected-mode yes
save ""
appendonly no
user default on >local-test-secret ~* +@all
user tester on >acl-test-secret ~* +@all
dir "$work"
CONFIG
}

choose_port
base_config
printf 'port %s\n' "$port" >> "$work/redis.conf"
start_redis
REDIS_PORT="$port" REDIS_TLS=0 S_REDIS_TEST=integration timeout 30 "$work/suite"
REDIS_HOST=127.0.0.1 REDIS_PORT="$port" REDIS_USER= REDIS_PASSWORD=local-test-secret \
    REDIS_TLS=0 timeout 15 "$work/basic"
stop_redis

for fault in fragmented malformed oversized truncated disconnect timeout trickle wrongtype servererror; do
    S_REDIS_FAULT="$fault" "$work/peer" > "$work/peer.log" 2>&1 &
    peer_pid=$!
    wait_ready "$work/peer.log" "$peer_pid" '^READY '
    port=$(awk '/^READY / {print $2; exit}' "$work/peer.log")
    REDIS_PORT="$port" S_REDIS_TEST=fault S_REDIS_FAULT="$fault" timeout 10 "$work/suite"
    wait "$peer_pid"
    peer_pid=
done

# Temporary local CA; verification is exercised by the S TLS test, not a CLI client.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/ca.key" -out "$work/ca.pem" \
    -days 1 -subj '/CN=S Redis test CA' > "$work/openssl.log" 2>&1
openssl req -newkey rsa:2048 -nodes -keyout "$work/server.key" -out "$work/server.csr" \
    -subj '/CN=redis.local' >> "$work/openssl.log" 2>&1
printf 'subjectAltName=DNS:redis.local\nextendedKeyUsage=serverAuth\n' > "$work/extensions"
openssl x509 -req -in "$work/server.csr" -CA "$work/ca.pem" -CAkey "$work/ca.key" \
    -CAcreateserial -out "$work/server.pem" -days 1 -extfile "$work/extensions" >> "$work/openssl.log" 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/wrong.key" -out "$work/wrong.pem" \
    -days 1 -subj '/CN=Untrusted CA' >> "$work/openssl.log" 2>&1
choose_port
base_config
cat >> "$work/redis.conf" <<CONFIG
port 0
tls-port $port
tls-cert-file "$work/server.pem"
tls-key-file "$work/server.key"
tls-ca-cert-file "$work/ca.pem"
tls-auth-clients no
CONFIG
start_redis
REDIS_PORT="$port" REDIS_TLS=1 REDIS_TLS_SERVER_NAME=redis.local \
    REDIS_TLS_CA_FILE="$work/ca.pem" REDIS_TLS_WRONG_CA_FILE="$work/wrong.pem" \
    S_REDIS_TEST=tls timeout 30 "$work/suite"
stop_redis
printf 'native S Redis acceptance: PASS\n'
