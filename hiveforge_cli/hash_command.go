package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"encoding/json"

	"github.com/schollz/progressbar/v3"
	"github.com/zeebo/blake3"
)

const (
	minChunkSize = 64 * 1024   // 64 KB
	maxChunkSize = 1024 * 1024 // 1 MB
	maxChunks    = 1024
	outputLines  = 8
)

type IgnoreRules struct {
	patterns []string
	source   string // to keep track of where the rule came from
}

type IgnoredItem struct {
	Path   string
	Reason string
}

type HashingOutput struct {
    bar            *progressbar.ProgressBar
    mutex          sync.Mutex
    recentFiles    []string
    ignoredItems   []IgnoredItem
    totalFiles     int
    processedFiles int
    totalSize      int64
    processedSize  int64
    startTime      time.Time
    currentFile    string
    isCompleted    bool
    lastLines      int
}

func newHashingOutput(totalSize int64, totalFiles int) *HashingOutput {
    return &HashingOutput{
        bar: progressbar.NewOptions64(
            totalSize,
            progressbar.OptionSetWidth(50),
            progressbar.OptionSetDescription("Hashing"),
            progressbar.OptionSetRenderBlankState(true),
            progressbar.OptionShowBytes(true),
            progressbar.OptionThrottle(65*time.Millisecond),
            progressbar.OptionShowCount(),
            progressbar.OptionOnCompletion(func() {}), // Empty function to prevent automatic "completed" message
        ),
        recentFiles:  make([]string, 0, 5),
        ignoredItems: make([]IgnoredItem, 0),
        totalSize:    totalSize,
        totalFiles:   totalFiles,
        startTime:    time.Now(),
    }
}

func (ho *HashingOutput) updateProgress(size int64) {
    ho.mutex.Lock()
    defer ho.mutex.Unlock()

    ho.processedSize += size
    ho.processedFiles++
    ho.bar.Add64(size)
}

func (ho *HashingOutput) updateCurrentFile(path string) {
    ho.mutex.Lock()
    defer ho.mutex.Unlock()

    ho.currentFile = path
    ho.recentFiles = append([]string{path}, ho.recentFiles...)
    if len(ho.recentFiles) > 5 {
        ho.recentFiles = ho.recentFiles[:5]
    }
}

func (ho *HashingOutput) printStatus() {
    ho.mutex.Lock()
    defer ho.mutex.Unlock()

    // Clear previous lines
    if ho.lastLines > 0 {
        fmt.Printf("\033[%dA\033[J", ho.lastLines)
    }

    // Print new status
    fmt.Print(ho.bar.String() + "\n")
    fmt.Printf("Files: %d/%d | Size: %.2f MB / %.2f MB | Time: %s\n",
        ho.processedFiles, ho.totalFiles,
        float64(ho.processedSize)/1024/1024,
        float64(ho.totalSize)/1024/1024,
        time.Since(ho.startTime).Round(time.Second),
    )
    fmt.Printf("Current file: %s\n", ho.currentFile)
    fmt.Println("Recent files:")
    
    recentFilesCount := len(ho.recentFiles)
    if recentFilesCount > 4 {
        recentFilesCount = 4
    }
    for i := 0; i < recentFilesCount; i++ {
        fmt.Printf("  %s\n", ho.recentFiles[i])
    }

    // Update lastLines
    ho.lastLines = 4 + recentFilesCount // 3 for progress, current file, and "Recent files:" + number of recent files
}

func (ho *HashingOutput) complete() {
    ho.mutex.Lock()
    defer ho.mutex.Unlock()

    ho.isCompleted = true
    ho.bar.Finish()
}

func (ho *HashingOutput) printFinalSummary() {
    ho.mutex.Lock()
    defer ho.mutex.Unlock()

    // Clear the last update
    if ho.lastLines > 0 {
        fmt.Printf("\033[%dA\033[J", ho.lastLines)
    }

    fmt.Print(ho.bar.String() + "\n")
    fmt.Println("Hashing completed!")
    fmt.Printf("Total files processed: %d\n", ho.processedFiles)
    fmt.Printf("Total size: %.2f MB\n", float64(ho.processedSize)/1024/1024)
    fmt.Printf("Time taken: %s\n", time.Since(ho.startTime).Round(time.Second))

    if len(ho.ignoredItems) > 0 {
        fmt.Println("\nIgnored items:")
        for _, item := range ho.ignoredItems {
            fmt.Printf("   %s\n      Reason: %s\n", item.Path, item.Reason)
        }
    }
}

