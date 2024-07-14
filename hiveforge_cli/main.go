package main

import (
	"bytes"
	// "crypto/hmac"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/user"
	"path/filepath"
	"time"
	"github.com/golang-jwt/jwt/v4"
)

type JWT struct {
    Token     string    `json:"token"`
    ExpiresAt time.Time `json:"expires_at"`
    IssuedAt  time.Time `json:"issued_at"`
}

// Config represents the application configuration
type Config struct {
	ApiEndpoint string `json:"api_endpoint"`
	Port        int    `json:"port"`
	CacertFile  string `json:"cacert_file"`
	Debug       bool   `json:"debug"`
	ApiKey      string `json:"api_key"`
	MasterKey   string `json:"master_key"`
}

type ApiKey struct {
	Key 	string `json:"key"`
	Type    string `json:"type"`
	Name    string `json:"name"`
	Description string `json:"description"`
}

// Job represents a job retrieved from the API
type Job struct {
	Id                   int       `json:"id"`
	Name                 string    `json:"name"`
	Description          string    `json:"description"`
	Status               string    `json:"status"`
	RequestedCapabilities []string `json:"requested_capabilities"`
	InsertedAt           string    `json:"inserted_at"`
	UpdatedAt            string    `json:"updated_at"`
}

type Agent struct {
    ID         			int       `json:"id"`
    Name       			string    `json:"name"`
    AgentID   			string    `json:"agent_id"`
    Capabilities 		[]string  `json:"capabilities"`
    Status     			string    `json:"status"`
    LastHeartbeat 		string 	  `json:"last_heartbeat"`
    InsertedAt 			string    `json:"inserted_at"`
    UpdatedAt  			string    `json:"updated_at"`
}

// loadConfig loads the configuration from a file
func loadConfig() (Config, *JWT, error) {
    configPaths := []string{
        "config.json",
    }

    jwtPaths := []string{
        "jwt.json",
    }

    user, err := user.Current()
    if err != nil {
        return Config{}, nil, err
    }

    homeConfigPath := filepath.Join(user.HomeDir, ".hiveforge", "config.json")
    homeJWTPath := filepath.Join(user.HomeDir, ".hiveforge", "jwt.json")
    configPaths = append(configPaths, homeConfigPath)
    jwtPaths = append(jwtPaths, homeJWTPath)

    var config Config
    var jwt JWT

    for _, path := range configPaths {
        if _, err := os.Stat(path); err == nil {
            file, err := os.ReadFile(path)
            if err != nil {
                return Config{}, nil, err
            }

            err = json.Unmarshal(file, &config)
            if err != nil {
                return Config{}, nil, err
            }

            break
        }
    }

    for _, path := range jwtPaths {
        if _, err := os.Stat(path); err == nil {
            file, err := os.ReadFile(path)
            if err != nil {
                return config, nil, err
            }

            err = json.Unmarshal(file, &jwt)
            if err != nil {
                return config, nil, err
            }

            return config, &jwt, nil
        }
    }

    return config, nil, nil
}

