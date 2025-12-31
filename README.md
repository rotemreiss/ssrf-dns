# SSRF DNS

A lightweight DNS server for testing SSRF via DNS rebinding.

## Install

```bash
go install github.com/rotemreiss/ssrf-dns@latest
```

## Build from source

```bash
git clone https://github.com/rotemreiss/ssrf-dns.git
cd ssrf-dns
go build -o ssrf-dns main.go
```

## Usage

```bash
ssrf-dns -valid <valid_ip> -internal <internal_ip> -domain <domain> [-port <port>] [-upstream <addr>] [-log <file>]
```

**Example:**

```bash
ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port 10053
```

- **Queries for `*.example.com`**:
  - First Query: Returns `valid` IP.
  - Subsequent Queries: Returns `internal` IP.
- **Other Queries (e.g., Google)**: Proxied to standard DNS (default `8.8.8.8:53` or specified via `-upstream`).

## Testing

```bash
dig @127.0.0.1 -p 10053 test.example.com +short
```

Run twice to see the IP change.

## Troubleshooting

### Port 53 on Linux (Ubuntu)

On Ubuntu (systemd-based systems), port 53 is often occupied by `systemd-resolved`.

To use port 53, **Stop systemd-resolved**:
```bash
sudo systemctl stop systemd-resolved
ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com
```

*Note: Stopping systemd-resolved may break DNS resolution on the host machine itself while it is stopped.*
