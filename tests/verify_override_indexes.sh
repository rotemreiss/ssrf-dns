#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$DIR/.."

# Build from root
cd "$ROOT_DIR"
go build -o ssrf-dns .

VALID_IP="1.1.1.1"
INTERNAL_IP="127.0.0.1"
PASS=0
FAIL=0

run_test() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" == "$expected" ]; then
        echo "  PASS: $test_name (got $actual)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name (expected $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

query() {
    dig @127.0.0.1 -p $PORT "$1" +short 2>/dev/null
}

cleanup() {
    kill $PID 2>/dev/null
    wait $PID 2>/dev/null
}

# =========================================================
echo "=== Test 1: --internal-for standalone ==="
# --internal-for 3: all valid except query 3
PORT=10070
./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port $PORT -internal-for 3 &
PID=$!
sleep 1

DOMAIN="t1.example.com"
run_test "Query 1 = valid"   "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 2 = valid"   "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 3 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 4 = valid"   "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 5 = valid"   "$VALID_IP"    "$(query $DOMAIN)"
cleanup

# =========================================================
echo ""
echo "=== Test 2: --valid-for standalone ==="
# --valid-for 2,4: all internal except queries 2 and 4
PORT=10071
./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port $PORT -valid-for 2,4 &
PID=$!
sleep 1

DOMAIN="t2.example.com"
run_test "Query 1 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 2 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 3 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 4 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 5 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
cleanup

# =========================================================
echo ""
echo "=== Test 3: --rebind-after 2 --valid-for 4 ==="
# Queries 1-2 valid, 3 internal, 4 valid (override), 5+ internal
PORT=10072
./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port $PORT -rebind-after 2 -valid-for 4 &
PID=$!
sleep 1

DOMAIN="t3.example.com"
run_test "Query 1 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 2 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 3 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 4 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 5 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 6 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
cleanup

# =========================================================
echo ""
echo "=== Test 4: --rebind-after 3 --internal-for 1,2 ==="
# Query 1 internal (override), 2 internal (override), 3 valid (rebind-after), 4+ internal
PORT=10073
./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port $PORT -rebind-after 3 -internal-for 1,2 &
PID=$!
sleep 1

DOMAIN="t4.example.com"
run_test "Query 1 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 2 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 3 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 4 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 5 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
cleanup

# =========================================================
echo ""
echo "=== Test 5: --rebind-after 2 --valid-for 4 --internal-for 1 ==="
# Query 1 internal (override), 2 valid (rebind), 3 internal (rebind), 4 valid (override), 5+ internal
PORT=10074
./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port $PORT -rebind-after 2 -valid-for 4 -internal-for 1 &
PID=$!
sleep 1

DOMAIN="t5.example.com"
run_test "Query 1 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 2 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 3 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 4 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 5 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
cleanup

# =========================================================
echo ""
echo "=== Test 6: --internal-for with multiple indexes (comma-separated) ==="
# --internal-for 1,3,5: all valid except queries 1, 3, 5
PORT=10075
./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port $PORT -internal-for 1,3,5 &
PID=$!
sleep 1

DOMAIN="t6.example.com"
run_test "Query 1 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 2 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 3 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 4 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 5 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 6 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
cleanup

# =========================================================
echo ""
echo "=== Test 7: Both flags without --rebind-after (assume rebind-after=0) ==="
# --internal-for 2 --valid-for 4: base=all internal, query 2=internal (redundant), query 4=valid
PORT=10076
./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port $PORT -internal-for 2 -valid-for 4 &
PID=$!
sleep 1

DOMAIN="t7.example.com"
run_test "Query 1 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 2 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 3 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
run_test "Query 4 = valid"    "$VALID_IP"    "$(query $DOMAIN)"
run_test "Query 5 = internal" "$INTERNAL_IP" "$(query $DOMAIN)"
cleanup

# =========================================================
echo ""
echo "=== Test 8: Error cases ==="

# 8a: overlapping indexes
echo "  Testing overlapping indexes..."
OUTPUT=$(./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port 10077 -internal-for 3 -valid-for 3 2>&1)
if echo "$OUTPUT" | grep -q "appears in both"; then
    echo "  PASS: Overlapping indexes rejected"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Overlapping indexes not detected"
    FAIL=$((FAIL + 1))
fi

# 8b: random + internal-for
echo "  Testing random + internal-for..."
OUTPUT=$(./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port 10077 -random -internal-for 3 2>&1)
if echo "$OUTPUT" | grep -q "cannot be used with"; then
    echo "  PASS: random + internal-for rejected"
    PASS=$((PASS + 1))
else
    echo "  FAIL: random + internal-for not detected"
    FAIL=$((FAIL + 1))
fi

# 8c: random + valid-for
echo "  Testing random + valid-for..."
OUTPUT=$(./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port 10077 -random -valid-for 3 2>&1)
if echo "$OUTPUT" | grep -q "cannot be used with"; then
    echo "  PASS: random + valid-for rejected"
    PASS=$((PASS + 1))
else
    echo "  FAIL: random + valid-for not detected"
    FAIL=$((FAIL + 1))
fi

# 8d: index 0
echo "  Testing index 0..."
OUTPUT=$(./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port 10077 -valid-for 0 2>&1)
if echo "$OUTPUT" | grep -q "must be >= 1"; then
    echo "  PASS: index 0 rejected"
    PASS=$((PASS + 1))
else
    echo "  FAIL: index 0 not detected"
    FAIL=$((FAIL + 1))
fi

# 8e: negative index
echo "  Testing negative index..."
OUTPUT=$(./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port 10077 -internal-for -1 2>&1)
if echo "$OUTPUT" | grep -qi "invalid\|must be"; then
    echo "  PASS: negative index rejected"
    PASS=$((PASS + 1))
else
    echo "  FAIL: negative index not detected (output: $OUTPUT)"
    FAIL=$((FAIL + 1))
fi

# 8f: non-numeric index
echo "  Testing non-numeric index..."
OUTPUT=$(./ssrf-dns -valid $VALID_IP -internal $INTERNAL_IP -domain example.com -port 10077 -valid-for abc 2>&1)
if echo "$OUTPUT" | grep -q "must be a positive integer"; then
    echo "  PASS: non-numeric index rejected"
    PASS=$((PASS + 1))
else
    echo "  FAIL: non-numeric index not detected"
    FAIL=$((FAIL + 1))
fi

# =========================================================
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "SOME TESTS FAILED"
    rm -f ssrf-dns
    exit 1
else
    echo "ALL TESTS PASSED"
fi

rm -f ssrf-dns