func authenticateAndGetJWT(config Config) (*JWT, error) {
	var keyToUse string
	var keyHash string

	if config.MasterKey != "" {
		keyToUse = config.MasterKey
		keyHash = hashKey(config.MasterKey)
	} else if config.ApiKey != "" {
		keyToUse = config.ApiKey
		keyHash = hashKey(config.ApiKey)
	} else {
		return nil, errors.New("neither master key nor API key is set")
	}

	// Step 1: Request a challenge
	challengeURL := fmt.Sprintf("http://%s:%d/api/v1/auth/challenge", config.ApiEndpoint, config.Port)
	req, err := http.NewRequest("GET", challengeURL, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("x-api-key-id", keyHash) // Send the BLAKE3 hash

    fmt.Printf("DEBUG: Sending request to: %s\n", challengeURL)
    fmt.Printf("DEBUG: Request headers: %v\n", req.Header)

    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    fmt.Printf("DEBUG: Response status: %s\n", resp.Status)
    fmt.Printf("DEBUG: Response headers: %v\n", resp.Header)

    if resp.StatusCode != http.StatusOK {
        return nil, fmt.Errorf("failed to get challenge: %s", resp.Status)
    }

    var challengeResp struct {
        Challenge string `json:"challenge"`
    }
    if err := json.NewDecoder(resp.Body).Decode(&challengeResp); err != nil {
        return nil, err
    }

    // Step 2: Solve the challenge
	challengeResponse := solveChallenge(challengeResp.Challenge, keyToUse)
	fmt.Printf("DEBUG: Challenge: %s\n", challengeResp.Challenge)
    fmt.Printf("DEBUG: Challenge Response: %s\n", challengeResponse)

    // Only use the first 8 characters of the challenge response
    shortChallengeResponse := challengeResponse[:8]
    fmt.Printf("DEBUG: Short Challenge Response: %s\n", shortChallengeResponse)

    // Step 3: Submit the challenge response
	authURL := fmt.Sprintf("http://%s:%d/api/v1/auth/verify", config.ApiEndpoint, config.Port)
	challengeResponseJSON, _ := json.Marshal(map[string]string{"challenge_response": challengeResponse})
	authReq, err := http.NewRequest("POST", authURL, bytes.NewBuffer(challengeResponseJSON))
	if err != nil {
		return nil, err
	}
	authReq.Header.Set("x-api-key-id", keyHash)
	authReq.Header.Set("Content-Type", "application/json")

    fmt.Printf("DEBUG: Sending verification request to: %s\n", authURL)
    fmt.Printf("DEBUG: Verification request headers: %v\n", authReq.Header)
    fmt.Printf("DEBUG: Verification request body: %s\n", string(challengeResponseJSON))


    authResp, err := http.DefaultClient.Do(authReq)
    if err != nil {
        return nil, err
    }
    defer authResp.Body.Close()

    fmt.Printf("DEBUG: Verification response status: %s\n", authResp.Status)
    fmt.Printf("DEBUG: Verification response headers: %v\n", authResp.Header)

    body, _ := io.ReadAll(authResp.Body)
    fmt.Printf("DEBUG: Verification response body: %s\n", string(body))

    if authResp.StatusCode != http.StatusOK {
        return nil, fmt.Errorf("authentication failed: %s", authResp.Status)
    }

    var tokenResponse struct {
        Token string `json:"token"`
    }
    if err := json.NewDecoder(bytes.NewReader(body)).Decode(&tokenResponse); err != nil {
        return nil, err
    }

    // Parse the JWT to extract issued and expiration times
    token, _, err := new(jwt.Parser).ParseUnverified(tokenResponse.Token, jwt.MapClaims{})
    if err != nil {
        return nil, fmt.Errorf("failed to parse JWT: %w", err)
    }

    claims, ok := token.Claims.(jwt.MapClaims)
    if !ok {
        return nil, fmt.Errorf("invalid token claims")
    }

    exp, ok := claims["exp"].(float64)
    if !ok {
        return nil, fmt.Errorf("invalid expiration claim")
    }

    iat, ok := claims["iat"].(float64)
    if !ok {
        return nil, fmt.Errorf("invalid issued at claim")
    }

    jwt := &JWT{
        Token:     tokenResponse.Token,
        ExpiresAt: time.Unix(int64(exp), 0),
        IssuedAt:  time.Unix(int64(iat), 0),
    }

    return jwt, nil
}



func storeJWT(jwt *JWT) error {
    home, err := os.UserHomeDir()
    if err != nil {
        return err
    }

    jwtDir := filepath.Join(home, ".hiveforge")
    if err := os.MkdirAll(jwtDir, 0700); err != nil {
        return err
    }

    jwtFile := filepath.Join(jwtDir, "jwt.json")
    file, err := os.Create(jwtFile)
    if err != nil {
        return err
    }
    defer file.Close()

    return json.NewEncoder(file).Encode(jwt)
}

func getStoredJWT() (*JWT, error) {
    home, err := os.UserHomeDir()
    if err != nil {
        return nil, err
    }

    jwtFile := filepath.Join(home, ".hiveforge", "jwt.json")
    file, err := os.Open(jwtFile)
    if err != nil {
        return nil, err
    }
    defer file.Close()

    var jwt JWT
    if err := json.NewDecoder(file).Decode(&jwt); err != nil {
        return nil, err
    }

    return &jwt, nil
}
// func generateSignature(apiKey, nonce string, body []byte) string {
// 	transactionKey := hmac.New(sha256.New, []byte(apiKey))
// 	transactionKey.Write([]byte("TRANSACTION" + nonce))

// 	signature := hmac.New(sha256.New, transactionKey.Sum(nil))
// 	signature.Write(body)

// 	return base64.StdEncoding.EncodeToString(signature.Sum(nil))
// }

func generateApiKey(config Config, jwt *JWT, keyType, name, description string) (*ApiKey, error) {
    url := fmt.Sprintf("http://%s:%d/api/v1/api_keys/generate", config.ApiEndpoint, config.Port)

    requestBody, err := json.Marshal(map[string]string{
        "type": keyType,
        "name": name,
        "description": description,
    })
    if err != nil {
        return nil, err
    }

    resp, err := makeAuthenticatedRequest(config, jwt, "POST", url, requestBody)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, err
    }

    if config.Debug {
        fmt.Printf("Response Status: %s\n", resp.Status)
        fmt.Printf("Response Headers: %v\n", resp.Header)
        fmt.Printf("Response Body: %s\n", string(body))
    }

    if resp.StatusCode != http.StatusCreated {
        return nil, fmt.Errorf("failed to generate API key: %s", string(body))
    }

    var apiKey ApiKey
    err = json.Unmarshal(body, &apiKey)
    if err != nil {
        return nil, err
    }

    return &apiKey, nil
}

