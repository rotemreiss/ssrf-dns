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
ssrf-dns -valid <valid_ip> -internal <internal_ip> -domain <domain> [-rebind-after <count>] [-random] [-internal-for <indexes>] [-valid-for <indexes>] [-port <port>] [-upstream <addr>] [-records <file>] [-log <file>]
```

### Arguments

| Argument | Description | Default |
| :--- | :--- | :--- |
| `-valid` | Valid (external) IP address to return initially | (Required) |
| `-internal` | Internal IP address to return after rebinding | (Required) |
| `-domain` | Target domain or subdomain to rebind | (Required) |
| `-rebind-after`| Number of resolutions before returning the internal IP | `1` |
| `-random` | Randomly return valid or internal IP (rbndr-style) | `false` |
| `-port` | UDP port to listen on | `53` |
| `-upstream` | Upstream DNS server for non-matching domains | `8.8.8.8:53` |
| `-records` | Path to YAML file containing static records | |
| `-internal-for`| Comma-separated query indexes that return the internal IP (all others return valid) | |
| `-valid-for` | Comma-separated query indexes that return the valid IP (all others return internal) | |
| `-delay` | Delay in milliseconds before responding to queries | `0` |
| `-log` | Path to log file (defaults to stdout) | |

**Example:**

```bash
ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port 10053
```

**Random mode (rbndr-style):**

```bash
ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port 10053 -random
```

In random mode, the server uses the least significant bit of the DNS query ID to randomly select between the valid and internal IP for each query (approximately 50/50 distribution). This mirrors the approach used by [rbndr](https://github.com/taviso/rbndr). When `-random` is enabled, `-rebind-after`, `-internal-for`, and `-valid-for` cannot be used.

### Per-query overrides

Use `-internal-for` and `-valid-for` to control exactly which query indexes return which IP.

**Return valid IP for all queries except query 6 (which returns internal):**

```bash
ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port 10053 -internal-for 6
```

**Return internal IP for all queries except queries 2 and 4 (which return valid):**

```bash
ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port 10053 -valid-for 2,4
```

**Combine with `-rebind-after` for fine-grained control:**

```bash
# Queries 1-2 return valid, query 3+ return internal, except query 4 returns valid
ssrf-dns -valid 1.1.1.1 -internal 127.0.0.1 -domain example.com -port 10053 -rebind-after 2 -valid-for 4
```

| Flags used | Default behavior | Overrides |
| :--- | :--- | :--- |
| `-internal-for` alone | All queries return valid IP | Listed indexes → internal |
| `-valid-for` alone | All queries return internal IP | Listed indexes → valid |
| Both without `-rebind-after` | All queries return internal IP (`rebind-after=0`) | Each list overrides accordingly |
| `-rebind-after N` + either/both | Standard rebind-after behavior | Listed indexes override the base |

Override evaluation order: `-valid-for` → `-internal-for` → rebind-after base logic.

**Validation rules:**
- Query indexes must be positive integers (≥ 1).
- The same index cannot appear in both `-internal-for` and `-valid-for`.
- `-random` cannot be combined with `-internal-for` or `-valid-for`.

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
      
      # Multiple records for the same domain
      _acme-challenge.example.com:
        - type: TXT
          value: "value1"
        - type: TXT
          value: "value2"
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
