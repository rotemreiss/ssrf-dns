#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$DIR/.."

# Build
cd "$ROOT_DIR"
go build -o ssrf-dns .

# Create records.yaml
cat <<EOF > records.yaml
record:
  foo.example.com:
    type: TXT
    value: "thisisatextualvalue"
  bar.example.com:
    type: A
    value: "1.2.3.4"
  cname.example.com:
    type: CNAME
    value: "google.com."
EOF

# Start server
echo "Starting server with -records records.yaml..."
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -records records.yaml -port 10058 &
PID=$!
sleep 2

cleanup() {
    kill $PID 2>/dev/null
    rm -f ssrf-dns records.yaml
}
trap cleanup EXIT

echo "--- Test 1: TXT Record (foo.example.com) ---"
RESP_TXT=$(dig @127.0.0.1 -p 10058 foo.example.com TXT +short)
echo "TXT Resp: $RESP_TXT"
if [[ "$RESP_TXT" == "\"thisisatextualvalue\"" ]]; then
    echo "TXT: PASSED"
else
    echo "TXT: FAILED"
    exit 1
fi

echo "--- Test 2: A Record (bar.example.com) ---"
RESP_A=$(dig @127.0.0.1 -p 10058 bar.example.com A +short)
echo "A Resp: $RESP_A"
if [[ "$RESP_A" == "1.2.3.4" ]]; then
    echo "A: PASSED"
else
    echo "A: FAILED"
    exit 1
fi

echo "--- Test 3: CNAME Record (cname.example.com) ---"
RESP_CNAME=$(dig @127.0.0.1 -p 10058 cname.example.com CNAME +short)
echo "CNAME Resp: $RESP_CNAME"
if [[ "$RESP_CNAME" == "google.com." ]]; then
    echo "CNAME: PASSED"
else
    echo "CNAME: FAILED"
    exit 1
fi

echo "ALL TESTS PASSED"
