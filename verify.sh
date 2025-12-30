#!/bin/bash

# Build the server
echo "Building server..."
go build -o ssrf-dns main.go
if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

# Define ports and IPs
PORT=10053
VALID_IP="1.1.1.1"
INTERNAL_IP="127.0.0.1"
LOG_FILE="dns.log"

# Cleanup function
cleanup() {
    echo "Stopping server..."
    kill $SERVER_PID 2>/dev/null
    rm -f ssrf-dns $LOG_FILE
}
trap cleanup EXIT

# Start server
echo "Starting server..."
./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -port $PORT -log $LOG_FILE &
SERVER_PID=$!
sleep 2

# Test Domain
DOMAIN="test.example.com"

echo "Query 1 (Should be $VALID_IP)..."
RES1=$(dig @127.0.0.1 -p $PORT +short $DOMAIN)
echo "Result 1: $RES1"

if [ "$RES1" != "$VALID_IP" ]; then
    echo "FAIL: Expected $VALID_IP, got $RES1"
    exit 1
fi

echo "Query 2 (Should be $INTERNAL_IP)..."
RES2=$(dig @127.0.0.1 -p $PORT +short $DOMAIN)
echo "Result 2: $RES2"

if [ "$RES2" != "$INTERNAL_IP" ]; then
    echo "FAIL: Expected $INTERNAL_IP, got $RES2"
    exit 1
fi

# Check Log
echo "Checking log..."
cat $LOG_FILE
if grep -q "State: NEW" $LOG_FILE && grep -q "State: RETURNING" $LOG_FILE; then
    echo "Log verification PASSED"
else
    echo "Log verification FAILED"
    exit 1
fi

echo "ALL TESTS PASSED"