func (ho *HashingOutput) updateDisplay() {
    for {
        time.Sleep(100 * time.Millisecond)
        ho.mutex.Lock()
        if ho.isCompleted {
            ho.mutex.Unlock()
            return
        }
        ho.printStatus()
        ho.mutex.Unlock()
    }
}

// ====





func (ho *HashingOutput) addIgnoredItem(path, reason string) {
	ho.mutex.Lock()
	defer ho.mutex.Unlock()
	ho.ignoredItems = append(ho.ignoredItems, IgnoredItem{Path: path, Reason: reason})
}


func handleHash(args []string, config Config, jwt *JWT) error {
    if len(args) < 1 {
        return fmt.Errorf("usage: hiveforgectl hash <directory>")
    }

    directory := args[0]

    result, err := hashDirectory(directory)
    if err != nil {
        return fmt.Errorf("error hashing directory: %w", err)
    }

    if err := sendHashResultToAPI(config, jwt, result); err != nil {
        return fmt.Errorf("error sending hash result to API: %w", err)
    }

    fmt.Println("Hash result successfully sent, handleHash complete.")
    return nil
}

func hashDirectory(rootPath string) (*DirectoryHashResult, error) {
	var totalSize int64
	var totalFiles int

	err := filepath.Walk(rootPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			totalSize += info.Size()
			totalFiles++
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	output := newHashingOutput(totalSize, totalFiles)

	ignoreRules := loadIgnoreRules(rootPath, &IgnoreRules{})
	rootEntry, err := processDirectory(rootPath, rootPath, ignoreRules, output)
	if err != nil {
		return nil, err
	}

	output.complete()
	output.printFinalSummary()

    result := &DirectoryHashResult{
        RootPath:           rootPath,
        DirectoryStructure: rootEntry,
        TotalSize:          rootEntry.Size,
        TotalFiles:         output.processedFiles,
        HashingTime:        time.Since(output.startTime).Seconds(),
        IgnoredItems:       output.ignoredItems,
    }

    // Write the result to a JSON file for debugging
    if err := writeResultToJSONFile(result, "hash_result_debug.json"); err != nil {
        fmt.Printf("Warning: Failed to write debug JSON file: %v\n", err)
    } else {
        fmt.Println("Debug: JSON result written to hash_result_debug.json")
    }

    return result, nil
}

func writeResultToJSONFile(result *DirectoryHashResult, filename string) error {
    // Create a pretty-printed JSON
    jsonData, err := json.MarshalIndent(result, "", "  ")
    if err != nil {
        return fmt.Errorf("failed to marshal result to JSON: %w", err)
    }

    // Write to file
    err = os.WriteFile(filename, jsonData, 0644)
    if err != nil {
        return fmt.Errorf("failed to write JSON to file: %w", err)
    }

    return nil
}

func processDirectory(rootPath string, dirPath string, rules *IgnoreRules, output *HashingOutput) (*DirectoryEntry, error) {
    entries, err := os.ReadDir(dirPath)
    if err != nil {
        return nil, err
    }

    dirEntry := &DirectoryEntry{
        Name: filepath.Base(dirPath),
        Type: "directory",
    }

    for _, entry := range entries {
        childPath := filepath.Join(dirPath, entry.Name())
        
        // Get file info, following symlinks
        info, err := os.Stat(childPath)
        if err != nil {
            output.addIgnoredItem(childPath, fmt.Sprintf("Error getting file info: %v", err))
            continue
        }

        ignored, reason := shouldIgnore(childPath, info.IsDir(), rootPath, rules)
        if ignored {
            output.addIgnoredItem(childPath, reason)
            continue
        }

        if info.IsDir() {
            childRules := loadIgnoreRules(childPath, rules)
            childEntry, err := processDirectory(rootPath, childPath, childRules, output)
            if err != nil {
                output.addIgnoredItem(childPath, fmt.Sprintf("Error processing directory: %v", err))
                continue
            }
            dirEntry.Children = append(dirEntry.Children, childEntry)
            dirEntry.Size += childEntry.Size
        } else if info.Mode().IsRegular() {
            childEntry, err := processFile(childPath, info, output)
            if err != nil {
                output.addIgnoredItem(childPath, fmt.Sprintf("Error processing file: %v", err))
                continue
            }
            dirEntry.Children = append(dirEntry.Children, childEntry)
            dirEntry.Size += childEntry.Size
        } else {
            // Handle special files (e.g., symlinks, devices)
            output.addIgnoredItem(childPath, "Skipped special file")
        }

        output.updateProgress(info.Size())
    }

    return dirEntry, nil
}
func processFile(path string, info os.FileInfo, output *HashingOutput) (*DirectoryEntry, error) {
	output.updateCurrentFile(path)

	hashes, err := hashFile(path)
	if err != nil {
		return nil, err
	}

	return &DirectoryEntry{
		Name:   info.Name(),
		Type:   "file",
		Size:   info.Size(),
		Hashes: &hashes,
	}, nil
}

func loadIgnoreRules(dirPath string, parentRules *IgnoreRules) *IgnoreRules {
	ignoreFilePath := filepath.Join(dirPath, ".hiveignore")
	file, err := os.Open(ignoreFilePath)
	if err != nil {
		// If .hiveignore doesn't exist, return parent rules
		return parentRules
	}
	defer file.Close()

	newRules := &IgnoreRules{
		patterns: make([]string, len(parentRules.patterns)),
		source:   ignoreFilePath,
	}
	copy(newRules.patterns, parentRules.patterns)

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		pattern := strings.TrimSpace(scanner.Text())
		if pattern != "" && !strings.HasPrefix(pattern, "#") {
			newRules.patterns = append(newRules.patterns, pattern)
		}
	}

	return newRules
}

