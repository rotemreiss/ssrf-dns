package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"math"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/miekg/dns"
)

// RecordState tracks the state of a domain
type RecordState struct {
	mu                 sync.Mutex
	queryCounts        map[string]int
	validIP            net.IP
	internalIP         net.IP
	logger             *log.Logger
	targetDomain       string
	upstream           string
	staticRecords      map[string][]RecordConfig
	delay              time.Duration
	rebindAfter        int
	randomMode         bool
	internalForIndexes map[int]bool
	validForIndexes    map[int]bool
}

func NewRecordState(validIP, internalIP net.IP, targetDomain string, upstream string, records map[string][]RecordConfig, delay time.Duration, rebindAfter int, randomMode bool, internalForIndexes, validForIndexes map[int]bool, logger *log.Logger) *RecordState {
	return &RecordState{
		queryCounts:        make(map[string]int),
		validIP:            validIP,
		internalIP:         internalIP,
		targetDomain:       targetDomain,
		upstream:           upstream,
		staticRecords:      records,
		delay:              delay,
		rebindAfter:        rebindAfter,
		randomMode:         randomMode,
		internalForIndexes: internalForIndexes,
		validForIndexes:    validForIndexes,
		logger:             logger,
	}
}

func (rs *RecordState) handleDNSRequest(w dns.ResponseWriter, r *dns.Msg) {
	msg := new(dns.Msg)
	msg.SetReply(r)
	msg.Authoritative = true

	for _, question := range r.Question {
		domain := question.Name
		cleanDomain := strings.ToLower(strings.TrimSuffix(domain, "."))
		var rr []dns.RR

		// 1. Check Static Records
		if records, ok := rs.staticRecords[cleanDomain]; ok {
			for _, record := range records {
				hdr := dns.RR_Header{
					Name:  question.Name,
					Class: dns.ClassINET,
					Ttl:   300,
				}

				// Map string type to dns.Type
				var targetType uint16
				switch record.Type {
				case "A":
					targetType = dns.TypeA
				case "TXT":
					targetType = dns.TypeTXT
				case "CNAME":
					targetType = dns.TypeCNAME
				}

				if question.Qtype == targetType {
					hdr.Rrtype = targetType
					added := false
					switch record.Type {
					case "A":
						ip := net.ParseIP(record.Value)
						if ip != nil {
							rr = append(rr, &dns.A{Hdr: hdr, A: ip})
							added = true
						} else {
							rs.logger.Printf("Error parsing static A record IP: %s", record.Value)
						}
					case "TXT":
						rr = append(rr, &dns.TXT{Hdr: hdr, Txt: []string{record.Value}})
						added = true
					case "CNAME":
						rr = append(rr, &dns.CNAME{Hdr: hdr, Target: dns.Fqdn(record.Value)})
						added = true
					}

					if added {
						remoteAddr, _, _ := net.SplitHostPort(w.RemoteAddr().String())
						rs.logger.Printf("Src: %s, Domain: %s, Action: STATIC, Type: %s, Value: %s", remoteAddr, domain, record.Type, record.Value)
					}
				}
			}
		}

		// 2. If no static record found (or type mismatch), proceed with standard logic ONLY for A records
		if len(rr) == 0 && question.Qtype == dns.TypeA {
			// Check if it matches our target domain (or subdomain)
			isMatch := strings.HasSuffix(cleanDomain, rs.targetDomain)
			if !isMatch {
				// Proxy to upstream
				c := new(dns.Client)
				in, _, err := c.Exchange(r, rs.upstream)
				if err != nil {
					rs.logger.Printf("Proxy Error: %v", err)
					continue
				}
				w.WriteMsg(in)
				rs.logger.Printf("Src: %s, Domain: %s, Action: PROXY", w.RemoteAddr(), domain)
				return
			}

			var ipToReturn net.IP
			var stateStr string

			if rs.randomMode {
				// rbndr-style random resolution: use LSB of DNS query ID
				// Since query IDs are pseudo-random, this gives ~50/50 distribution
				if r.Id&1 == 0 {
					ipToReturn = rs.validIP
					stateStr = "RANDOM_VALID"
				} else {
					ipToReturn = rs.internalIP
					stateStr = "RANDOM_INTERNAL"
				}
			} else {
				rs.mu.Lock()
				rs.queryCounts[cleanDomain]++
				count := rs.queryCounts[cleanDomain]
				rs.mu.Unlock()

				if rs.validForIndexes[count] {
					ipToReturn = rs.validIP
					stateStr = "OVERRIDE_VALID"
				} else if rs.internalForIndexes[count] {
					ipToReturn = rs.internalIP
					stateStr = "OVERRIDE_INTERNAL"
				} else if count > rs.rebindAfter {
					ipToReturn = rs.internalIP
					stateStr = "RETURNING"
				} else {
					ipToReturn = rs.validIP
					stateStr = "NEW"
				}
			}

			if rs.delay > 0 {
				time.Sleep(rs.delay)
			}

			rr = append(rr, &dns.A{
				Hdr: dns.RR_Header{
					Name:   question.Name,
					Rrtype: dns.TypeA,
					Class:  dns.ClassINET,
					Ttl:    0, // No caching to ensure rebind works
				},
				A: ipToReturn,
			})

			// Log the rebind request
			remoteAddr, _, _ := net.SplitHostPort(w.RemoteAddr().String())
			rs.logger.Printf("Src: %s, Domain: %s, Resp: %s, State: %s",
				remoteAddr, domain, ipToReturn.String(), stateStr)
		}

		if len(rr) > 0 {
			msg.Answer = append(msg.Answer, rr...)
		}
	}

	w.WriteMsg(msg)
}

