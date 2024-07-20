package main

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

func sendHashResultToAPI(config Config, jwt *JWT, result *DirectoryHashResult) error {
	url := fmt.Sprintf("http://%s:%d/api/v1/hash-results", config.ApiEndpoint, config.Port)
	fmt.Printf("DEBUG: Preparing to send hash result to URL: %s\n", url)

	// Print some information about the result before encoding
	fmt.Printf("DEBUG: Result summary:\n")
	fmt.Printf("  Root Path: %s\n", result.RootPath)
	fmt.Printf("  Total Files: %d\n", result.TotalFiles)
	fmt.Printf("  Total Size: %d bytes\n", result.TotalSize)
	fmt.Printf("  Hashing Time: %.2f seconds\n", result.HashingTime)

	// Encode the result to JSON
	jsonData, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("error encoding result to JSON: %w", err)
	}

	var body []byte
	var contentEncoding string

	// Apply gzip compression if the JSON data is large
	if len(jsonData) > 1024 {
		var buf bytes.Buffer
		gzWriter := gzip.NewWriter(&buf)
		if _, err := gzWriter.Write(jsonData); err != nil {
			return fmt.Errorf("error compressing JSON data: %w", err)
		}
		gzWriter.Close()
		body = buf.Bytes()
		contentEncoding = "gzip"
		fmt.Printf("DEBUG: Compressed data size: %d bytes\n", len(body))
	} else {
		body = jsonData
		contentEncoding = "identity"
		fmt.Printf("DEBUG: Uncompressed data size: %d bytes\n", len(body))
	}

	// Make the authenticated request
	resp, err := makeAuthenticatedRequest(config, jwt, "POST", url, body, contentEncoding)
	if err != nil {
		return fmt.Errorf("error making authenticated request: %w", err)
	}
	defer resp.Body.Close()

	fmt.Printf("DEBUG: Response status: %s\n", resp.Status)
	fmt.Printf("DEBUG: Response headers:\n")
	for key, values := range resp.Header {
		for _, value := range values {
			fmt.Printf("  %s: %s\n", key, value)
		}
	}

	body, _ = io.ReadAll(resp.Body)
	fmt.Printf("DEBUG: Response body: %s\n", string(body))

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("API returned non-OK status: %d, body: %s", resp.StatusCode, string(body))
	}

	fmt.Println("Hash result successfully sent to API")
	return nil
}
