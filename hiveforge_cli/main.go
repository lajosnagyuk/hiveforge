package main

import (
	"bytes"
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
)

// Config represents the application configuration
type Config struct {
	ApiEndpoint string `json:"api_endpoint"`
	Port        int    `json:"port"`
	CacertFile  string `json:"cacert_file"`
	Debug       bool   `json:"debug"`
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
	if len(args) < 2 {
		fmt.Println("Usage: hiveforgectl [get jobs | create job <json_file>] [-d|--debug]")
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

	switch {
	case args[0] == "get" && args[1] == "jobs":
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
	case args[0] == "create" && args[1] == "job":
		if len(args) < 3 {
			fmt.Println("Usage: hiveforgectl create job <json_file> [-d|--debug]")
			return
		}
		jsonFilePath := args[2]
		err := createJob(config, jsonFilePath)
		if err != nil {
			fmt.Println("Error creating job:", err)
		}

	case args[0] == "describe" && args[1] == "job":
    if len(args) < 3 {
        fmt.Println("Usage: hiveforgectl describe job <id> [-d|--debug]")
        return
    }

    jobID := args[2]
    err := describeJob(config, jobID)
    if err != nil {
        fmt.Printf("Error describing job: %v\n", err)
    }

    case args[0] == "get" && args[1] == "agents":
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

    case args[0] == "describe" && args[1] == "agent":
        if len(args) < 3 {
            fmt.Println("Usage: hiveforgectl describe agent <id> [-d|--debug]")
            return
        }
        agentID := args[2]
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
        fmt.Println("Invalid command. Usage: hiveforgectl [get jobs | create job <json_file> | describe job <id> | get agents | describe agent <id>] [-d|--debug]")
    }
}
