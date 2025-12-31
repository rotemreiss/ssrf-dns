# url-sheriff SSRF Example

This directory contains a vulnerable Node.js application that uses `url-sheriff` for SSRF protection but is vulnerable to DNS rebinding (TOCTOU).

## Frameworks and Libraries

- **Framework**: [Express](https://expressjs.com/)
- **HTTP Client**: [node-fetch](https://github.com/node-fetch/node-fetch) - chosen because it performs its own DNS resolution, separate from `url-sheriff`'s check.
- **SSRF Protection**: [url-sheriff](https://github.com/manning-books/url-sheriff) - configured to block private IP ranges.

## Vulnerability: Time-of-Check Time-of-Use (TOCTOU)

The application validates the URL using `url-sheriff` which resolves the domain to an IP and checks if it's allowed. If allowed, the application then uses `node-fetch` to make the request.

Since `node-fetch` resolves the domain name again, an attacker can use a technique like DNS Rebinding where the domain resolves to a safe IP during the check (Time-of-Check) and to a private IP during the request (Time-of-Use).

## Exploitation

The server listens on port 3000.

**Endpoint**: `/`
**Parameter**: `url` (The target URL to fetch)

To exploit this, you need a domain that you control with a very short TTL (Time To Live).

1.  **First resolution (Check)**: Return a public, allowed IP (e.g., 1.2.3.4).
2.  **Second resolution (Use)**: Return a private, internal IP (e.g., 127.0.0.1).

**Example Request:**

```bash
curl "http://localhost:3000/?url=http://rebind-domain.example.com"
```
## Running with Docker

```bash
docker build -t url-sheriff .
docker run --dns DNS_SERVER_WITH_SHORT_TTL -p 3000:3000 url-sheriff
```

## Note on Local Testing & DNS Caching

If you are testing this locally (e.g., on macOS or Ubuntu), the exploit might fail because the operating system caches DNS responses.

-   **macOS**: Uses `mDNSResponder` which aggressively caches DNS queries, often ignoring short TTLs for performance.
-   **Ubuntu/Linux**: Often uses `systemd-resolved` which also has a local cache.

**Why this matters**:
The vulnerability relies on the DNS resolver returning a *different* IP address the second time it is queried (Time-of-Use). If the OS caches the first result (Time-of-Check), `node-fetch` will use the safe cached IP, and the attack will fail.

**Solution**:
Run the application inside a **Docker container**. The Alpine Linux image used in the Dockerfile uses `musl` libc, which **does not** cache DNS lookups by default, making the exploit reliable.