const Version = "0.11.0"

func parseIndexList(s string) (map[int]bool, error) {
	if s == "" {
		return nil, nil
	}
	result := make(map[int]bool)
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		n, err := strconv.Atoi(part)
		if err != nil {
			return nil, fmt.Errorf("invalid index %q: must be a positive integer", part)
		}
		if n < 1 {
			return nil, fmt.Errorf("invalid index %d: must be >= 1", n)
		}
		result[n] = true
	}
	if len(result) == 0 {
		return nil, nil
	}
	return result, nil
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "version" {
		fmt.Printf("ssrf-dns version %s\n", Version)
		os.Exit(0)
	}

	validIPStr := flag.String("valid", "", "Valid IP address to return on first request")
	internalIPStr := flag.String("internal", "", "Internal IP address to return on subsequent requests")
	logFileStr := flag.String("log", "", "Path to log file (default: stdout)")
	portStr := flag.String("port", "53", "UDP port to listen on")
	targetDomain := flag.String("domain", "", "Target domain (mandatory) - queries for this domain (and subdomains) will be rebinded, others proxied")
	upstreamDNS := flag.String("upstream", "8.8.8.8:53", "Upstream DNS server for non-matching domains")
	recordsFile := flag.String("records", "", "Path to YAML file with static records")
	delayMs := flag.Int("delay", 0, "Delay in milliseconds before replying to dynamic record queries")
	rebindAfter := flag.Int("rebind-after", 1, "Number of queries to return valid IP before switching to internal IP")
	randomMode := flag.Bool("random", false, "Randomly return valid or internal IP using DNS query ID (rbndr-style)")
	internalForStr := flag.String("internal-for", "", "Comma-separated query indexes that return internal IP (default: all other queries return valid)")
	validForStr := flag.String("valid-for", "", "Comma-separated query indexes that return valid IP (default: all other queries return internal)")
	flag.Parse()

	// Check if rebind-after was explicitly set
	rebindAfterExplicit := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == "rebind-after" {
			rebindAfterExplicit = true
		}
	})

	if *validIPStr == "" || *internalIPStr == "" || *targetDomain == "" {
		fmt.Println("Error: -valid, -internal and -domain flags are required")
		flag.Usage()
		os.Exit(1)
	}

	// Parse index lists
	internalForIndexes, err := parseIndexList(*internalForStr)
	if err != nil {
		fmt.Printf("Error in -internal-for: %v\n", err)
		os.Exit(1)
	}
	validForIndexes, err := parseIndexList(*validForStr)
	if err != nil {
		fmt.Printf("Error in -valid-for: %v\n", err)
		os.Exit(1)
	}

	hasInternalFor := len(internalForIndexes) > 0
	hasValidFor := len(validForIndexes) > 0

	// Validate flag combinations
	if *randomMode {
		if rebindAfterExplicit {
			fmt.Println("Error: -random and -rebind-after cannot be used together")
			flag.Usage()
			os.Exit(1)
		}
		if hasInternalFor || hasValidFor {
			fmt.Println("Error: -random cannot be used with -internal-for or -valid-for")
			flag.Usage()
			os.Exit(1)
		}
	}

	// Check for overlapping indexes between internal-for and valid-for
	if hasInternalFor && hasValidFor {
		for idx := range internalForIndexes {
			if validForIndexes[idx] {
				fmt.Printf("Error: query index %d appears in both -internal-for and -valid-for\n", idx)
				os.Exit(1)
			}
		}
	}

	// Adjust rebindAfter when not explicitly set
	if !rebindAfterExplicit {
		if hasInternalFor && !hasValidFor {
			// internal-for alone: all queries return valid by default
			*rebindAfter = math.MaxInt32
		} else if hasValidFor {
			// valid-for (with or without internal-for): all queries return internal by default
			*rebindAfter = 0
		}
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

	// Load static records
	records, err := LoadStaticRecords(*recordsFile)
	if err != nil {
		fmt.Printf("Error loading static records: %v\n", err)
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

	recordState := NewRecordState(validIP, internalIP, *targetDomain, *upstreamDNS, records, time.Duration(*delayMs)*time.Millisecond, *rebindAfter, *randomMode, internalForIndexes, validForIndexes, logger)

	// DNS server handler
	dns.HandleFunc(".", recordState.handleDNSRequest)

	server := &dns.Server{Addr: ":" + *portStr, Net: "udp"}

	fmt.Printf("Starting Rebind DNS Server on port %s\n", *portStr)
	fmt.Printf("Target Domain: %s (and subdomains)\n", *targetDomain)
	if len(records) > 0 {
		fmt.Printf("Loaded %d static records\n", len(records))
	}
	if *randomMode {
		fmt.Printf("Mode: Random (rbndr-style, based on DNS query ID LSB)\n")
	} else if *rebindAfter >= math.MaxInt32 {
		fmt.Printf("Mode: All queries return valid IP by default\n")
	} else if *rebindAfter == 0 {
		fmt.Printf("Mode: All queries return internal IP by default\n")
	} else {
		fmt.Printf("Mode: Sequential (rebind after %d queries)\n", *rebindAfter)
	}
	if hasInternalFor {
		fmt.Printf("Override: Queries [%s] return internal IP\n", *internalForStr)
	}
	if hasValidFor {
		fmt.Printf("Override: Queries [%s] return valid IP\n", *validForStr)
	}
	fmt.Printf("Valid IP: %s\n", validIP.String())
	fmt.Printf("Internal IP: %s\n", internalIP.String())

	if err := server.ListenAndServe(); err != nil {
		fmt.Printf("Failed to start server: %s\n", err.Error())
		os.Exit(1)
	}
}
