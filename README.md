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
go build -o ssrf-dns .
```

## Usage

```bash
ssrf-dns version
ssrf-dns -valid <valid_ip> -internal <internal_ip> -domain <domain> [-port <port>] [-upstream <addr>] [-records <file>] [-log <file>]
```

**Example:**

```bash
ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port 10053
```

- **Queries for `*.example.com`**:
  - **Static Records**: If defined in YAML, returned immediately (precedes rebind logic).
  - First Query: Returns `valid` IP.
  - Subsequent Queries: Returns `internal` IP.
- **Other Queries (e.g., Google)**: Proxied to standard DNS (default `8.8.8.8:53` or specified via `-upstream`).

## Static Records (YAML)

You can define static records (A, TXT, CNAME) in a YAML file. These records take precedence over the rebind logic.

1.  **Create `records.yaml`**:

    ```yaml
    record:
      foo.example.com:
        type: TXT
        value: "thisisatextualvalue"
      bar.example.com:
        type: A
        value: "1.1.1.1"
      cname.example.com:
        type: CNAME
        value: "google.com."
    ```

2.  **Run with `-records` flag**:

    ```bash
    ssrf-dns ... -records records.yaml
    ```

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
