package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io/ioutil"
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
	Id                   int      `json:"id"`
	Name                 string   `json:"name"`
	Description          string   `json:"description"`
	Status               string   `json:"status"`
	RequestedCapabilities []string `json:"requested_capabilities"`
	InsertedAt           string   `json:"inserted_at"`
	UpdatedAt            string   `json:"updated_at"`
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
			file, err := ioutil.ReadFile(path)
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
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// Print the raw API response if debug mode is enabled
	if config.Debug {
		fmt.Println("Raw API response:")
		fmt.Println(string(body))
	}

	var jobs []Job
	err = json.Unmarshal(body, &jobs)
	if err != nil {
		return nil, err
	}

	return jobs, nil
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

func main() {
	// Define and parse the debug flag
	debug := flag.Bool("debug", false, "Enable debug mode")
	flag.Parse()

	args := flag.Args()
	if len(args) < 2 || args[0] != "get" || args[1] != "jobs" {
		fmt.Println("Usage: hiveforgectl get jobs [-d|--debug]")
		return
	}

	// Load configuration
	config, err := loadConfig()
	if err != nil {
		fmt.Println("Error loading config:", err)
		return
	}
	config.Debug = *debug

	// Confirm if debug mode is enabled
	if config.Debug {
		fmt.Println("Debug mode is enabled")
	}

	// Retrieve jobs from the API
	jobs, err := getJobs(config)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	// Display the jobs
	if len(jobs) == 0 {
		fmt.Println("No jobs found.")
	} else {
		displayJobs(jobs)
	}
}
