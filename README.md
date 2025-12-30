# SSRF DNS

A lightweight DNS server for testing SSRF via DNS rebinding.

## Build

```bash
go build -o ssrf-dns main.go
```

## Usage

```bash
./ssrf-dns -valid <valid_ip> -internal <internal_ip> [-port <port>] [-log <file>]
```

**Example:**

```bash
./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -port 10053
```

- **First Query**: Returns `valid` IP.
- **Subsequent Queries**: Returns `internal` IP (state tracks by domain).

## Testing

```bash
dig @127.0.0.1 -p 10053 test.example.com +short
```

Run twice to see the IP change.