func printRequest(req *http.Request, body []byte) {
    fmt.Printf("Request Method: %s\n", req.Method)
    fmt.Printf("Request URL: %s\n", req.URL.String())
    fmt.Printf("Request Headers: %v\n", req.Header)
    fmt.Printf("Request Body: %s\n", string(body))
}

// Use the JWT to make an authenticated request to the API
func makeAuthenticatedRequest(config Config, jwt *JWT, method, url string, body []byte) (*http.Response, error) {
    needsRefresh := func(jwt *JWT) bool {
        if jwt == nil {
            return true
        }
        // Check if we're more than 2/3 through the validity duration
        return time.Now().After(jwt.ExpiresAt.Add(-1 * jwt.ExpiresAt.Sub(jwt.IssuedAt) / 3))
    }

    if needsRefresh(jwt) {
        newJWT, err := authenticateAndGetJWT(config)
        if err != nil {
            return nil, fmt.Errorf("failed to refresh JWT: %w", err)
        }
        *jwt = *newJWT
        if err := storeJWT(jwt); err != nil {
            return nil, fmt.Errorf("failed to store refreshed JWT: %w", err)
        }
        if config.Debug {
            fmt.Println("JWT refreshed proactively")
        }
    }

    req, err := http.NewRequest(method, url, bytes.NewBuffer(body))
    if err != nil {
        return nil, err
    }

    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", jwt.Token))

    if config.Debug {
        printRequest(req, body)
    }

    client := &http.Client{}
    return client.Do(req)
}

