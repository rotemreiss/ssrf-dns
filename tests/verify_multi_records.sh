#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$DIR/.."

# Build
cd "$ROOT_DIR"
go build -o ssrf-dns .

# Create records_multi.yaml
cat <<EOF > records_multi.yaml
record:
  txt.example.com:
    - type: TXT
      value: "value1"
    - type: TXT
      value: "value2"
  mixed.example.com:
    - type: A
      value: "1.1.1.1"
    - type: A
      value: "2.2.2.2"
  single.example.com:
      type: TXT
      value: "single"
EOF

# Start server
echo "Starting server with -records records_multi.yaml..."
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -records records_multi.yaml -port 10059 &
PID=$!
sleep 2

cleanup() {
    kill $PID 2>/dev/null
    rm -f ssrf-dns records_multi.yaml
}
trap cleanup EXIT

echo "--- Test 1: Multiple TXT Records (txt.example.com) ---"
RESP_TXT=$(dig @127.0.0.1 -p 10059 txt.example.com TXT +short | sort)
EXPECTED_TXT=$(echo -e "\"value1\"\n\"value2\"" | sort)
echo "Got:"
echo "$RESP_TXT"
echo "Expected:"
echo "$EXPECTED_TXT"

if [[ "$RESP_TXT" == "$EXPECTED_TXT" ]]; then
    echo "TXT: PASSED"
else
    echo "TXT: FAILED"
    exit 1
fi

echo "--- Test 2: Multiple A Records (mixed.example.com) ---"
RESP_A=$(dig @127.0.0.1 -p 10059 mixed.example.com A +short | sort)
EXPECTED_A=$(echo -e "1.1.1.1\n2.2.2.2" | sort)
echo "Got:"
echo "$RESP_A"
echo "Expected:"
echo "$EXPECTED_A"

if [[ "$RESP_A" == "$EXPECTED_A" ]]; then
    echo "A: PASSED"
else
    echo "A: FAILED"
    exit 1
fi

echo "--- Test 3: Single TXT Record (single.example.com) ---"
RESP_SINGLE=$(dig @127.0.0.1 -p 10059 single.example.com TXT +short)
if [[ "$RESP_SINGLE" == "\"single\"" ]]; then
    echo "SINGLE: PASSED"
else
    echo "SINGLE: FAILED"
    exit 1
fi

echo "ALL TESTS PASSED"
