package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
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
)

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
func loadConfig() (Config, error) {
	configPaths := []string{
		"config.json",
	}

	user, err := user.Current()
	if err != nil {
		return Config{}, err
	}

	homeConfigPath := filepath.Join(user.HomeDir, ".hiveforge", "config.json")
	configPaths = append(configPaths, homeConfigPath)

	for _, path := range configPaths {
		if _, err := os.Stat(path); err == nil {
			file, err := os.ReadFile(path)
			if err != nil {
				return Config{}, err
			}

			var config Config
			err = json.Unmarshal(file, &config)
			if err != nil {
				return Config{}, err
			}

			return config, nil
		}
	}

	return Config{}, errors.New("config file not found in current directory or ~/.hiveforge/")
}

func generateSignature(apiKey, nonce string, body []byte) string {
	transactionKey := hmac.New(sha256.New, []byte(apiKey))
	transactionKey.Write([]byte("TRANSACTION" + nonce))

	signature := hmac.New(sha256.New, transactionKey.Sum(nil))
	signature.Write(body)

	return base64.StdEncoding.EncodeToString(signature.Sum(nil))
}

func makeAuthenticatedRequest(config Config, method, url string, body []byte) (*http.Response, error) {
	req, err := http.NewRequest(method, url, bytes.NewBuffer(body))
	if err != nil {
		return nil, err
	}

	nonce := fmt.Sprintf("%d", time.Now().UnixNano())
	signature := generateSignature(config.ApiKey, nonce, body)

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", config.ApiKey)
	req.Header.Set("x-nonce", nonce)
	req.Header.Set("x-signature", signature)

	client := &http.Client{}
	return client.Do(req)
}

