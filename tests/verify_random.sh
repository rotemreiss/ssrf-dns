#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$DIR/.."

# Build from root
cd "$ROOT_DIR"
go build -o ssrf-dns .

# Start server with -random
PORT=10060
echo "Starting server with -random on port $PORT..."
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port $PORT -random &
PID=$!
sleep 2

cleanup() {
    kill $PID 2>/dev/null
    rm -f ssrf-dns
}
trap cleanup EXIT

echo "--- Test 1: Random Mode - Both IPs Observed ---"
DOMAIN="test.example.com"
VALID_COUNT=0
INTERNAL_COUNT=0
NUM_QUERIES=20

for i in $(seq 1 $NUM_QUERIES); do
    RESP=$(dig @127.0.0.1 -p $PORT $DOMAIN +short)
    if [ "$RESP" == "1.1.1.1" ]; then
        VALID_COUNT=$((VALID_COUNT + 1))
    elif [ "$RESP" == "127.0.0.1" ]; then
        INTERNAL_COUNT=$((INTERNAL_COUNT + 1))
    else
        echo "RANDOM MODE: FAILED - Unexpected response: $RESP"
        exit 1
    fi
done

echo "Results: valid=$VALID_COUNT, internal=$INTERNAL_COUNT (out of $NUM_QUERIES queries)"

# Both IPs must appear at least once in 20 queries (probability of failure ~2^-20 ≈ 0.0001%)
if [ "$VALID_COUNT" -gt 0 ] && [ "$INTERNAL_COUNT" -gt 0 ]; then
    echo "RANDOM MODE (both IPs observed): PASSED"
else
    echo "RANDOM MODE: FAILED - Expected both IPs to appear. valid=$VALID_COUNT, internal=$INTERNAL_COUNT"
    exit 1
fi

echo "--- Test 2: Random Mode - No Sequential Rebind Pattern ---"
# In random mode, the second query should NOT always be the internal IP
# Run 10 fresh subdomains - at least one second query should return valid IP
SECOND_VALID=0
for i in $(seq 1 10); do
    SUB="rand${i}.example.com"
    RESP1=$(dig @127.0.0.1 -p $PORT $SUB +short)
    RESP2=$(dig @127.0.0.1 -p $PORT $SUB +short)
    if [ "$RESP2" == "1.1.1.1" ]; then
        SECOND_VALID=$((SECOND_VALID + 1))
    fi
done

echo "Second-query valid count: $SECOND_VALID out of 10"

if [ "$SECOND_VALID" -gt 0 ]; then
    echo "RANDOM MODE (no sequential pattern): PASSED"
else
    echo "RANDOM MODE (no sequential pattern): FAILED - second query always returned internal IP"
    exit 1
fi

echo "ALL RANDOM MODE TESTS PASSED"