func listApiKeys(apiEndpoint string, port int, jwt *JWT) ([]ApiKey, error) {
	url := fmt.Sprintf("http://%s:%d/api/v1/api_keys", apiEndpoint, port)

	resp, err := makeAuthenticatedRequest(Config{ApiEndpoint: apiEndpoint, Port: port}, jwt, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to make authenticated request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to list API keys: %s", string(body))
	}

	var apiKeys []ApiKey
	err = json.Unmarshal(body, &apiKeys)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal API keys: %w", err)
	}

	return apiKeys, nil
}

func displayApiKeys(apiKeys []ApiKey) {
	headers := []string{"Key", "Type", "Name", "Description"}
	maxWidths := make([]int, len(headers))
	copy(maxWidths, []int{36, 12, 20, 30}) // Minimum widths for each header

	for _, key := range apiKeys {
		maxWidths[0] = max(maxWidths[0], len(key.Key))
		maxWidths[1] = max(maxWidths[1], len(key.Type))
		maxWidths[2] = max(maxWidths[2], len(key.Name))
		maxWidths[3] = max(maxWidths[3], len(key.Description))
	}

	printSeparator(maxWidths)
	printRow(headers, maxWidths)
	printSeparator(maxWidths)

	for _, key := range apiKeys {
		row := []string{
			key.Key,
			key.Type,
			key.Name,
			key.Description,
		}
		printRow(row, maxWidths)
	}

	printSeparator(maxWidths)
}

// getJobs retrieves all jobs from the API
func getJobs(apiEndpoint string, port int, debug bool, jwt *JWT) ([]Job, error) {
    url := fmt.Sprintf("http://%s:%d/api/v1/jobs", apiEndpoint, port)
    fmt.Printf("Requesting URL: %s\n", url)  // Debug print
    fmt.Printf("JWT: %s\n", jwt.Token)  // Debug print
    resp, err := makeAuthenticatedRequest(Config{ApiEndpoint: apiEndpoint, Port: port}, jwt, "GET", url, nil)
    if err != nil {
        return nil, fmt.Errorf("HTTP request failed: %v", err)
    }
    defer resp.Body.Close()

    fmt.Printf("HTTP Status: %d\n", resp.StatusCode)  // Debug print

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, fmt.Errorf("failed to read response body: %v", err)
    }

    // Print the raw API response
    if debug {
	    fmt.Println("Raw API response:")
	    fmt.Println(string(body))
    }

    var jobs []Job
    err = json.Unmarshal(body, &jobs)
    if err != nil {
        fmt.Println("Failed to unmarshal JSON. Raw response:")
        fmt.Println(string(body))
        return nil, fmt.Errorf("failed to parse JSON: %v", err)
    }

    fmt.Printf("Number of jobs retrieved: %d\n", len(jobs))  // Debug print

    return jobs, nil
}

func describeJob(apiEndpoint string, port int, debug bool, id string, jwt *JWT) error {
    url := fmt.Sprintf("http://%s:%d/api/v1/jobs/%s", apiEndpoint, port, id)
    fmt.Printf("Requesting URL: %s\n", url)
    resp, err := makeAuthenticatedRequest(Config{ApiEndpoint: apiEndpoint, Port: port}, jwt, "GET", url, nil)

    if err != nil {
        return fmt.Errorf("HTTP request failed: %v", err)
    }
    defer resp.Body.Close()

    fmt.Printf("HTTP Status: %d\n", resp.StatusCode)

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return fmt.Errorf("failed to read response body: %v", err)
    }

    if resp.StatusCode != http.StatusOK {
        return fmt.Errorf("API returned non-OK status: %d, body: %s", resp.StatusCode, string(body))
    }

    // Pretty print the JSON
    var prettyJSON bytes.Buffer
    err = json.Indent(&prettyJSON, body, "", "  ")
    if err != nil {
        return fmt.Errorf("failed to pretty print JSON: %v", err)
    }

    fmt.Println(prettyJSON.String())
    return nil
}