func generateApiKey(config Config, keyType, name, description string) (*ApiKey, error) {
    if keyType == "operator_key" && config.MasterKey == "" {
        return nil, errors.New("master key is required to generate an operator key")
    }

    url := fmt.Sprintf("http://%s:%d/api/v1/api_keys", config.ApiEndpoint, config.Port)

    requestBody, err := json.Marshal(map[string]string{
        "type": keyType,
        "name": name,
        "description": description,
    })
    if err != nil {
        return nil, err
    }

    var resp *http.Response
    var reqErr error

    if keyType == "operator_key" && config.MasterKey != "" {
        req, err := http.NewRequest("POST", url, bytes.NewBuffer(requestBody))
        if err != nil {
            return nil, err
        }
        req.Header.Set("Content-Type", "application/json")
        req.Header.Set("x-master-key", config.MasterKey)

        client := &http.Client{}
        resp, reqErr = client.Do(req)
    } else if config.ApiKey != "" {
        resp, reqErr = makeAuthenticatedRequest(config, "POST", url, requestBody)
    } else {
        return nil, errors.New("neither master key (for operator key) nor API key is set")
    }

    if reqErr != nil {
        return nil, reqErr
    }
    if resp == nil {
        return nil, errors.New("no response received from server")
    }
    defer resp.Body.Close()

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, err
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

func listApiKeys(config Config) ([]ApiKey, error) {
	url := fmt.Sprintf("http://%s:%d/api/v1/api_keys", config.ApiEndpoint, config.Port)

	resp, err := makeAuthenticatedRequest(config, "GET", url, nil)
	if err != nil {
		return nil, err
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
		return nil, err
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

// getJobs retrieves jobs from the API
func getJobs(config Config) ([]Job, error) {
    url := fmt.Sprintf("http://%s:%d/api/v1/jobs", config.ApiEndpoint, config.Port)
    fmt.Printf("Requesting URL: %s\n", url)  // Debug print

    resp, err := http.Get(url)
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
    fmt.Println("Raw API response:")
    fmt.Println(string(body))

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

func describeJob(config Config, id string) error {
    url := fmt.Sprintf("http://%s:%d/api/v1/jobs/%s", config.ApiEndpoint, config.Port, id)
    fmt.Printf("Requesting URL: %s\n", url)

    resp, err := http.Get(url)
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

func createJob(config Config, jsonFilePath string) error {
	// Read the JSON file
	jsonData, err := os.ReadFile(jsonFilePath)
	if err != nil {
		return fmt.Errorf("error reading JSON file: %v", err)
	}

	// Validate JSON
	var job map[string]interface{}
	if err := json.Unmarshal(jsonData, &job); err != nil {
		return fmt.Errorf("invalid JSON: %v", err)
	}

	// Encode the JSON in base64
	encodedJob := base64.StdEncoding.EncodeToString(jsonData)
	requestBody := fmt.Sprintf(`{"body":"%s"}`, encodedJob)

	url := fmt.Sprintf("http://%s:%d/api/v1/jobs", config.ApiEndpoint, config.Port)
	resp, err := http.Post(url, "application/json", bytes.NewBufferString(requestBody))
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if config.Debug {
		fmt.Println("Raw API response:")
		fmt.Println(string(body))
	}

	if resp.StatusCode != http.StatusCreated {
		return fmt.Errorf("failed to create job: %s", string(body))
	}

	fmt.Println("Job created successfully")
	return nil
}

func getAgents(config Config) ([]Agent, error) {
    url := fmt.Sprintf("http://%s:%d/api/v1/agents", config.ApiEndpoint, config.Port)
    resp, err := http.Get(url)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, err
    }

    if config.Debug {
        fmt.Println("Raw API response:")
        fmt.Println(string(body))
    }

    var agents []Agent
    err = json.Unmarshal(body, &agents)
    if err != nil {
        return nil, err
    }

    return agents, nil
}

func getAgent(config Config, id string) (*Agent, error) {
    url := fmt.Sprintf("http://%s:%d/api/v1/agents/%s", config.ApiEndpoint, config.Port, id)
    resp, err := http.Get(url)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, err
    }

    if config.Debug {
        fmt.Println("Raw API response:")
        fmt.Println(string(body))
    }

    var agent Agent
    err = json.Unmarshal(body, &agent)
    if err != nil {
        return nil, err
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

    config, err := loadConfig()
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
	case "get":
		handleGet(args[1:], config)
	case "create":
		handleCreate(args[1:], config)
	case "describe":
		handleDescribe(args[1:], config)
	case "generate-key":
		handleGenerateKey(args[1:], config)
	case "list-keys":
		handleListKeys(config)
	default:
		fmt.Println("Invalid command.")
		printUsage()
	}
}

func printUsage() {
	fmt.Println("Usage: hiveforgectl [command] [subcommand] [args...] [-d|--debug]")
	fmt.Println("Commands:")
	fmt.Println("  get [jobs|agents]")
	fmt.Println("  create job <json_file>")
	fmt.Println("  describe [job|agent] <id>")
	fmt.Println("  generate-key <type> <name> <description>")
	fmt.Println("  list-keys")
}

func handleGet(args []string, config Config) {
	if len(args) < 1 {
		fmt.Println("Usage: hiveforgectl get [jobs|agents]")
		return
	}

	switch args[0] {
	case "jobs":
		fmt.Println("Fetching jobs...")
		jobs, err := getJobs(config)
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
		agents, err := getAgents(config)
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

func handleCreate(args []string, config Config) {
	if len(args) < 2 {
		fmt.Println("Usage: hiveforgectl create job <json_file>")
		return
	}

	if args[0] == "job" {
		jsonFilePath := args[1]
		err := createJob(config, jsonFilePath)
		if err != nil {
			fmt.Println("Error creating job:", err)
		}
	} else {
		fmt.Println("Invalid subcommand. Usage: hiveforgectl create job <json_file>")
	}
}

func handleDescribe(args []string, config Config) {
	if len(args) < 2 {
		fmt.Println("Usage: hiveforgectl describe [job|agent] <id>")
		return
	}

	switch args[0] {
	case "job":
		jobID := args[1]
		err := describeJob(config, jobID)
		if err != nil {
			fmt.Printf("Error describing job: %v\n", err)
		}
	case "agent":
		agentID := args[1]
		agent, err := getAgent(config, agentID)
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

func handleGenerateKey(args []string, config Config) {
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
    apiKey, err := generateApiKey(config, keyType, name, description)
    if err != nil {
        switch err.Error() {
        case "master key is required to generate an operator key":
            fmt.Println("Error: Master key is not set. It is required to generate an operator key.")
        case "neither master key (for operator key) nor API key is set":
            fmt.Println("Error: Neither master key (for operator key) nor API key is set. At least one is required.")
        default:
            fmt.Printf("Error generating API key: %v\n", err)
        }
        return
    }
    fmt.Printf("Successfully generated %s API key: %s\n", keyType, apiKey.Key)
}

func handleListKeys(config Config) {
	apiKeys, err := listApiKeys(config)
	if err != nil {
		fmt.Printf("Error listing API keys: %v\n", err)
		return
	}
	displayApiKeys(apiKeys)
}
