package geo

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/oschwald/geoip2-golang"
)

var (
	dbReader *geoip2.Reader
	dbMu     sync.RWMutex
	dbLoaded bool
)

// InitDB initializes the GeoIP database from the assets folder
func InitDB() error {
	dbMu.Lock()
	defer dbMu.Unlock()

	if dbLoaded {
		return nil
	}

	// Try to find the database file
	dbPath := findDatabasePath()
	if dbPath == "" {
		return fmt.Errorf("GeoIP database not found")
	}

	db, err := geoip2.Open(dbPath)
	if err != nil {
		return fmt.Errorf("failed to open GeoIP database: %w", err)
	}

	dbReader = db
	dbLoaded = true
	return nil
}

// findDatabasePath searches for the GeoIP database file
func findDatabasePath() string {
	// Common database filenames
	dbFiles := []string{
		"GeoLite2-Country.mmdb",
		"GeoLite2-ASN.mmdb",
		"GeoIP2-Country.mmdb",
	}

	// Search in assets folder relative to executable
	execPath, err := os.Executable()
	if err == nil {
		execDir := filepath.Dir(execPath)
		for _, dbFile := range dbFiles {
			// Check assets folder
			assetsPath := filepath.Join(execDir, "assets", dbFile)
			if _, err := os.Stat(assetsPath); err == nil {
				return assetsPath
			}
			// Check current directory
			currentPath := filepath.Join(execDir, dbFile)
			if _, err := os.Stat(currentPath); err == nil {
				return currentPath
			}
		}
	}

	// Search relative to working directory
	for _, dbFile := range dbFiles {
		assetsPath := filepath.Join("assets", dbFile)
		if _, err := os.Stat(assetsPath); err == nil {
			return assetsPath
		}
	}

	return ""
}

// GetCountryCode returns the ISO 3166-1 alpha-2 country code for an IP address
func GetCountryCode(ip string) (string, error) {
	// Initialize database if not loaded
	if err := InitDB(); err != nil {
		// Fallback to simple lookup if database not available
		return simpleLookup(ip), nil
	}

	// Parse IP address
	parsedIP := net.ParseIP(ip)
	if parsedIP == nil {
		// Try to extract IP from host:port format
		host, _, err := net.SplitHostPort(ip)
		if err != nil {
			return "", fmt.Errorf("invalid IP address: %s", ip)
		}
		parsedIP = net.ParseIP(host)
		if parsedIP == nil {
			return "", fmt.Errorf("invalid IP address: %s", ip)
		}
	}

	dbMu.RLock()
	defer dbMu.RUnlock()

	if dbReader == nil {
		return simpleLookup(ip), nil
	}

	record, err := dbReader.Country(parsedIP)
	if err != nil {
		return "UNKNOWN", nil
	}

	if record.Country.IsoCode != "" {
		return record.Country.IsoCode, nil
	}

	return "UNKNOWN", nil
}

// simpleLookup is a fallback when GeoIP database is not available
func simpleLookup(ip string) string {
	parsedIP := net.ParseIP(ip)
	if parsedIP == nil {
		host, _, err := net.SplitHostPort(ip)
		if err != nil {
			return "UNKNOWN"
		}
		parsedIP = net.ParseIP(host)
		if parsedIP == nil {
			return "UNKNOWN"
		}
	}

	if parsedIP.IsLoopback() {
		return "LOCAL"
	}
	if parsedIP.IsPrivate() {
		return "LOCAL"
	}

	return "UNKNOWN"
}

// GetCountryCodeFromURL extracts IP from mimic URL and returns country code
func GetCountryCodeFromURL(mimicURL string) string {
	// Extract IP from mimic://uuid@ip:port?... format
	atIdx := strings.Index(mimicURL, "@")
	if atIdx == -1 {
		return "UNKNOWN"
	}

	afterAt := mimicURL[atIdx+1:]

	// Find the end of host:port (before ? or /)
	endIdx := strings.IndexAny(afterAt, "?/")
	if endIdx == -1 {
		endIdx = len(afterAt)
	}

	hostPort := afterAt[:endIdx]

	// Extract just the IP (remove port)
	host, _, err := net.SplitHostPort(hostPort)
	if err != nil {
		// Might be just IP without port
		host = hostPort
	}

	country, err := GetCountryCode(host)
	if err != nil {
		return "UNKNOWN"
	}

	return country
}

// CountryCodeToFlag converts ISO 3166-1 alpha-2 country code to flag emoji
func CountryCodeToFlag(countryCode string) string {
	if countryCode == "LOCAL" {
		return "🏠"
	}
	if countryCode == "UNKNOWN" || countryCode == "" {
		return "🌐"
	}

	countryCode = strings.ToUpper(countryCode)

	// Special cases
	if countryCode == "EU" {
		return "🇪🇺"
	}
	if countryCode == "UN" {
		return "🇺🇳"
	}

	// Convert to flag emoji using Unicode regional indicators
	var flag strings.Builder
	for _, char := range countryCode {
		if char >= 'A' && char <= 'Z' {
			// Convert to regional indicator (U+1F1E6 to U+1F1FF)
			flag.WriteRune(char + 0x1F1E5)
		}
	}

	result := flag.String()
	if result == "" {
		return "🌐"
	}

	return result
}

// GetFlagForURL returns flag emoji for a mimic URL
func GetFlagForURL(mimicURL string) string {
	countryCode := GetCountryCodeFromURL(mimicURL)
	return CountryCodeToFlag(countryCode)
}

// GetCountryInfo returns detailed country information for an IP
func GetCountryInfo(ip string) (countryCode, countryName string, err error) {
	if err := InitDB(); err != nil {
		return "UNKNOWN", "Unknown", nil
	}

	parsedIP := net.ParseIP(ip)
	if parsedIP == nil {
		host, _, err := net.SplitHostPort(ip)
		if err != nil {
			return "UNKNOWN", "Unknown", fmt.Errorf("invalid IP address: %s", ip)
		}
		parsedIP = net.ParseIP(host)
		if parsedIP == nil {
			return "UNKNOWN", "Unknown", fmt.Errorf("invalid IP address: %s", ip)
		}
	}

	dbMu.RLock()
	defer dbMu.RUnlock()

	if dbReader == nil {
		return "UNKNOWN", "Unknown", nil
	}

	record, err := dbReader.Country(parsedIP)
	if err != nil {
		return "UNKNOWN", "Unknown", nil
	}

	countryCode = record.Country.IsoCode
	if countryCode == "" {
		countryCode = "UNKNOWN"
	}

	// Get country name in English if available
	if record.Country.Names != nil && record.Country.Names["en"] != "" {
		countryName = record.Country.Names["en"]
	} else {
		countryName = "Unknown"
	}

	return countryCode, countryName, nil
}

// CloseDB closes the GeoIP database
func CloseDB() error {
	dbMu.Lock()
	defer dbMu.Unlock()

	if dbReader != nil {
		err := dbReader.Close()
		dbReader = nil
		dbLoaded = false
		return err
	}
	return nil
}