// displayJobs displays jobs in a formatted table
func displayJobs(jobs []Job) {
	headers := []string{"ID", "Name", "Status", "Inserted At", "Updated At"}
	maxWidths := make([]int, len(headers))
	copy(maxWidths, []int{2, 4, 6, 11, 10}) // Minimum widths for each header

	for _, job := range jobs {
		maxWidths[0] = max(maxWidths[0], len(fmt.Sprint(job.Id)))
		maxWidths[1] = max(maxWidths[1], len(job.Name))
		maxWidths[2] = max(maxWidths[2], len(job.Status))
		maxWidths[3] = max(maxWidths[3], len(job.InsertedAt))
		maxWidths[4] = max(maxWidths[4], len(job.UpdatedAt))
	}

	printSeparator(maxWidths)
	printRow(headers, maxWidths)
	printSeparator(maxWidths)

	for _, job := range jobs {
		row := []string{
			fmt.Sprint(job.Id),
			job.Name,
			job.Status,
			job.InsertedAt,
			job.UpdatedAt,
		}
		printRow(row, maxWidths)
	}

	printSeparator(maxWidths)
}

// max returns the maximum of two integers
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// printSeparator prints a table row separator
func printSeparator(widths []int) {
	fmt.Print("+")
	for _, width := range widths {
		fmt.Print("-")
		for i := 0; i < width; i++ {
			fmt.Print("-")
		}
		fmt.Print("-+")
	}
	fmt.Println()
}

// printRow prints a row of the table
func printRow(row []string, widths []int) {
	fmt.Print("|")
	for i, col := range row {
		fmt.Printf(" %-*s |", widths[i], col)
	}
	fmt.Println()
}

func createJob(apiEndpoint string, port int, debug bool, jsonFilePath string, jwt *JWT) error {
	// Read the JSON file
	jsonData, err := os.ReadFile(jsonFilePath)
	if err != nil {
		return fmt.Errorf("error reading JSON file: %w", err)
	}

	// Validate JSON
	var job map[string]interface{}
	if err := json.Unmarshal(jsonData, &job); err != nil {
		return fmt.Errorf("invalid JSON: %w", err)
	}

	// Encode the JSON in base64
	encodedJob := base64.StdEncoding.EncodeToString(jsonData)
	requestBody := []byte(fmt.Sprintf(`{"body":"%s"}`, encodedJob))

	url := fmt.Sprintf("http://%s:%d/api/v1/jobs", apiEndpoint, port)

	resp, err := makeAuthenticatedRequest(Config{ApiEndpoint: apiEndpoint, Port: port}, jwt, "POST", url, requestBody)
	if err != nil {
		return fmt.Errorf("failed to make authenticated request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body: %w", err)
	}

	if debug {
		fmt.Println("Raw API response:")
		fmt.Println(string(body))
	}

	if resp.StatusCode != http.StatusCreated {
		return fmt.Errorf("failed to create job (status %d): %s", resp.StatusCode, string(body))
	}

	fmt.Println("Job created successfully")
	return nil
}

func getAgents(config Config, jwt *JWT) ([]Agent, error) {
    url := fmt.Sprintf("http://%s:%d/api/v1/agents", config.ApiEndpoint, config.Port)

    resp, err := makeAuthenticatedRequest(config, jwt, "GET", url, nil)
    if err != nil {
        return nil, fmt.Errorf("failed to make authenticated request: %w", err)
    }
    defer resp.Body.Close()

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, fmt.Errorf("failed to read response body: %w", err)
    }

    if config.Debug {
        fmt.Println("Raw API response:")
        fmt.Println(string(body))
    }

    var agents []Agent
    err = json.Unmarshal(body, &agents)
    if err != nil {
        return nil, fmt.Errorf("failed to unmarshal response: %w", err)
    }

    return agents, nil
}

