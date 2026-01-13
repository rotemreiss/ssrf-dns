#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$DIR/.."

# Build from root
cd "$ROOT_DIR"
go build -o ssrf-dns .

# Start server with --rebind-after 2
PORT=10057
echo "Starting server with --rebind-after 2 on port $PORT..."
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port $PORT --rebind-after 2 &
PID=$!
sleep 2

cleanup() {
    kill $PID 2>/dev/null
    rm -f ssrf-dns
}
trap cleanup EXIT

echo "--- Test: Rebind After 2 ---"
DOMAIN="test.example.com"

echo "Query 1..."
RESP1=$(dig @127.0.0.1 -p $PORT $DOMAIN +short)
echo "Resp 1: $RESP1"

echo "Query 2..."
RESP2=$(dig @127.0.0.1 -p $PORT $DOMAIN +short)
echo "Resp 2: $RESP2"

echo "Query 3 (should rebind now)..."
RESP3=$(dig @127.0.0.1 -p $PORT $DOMAIN +short)
echo "Resp 3: $RESP3"

if [ "$RESP1" == "1.1.1.1" ] && [ "$RESP2" == "1.1.1.1" ] && [ "$RESP3" == "127.0.0.1" ]; then
    echo "REBIND AFTER 2: PASSED"
else
    echo "REBIND AFTER 2: FAILED"
    exit 1
fi

echo "--- Test: Rebind After 1 (Default behavior) ---"
kill $PID
sleep 1
PORT=10058
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port $PORT &
PID=$!
sleep 2

echo "Query 1..."
RESP1=$(dig @127.0.0.1 -p $PORT $DOMAIN +short)
echo "Resp 1: $RESP1"

echo "Query 2 (should rebind now)..."
RESP2=$(dig @127.0.0.1 -p $PORT $DOMAIN +short)
echo "Resp 2: $RESP2"

if [ "$RESP1" == "1.1.1.1" ] && [ "$RESP2" == "127.0.0.1" ]; then
    echo "REBIND AFTER 1 (DEFAULT): PASSED"
else
    echo "REBIND AFTER 1 (DEFAULT): FAILED"
    exit 1
fi
