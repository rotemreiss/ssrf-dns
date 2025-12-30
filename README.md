# SSRF DNS

A lightweight DNS server for testing SSRF via DNS rebinding.

## Install

```bash
go install github.com/rotemreiss/ssrf-dns@latest
```

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

## Port 53 on Linux (Ubuntu)

On Ubuntu (systemd-based systems), port 53 is often occupied by `systemd-resolved`.

To use port 53:

1.  **Stop systemd-resolved**:
    ```bash
    sudo systemctl stop systemd-resolved
    ```
2.  **Run with sudo** (required for ports < 1024):
    ```bash
    sudo ./ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -port 53
    ```

*Note: Stopping systemd-resolved may break DNS resolution on the host machine itself while it is stopped.*
