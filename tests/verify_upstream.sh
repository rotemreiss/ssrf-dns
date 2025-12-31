#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$DIR/.."

# Build from root
cd "$ROOT_DIR"
go build -o ssrf-dns .

# Start server with custom upstream (1.1.1.1)
echo "Starting server with -upstream 1.1.1.1:53..."
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -upstream 1.1.1.1:53 -port 10057 &
PID=$!
sleep 2

cleanup() {
    kill $PID 2>/dev/null
    rm -f ssrf-dns
}
trap cleanup EXIT

echo "--- Test 1: Proxy Query (should succeed via 1.1.1.1) ---"
# We query google.com.
RESP=$(dig @127.0.0.1 -p 10057 google.com +short | head -n 1)
echo "Resp: $RESP"

if [[ "$RESP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
     echo "PROXY QUERY: PASSED"
else
     echo "PROXY QUERY: FAILED"
     exit 1
fi

echo "ALL TESTS PASSED"