func shouldIgnore(path string, isDir bool, rootPath string, rules *IgnoreRules) (bool, string) {
	relPath, err := filepath.Rel(rootPath, path)
	if err != nil {
		return false, ""
	}

	// Always use forward slashes for consistency
	relPath = filepath.ToSlash(relPath)

	for _, pattern := range rules.patterns {
		matched, err := matchIgnorePattern(relPath, pattern, isDir)
		if err != nil {
			continue
		}
		if matched {
			return true, fmt.Sprintf("Matched pattern '%s' from %s", pattern, rules.source)
		}
	}
	return false, ""
}

func matchIgnorePattern(path string, pattern string, isDir bool) (bool, error) {
	// Handle directory-only patterns (ending with '/')
	if strings.HasSuffix(pattern, "/") {
		if !isDir {
			return false, nil
		}
		pattern = strings.TrimSuffix(pattern, "/")
	}

	// If the pattern doesn't contain a slash, it matches in any directory
	if !strings.Contains(pattern, "/") {
		return filepath.Match(pattern, filepath.Base(path))
	}

	// If the pattern starts with '/', it matches from the root
	if strings.HasPrefix(pattern, "/") {
		return filepath.Match(pattern[1:], path)
	}

	// Otherwise, try to match the pattern anywhere in the path
	matched, err := filepath.Match(pattern, path)
	if matched {
		return true, nil
	}

	// Also check if the pattern matches any subdirectory
	parts := strings.Split(path, "/")
	for i := range parts {
		subpath := strings.Join(parts[i:], "/")
		matched, err = filepath.Match(pattern, subpath)
		if matched {
			return true, nil
		}
	}

	return false, err
}

func hashFile(filePath string) (FileHashes, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return FileHashes{}, err
	}
	defer file.Close()

	fileInfo, err := file.Stat()
	if err != nil {
		return FileHashes{}, err
	}

	totalSize := fileInfo.Size()
	chunkSize := calculateChunkSize(totalSize)

	hashes := make([]string, 0, maxChunks)
	buffer := make([]byte, chunkSize)

	for {
		n, err := file.Read(buffer)
		if err == io.EOF {
			break
		}
		if err != nil {
			return FileHashes{}, err
		}

		hash := blake3.Sum256(buffer[:n])
		hashes = append(hashes, fmt.Sprintf("%x", hash))

		if len(hashes) >= maxChunks {
			break
		}
	}

	return FileHashes{
		FileName:   filepath.Base(filePath),
		ChunkSize:  chunkSize,
		ChunkCount: len(hashes),
		Hashes:     hashes,
		TotalSize:  totalSize,
	}, nil
}

func calculateChunkSize(fileSize int64) int {
	chunkSize := fileSize / int64(maxChunks)
	if chunkSize < minChunkSize {
		return minChunkSize
	}
	if chunkSize > maxChunkSize {
		return maxChunkSize
	}
	return int(chunkSize)
}
