#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$DIR/.."

# Build from root
cd "$ROOT_DIR"
go build -o ssrf-dns .

# Start server with domain filter
echo "Starting server with -domain example.com..."
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port 10056 &
PID=$!
sleep 2

cleanup() {
    kill $PID 2>/dev/null
    rm -f ssrf-dns
}
trap cleanup EXIT

echo "--- Test 1: Matching Domain (should rebind) ---"
DOMAIN="test.example.com"
RESP1=$(dig @127.0.0.1 -p 10056 $DOMAIN +short)
RESP2=$(dig @127.0.0.1 -p 10056 $DOMAIN +short)
echo "Resp 1: $RESP1"
echo "Resp 2: $RESP2"

if [ "$RESP1" == "1.1.1.1" ] && [ "$RESP2" == "127.0.0.1" ]; then
    echo "MATCHING DOMAIN: PASSED"
else
    echo "MATCHING DOMAIN: FAILED"
    exit 1
fi