func getAgent(config Config, jwt *JWT, id string) (*Agent, error) {
    url := fmt.Sprintf("http://%s:%d/api/v1/agents/%s", config.ApiEndpoint, config.Port, id)
    resp, err := makeAuthenticatedRequest(config, jwt, "GET", url, nil)

    if err != nil {
        return nil, fmt.Errorf("failed to make authenticated request: %w", err)
    }

    defer resp.Body.Close()

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, fmt.Errorf("failed to read response body: %w", err)
    }

    if config.Debug {
        fmt.Println("Raw API response:")
        fmt.Println(string(body))
    }

    var agent Agent
    err = json.Unmarshal(body, &agent)
    if err != nil {
        return nil, fmt.Errorf("failed to unmarshal JSON: %w", err)
    }

    return &agent, nil
}

func displayAgents(agents []Agent) {
    headers := []string{"ID", "Name", "Agent ID", "Status", "Last Heartbeat"}
    maxWidths := make([]int, len(headers))
    copy(maxWidths, []int{2, 4, 8, 6, 14})

    for _, agent := range agents {
        maxWidths[0] = max(maxWidths[0], len(fmt.Sprint(agent.ID)))
        maxWidths[1] = max(maxWidths[1], len(agent.Name))
        maxWidths[2] = max(maxWidths[2], len(agent.AgentID))
        maxWidths[3] = max(maxWidths[3], len(agent.Status))
        if agent.LastHeartbeat != "" {
            maxWidths[4] = max(maxWidths[4], len(agent.LastHeartbeat))
        }
    }

    printSeparator(maxWidths)
    printRow(headers, maxWidths)
    printSeparator(maxWidths)

    for _, agent := range agents {
        lastHeartbeat := ""
        if agent.LastHeartbeat != "" {
            lastHeartbeat = agent.LastHeartbeat
        }
        row := []string{
            fmt.Sprint(agent.ID),
            agent.Name,
            agent.AgentID,
            agent.Status,
            lastHeartbeat,
        }
        printRow(row, maxWidths)
    }

    printSeparator(maxWidths)
}

func main() {
    debug := flag.Bool("debug", false, "Enable debug mode")
    flag.Parse()

    args := flag.Args()
    if len(args) < 1 {
        printUsage()
        return
    }

    config, jwt, err := loadConfig()
    if err != nil {
        fmt.Println("Error loading config:", err)
        return
    }
    config.Debug = *debug

    if config.Debug {
        fmt.Println("Debug mode is enabled")
    }

    if config.MasterKey == "" && config.ApiKey == "" {
        fmt.Println("Error: Neither master key nor API key is set in the configuration. At least one is required.")
        return
    }

    switch args[0] {
    case "authenticate":
        handleAuthenticate(config)
    case "get":
        handleGet(args[1:], config, jwt)
    case "create":
        handleCreate(args[1:], config, jwt)
    case "describe":
        handleDescribe(args[1:], config, jwt)
    case "generate-key":
        handleGenerateKey(args[1:], config, jwt)
    case "list-keys":
        handleListKeys(config, jwt)
    default:
        fmt.Println("Invalid command.")
        printUsage()
    }
}


func printUsage() {
    fmt.Println("Usage: hiveforgectl [command] [subcommand] [args...] [-d|--debug]")
    fmt.Println("Commands:")
    fmt.Println("  authenticate")
    fmt.Println("  get [jobs|agents]")
    fmt.Println("  create job <json_file>")
    fmt.Println("  describe [job|agent] <id>")
    fmt.Println("  generate-key <type> <name> <description>")
    fmt.Println("  list-keys")
}

