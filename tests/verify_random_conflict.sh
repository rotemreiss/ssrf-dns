#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$DIR/.."

# Build from root
cd "$ROOT_DIR"
go build -o ssrf-dns .

cleanup() {
    rm -f ssrf-dns
}
trap cleanup EXIT

echo "--- Test 1: -random with -rebind-after should fail ---"
OUTPUT=$(./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -random -rebind-after 3 2>&1)
EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ] && echo "$OUTPUT" | grep -q "cannot be used together"; then
    echo "CONFLICT DETECTION (random + rebind-after): PASSED"
else
    echo "CONFLICT DETECTION (random + rebind-after): FAILED"
    echo "Exit code: $EXIT_CODE"
    echo "Output: $OUTPUT"
    exit 1
fi

echo "--- Test 2: -random alone should start (then we kill it) ---"
PORT=10061
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -random -port $PORT &
PID=$!
sleep 2

if kill -0 $PID 2>/dev/null; then
    echo "RANDOM ALONE STARTS: PASSED"
    kill $PID 2>/dev/null
else
    echo "RANDOM ALONE STARTS: FAILED - server did not start"
    exit 1
fi

echo "--- Test 3: -rebind-after alone should start (then we kill it) ---"
PORT=10062
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -rebind-after 3 -port $PORT &
PID=$!
sleep 2

if kill -0 $PID 2>/dev/null; then
    echo "REBIND-AFTER ALONE STARTS: PASSED"
    kill $PID 2>/dev/null
else
    echo "REBIND-AFTER ALONE STARTS: FAILED - server did not start"
    exit 1
fi

echo "--- Test 4: -random with default -rebind-after (1) should work ---"
PORT=10063
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -random -port $PORT &
PID=$!
sleep 2

if kill -0 $PID 2>/dev/null; then
    echo "RANDOM WITH DEFAULT REBIND-AFTER: PASSED"
    kill $PID 2>/dev/null
else
    echo "RANDOM WITH DEFAULT REBIND-AFTER: FAILED - server did not start"
    exit 1
fi

echo "ALL CONFLICT TESTS PASSED"