func handleGet(args []string, config Config, jwt *JWT) {
    if len(args) < 1 {
        fmt.Println("Usage: hiveforgectl get [jobs|agents]")
        return
    }

    switch args[0] {
    case "jobs":
        fmt.Println("Fetching jobs...")
        jobs, err := getJobs(config.ApiEndpoint, config.Port, config.Debug, jwt)
        if err != nil {
            fmt.Printf("Error fetching jobs: %v\n", err)
            return
        }
        if len(jobs) == 0 {
            fmt.Println("No jobs found.")
        } else {
            fmt.Printf("Retrieved %d jobs. Displaying...\n", len(jobs))
            displayJobs(jobs)
        }
    case "agents":
        fmt.Println("Fetching agents...")
        agents, err := getAgents(config, jwt)
        if err != nil {
            fmt.Printf("Error fetching agents: %v\n", err)
            return
        }
        if len(agents) == 0 {
            fmt.Println("No agents found.")
        } else {
            fmt.Printf("Retrieved %d agents. Displaying...\n", len(agents))
            displayAgents(agents)
        }
    default:
        fmt.Println("Invalid subcommand. Usage: hiveforgectl get [jobs|agents]")
    }
}

func handleCreate(args []string, config Config, jwt *JWT) {
	if len(args) < 2 {
		fmt.Println("Usage: hiveforgectl create job <json_file>")
		return
	}

	if args[0] == "job" {
		jsonFilePath := args[1]
		err := createJob(config.ApiEndpoint, config.Port, config.Debug, jsonFilePath, jwt)
		if err != nil {
			fmt.Println("Error creating job:", err)
		}
	} else {
		fmt.Println("Invalid subcommand. Usage: hiveforgectl create job <json_file>")
	}
}

func handleDescribe(args []string, config Config, jwt *JWT) {
    if len(args) < 2 {
        fmt.Println("Usage: hiveforgectl describe [job|agent] <id>")
        return
    }

    switch args[0] {
    case "job":
        jobID := args[1]
        err := describeJob(config.ApiEndpoint, config.Port, config.Debug, jobID, jwt)
        if err != nil {
            fmt.Printf("Error describing job: %v\n", err)
        }
    case "agent":
        agentID := args[1]
        agent, err := getAgent(config, jwt, agentID)
        if err != nil {
            fmt.Printf("Error describing agent: %v\n", err)
            return
        }
        agentJSON, err := json.MarshalIndent(agent, "", "  ")
        if err != nil {
            fmt.Printf("Error formatting agent data: %v\n", err)
            return
        }
        fmt.Println(string(agentJSON))
    default:
        fmt.Println("Invalid subcommand. Usage: hiveforgectl describe [job|agent] <id>")
    }
}

func handleAuthenticate(config Config) {
    jwt, err := authenticateAndGetJWT(config)
    if err != nil {
        fmt.Printf("Authentication failed: %v\n", err)
        return
    }

    if err := storeJWT(jwt); err != nil {
        fmt.Printf("Failed to store JWT: %v\n", err)
        return
    }

    fmt.Println("Authentication successful. JWT stored.")
}

func handleGenerateKey(args []string, config Config, jwt *JWT) {
    if len(args) < 3 {
        fmt.Println("Usage: hiveforgectl generate-key <type> <name> <description>")
        return
    }
    validKeyTypes := map[string]bool{
        "operator_key": true,
        "agent_key":    true,
        "reader_key":   true,
    }
    if !validKeyTypes[args[0]] {
        fmt.Println("Invalid key type. Valid key types: operator_key, agent_key, reader_key")
        return
    }

    keyType, name, description := args[0], args[1], args[2]
    apiKey, err := generateApiKey(config, jwt, keyType, name, description)
    if err != nil {
        switch err.Error() {
        case "neither master key (for operator key) nor API key is set":
            fmt.Println("Error: Neither master key (for operator key) nor API key is set. At least one is required.")
        default:
            fmt.Printf("Error generating API key: %v\n", err)
        }
        return
    }
    fmt.Printf("Successfully generated %s API key: %s\n", keyType, apiKey.Key)
}

func handleListKeys(config Config, jwt *JWT) {
    apiKeys, err := listApiKeys(config.ApiEndpoint, config.Port, jwt)
	if err != nil {
		fmt.Printf("Error listing API keys: %v\n", err)
		return
	}
	displayApiKeys(apiKeys)
}
