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

func handleHash(args []string, config Config, jwt *JWT) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: hiveforgectl hash <directory>")
	}

	directory := args[0]
	fmt.Printf("Starting hash operation for directory: %s\n", directory)

	result, err := hashDirectory(directory)
	if err != nil {
		return fmt.Errorf("error hashing directory: %w", err)
	}

	if err := sendHashResultToAPI(config, jwt, result); err != nil {
		return fmt.Errorf("error sending hash result to API: %w", err)
	}

	fmt.Println("Hash result successfully sent to API")
	return nil
}

type HashingOutput struct {
	bar               *progressbar.ProgressBar
	mutex             sync.Mutex
	recentFiles       []string
	ignoredItems      []IgnoredItem
	totalFiles        int
	totalSize         int64
	processedSize     int64
	startTime         time.Time
	currentFile       string
	lastDisplayUpdate time.Time
}

func newHashingOutput(totalSize int64) *HashingOutput {
	return &HashingOutput{
		bar: progressbar.NewOptions64(totalSize,
			progressbar.OptionSetWidth(50),
			progressbar.OptionSetDescription("Hashing"),
			progressbar.OptionSetRenderBlankState(true),
			progressbar.OptionShowBytes(true),
			progressbar.OptionSetWriter(io.Discard), // Prevent automatic rendering
		),
		recentFiles:  make([]string, 0, 5),
		ignoredItems: make([]IgnoredItem, 0),
		totalSize:    totalSize,
		startTime:    time.Now(),
	}
}

func (ho *HashingOutput) updateProgress(size int64) {
	ho.mutex.Lock()
	defer ho.mutex.Unlock()

	ho.processedSize += size
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

func (ho *HashingOutput) incrementFileCount() {
	ho.mutex.Lock()
	defer ho.mutex.Unlock()

	ho.totalFiles++
}

func (ho *HashingOutput) printStatus() {
	ho.mutex.Lock()
	defer ho.mutex.Unlock()

	// Move cursor up 8 lines (or to the top if less than 8 lines have been printed)
	fmt.Print(strings.Repeat("\033[1A", outputLines))

	// Render progress bar
	fmt.Print("\033[2K") // Clear the entire line
	progressBarString := ho.bar.String()
	fmt.Println(progressBarString)

	// Print stats
	fmt.Print("\033[2K") // Clear the entire line
	fmt.Printf("Total files: %d | Processed: %.2f MB / %.2f MB | Time: %s\n",
		ho.totalFiles,
		float64(ho.processedSize)/1024/1024,
		float64(ho.totalSize)/1024/1024,
		time.Since(ho.startTime).Round(time.Second),
	)

	// Print current file
	fmt.Print("\033[2K") // Clear the entire line
	fmt.Printf("Current file: %s\n", ho.currentFile)

	// Print recent files
	fmt.Print("\033[2K") // Clear the entire line
	fmt.Println("Recent files:")
	for i, file := range ho.recentFiles {
		fmt.Print("\033[2K") // Clear the entire line
		fmt.Printf("  %s\n", file)
		if i == 3 {
			break // Only print up to 4 recent files
		}
	}

	// Fill any remaining lines with empty space
	for i := len(ho.recentFiles); i < 4; i++ {
		fmt.Print("\033[2K") // Clear the entire line
		fmt.Println()
	}
}

func (ho *HashingOutput) shouldUpdateDisplay() bool {
	ho.mutex.Lock()
	defer ho.mutex.Unlock()

	now := time.Now()
	if now.Sub(ho.lastDisplayUpdate) >= 100*time.Millisecond {
		ho.lastDisplayUpdate = now
		return true
	}
	return false
}

func (ho *HashingOutput) printFinalSummary() {
	ho.mutex.Lock()
	defer ho.mutex.Unlock()

	// Move cursor to the line after the progress output
	fmt.Print("\n\n")

	fmt.Println("Hashing completed!")
	fmt.Printf("Total files processed: %d\n", ho.totalFiles)
	fmt.Printf("Total size: %.2f MB\n", float64(ho.totalSize)/1024/1024)
	fmt.Printf("Time taken: %s\n", time.Since(ho.startTime).Round(time.Second))

	if len(ho.ignoredItems) > 0 {
		fmt.Println("\nIgnored items:")
		for _, item := range ho.ignoredItems {
			fmt.Printf("   %s\n      Reason: %s\n", item.Path, item.Reason)
		}
	}
}

func (ho *HashingOutput) addIgnoredItem(path, reason string) {
	ho.mutex.Lock()
	defer ho.mutex.Unlock()
	ho.ignoredItems = append(ho.ignoredItems, IgnoredItem{Path: path, Reason: reason})
}

func hashDirectory(rootPath string) (*DirectoryHashResult, error) {
	// Calculate total size first
	var totalSize int64
	err := filepath.Walk(rootPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			totalSize += info.Size()
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	output := newHashingOutput(totalSize)

	// Print initial empty lines
	fmt.Print(strings.Repeat("\n", outputLines))

	ignoreRules := loadIgnoreRules(rootPath, &IgnoreRules{})
	rootEntry, err := processDirectory(rootPath, rootPath, ignoreRules, output)
	if err != nil {
		return nil, err
	}

	output.printFinalSummary()

	return &DirectoryHashResult{
		RootPath:           rootPath,
		DirectoryStructure: rootEntry,
		TotalSize:          rootEntry.Size,
		TotalFiles:         output.totalFiles,
		HashingTime:        time.Since(output.startTime).Seconds(),
		IgnoredItems:       output.ignoredItems,
	}, nil
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
		info, err := entry.Info()
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
		} else {
			childEntry, err := processFile(childPath, info, output)
			if err != nil {
				output.addIgnoredItem(childPath, fmt.Sprintf("Error processing file: %v", err))
				continue
			}
			dirEntry.Children = append(dirEntry.Children, childEntry)
			dirEntry.Size += childEntry.Size
		}

		output.updateProgress(info.Size())
		if output.shouldUpdateDisplay() {
			output.printStatus()
		}
	}

	return dirEntry, nil
}

func processFile(path string, info os.FileInfo, output *HashingOutput) (*DirectoryEntry, error) {
	output.updateCurrentFile(path)
	output.incrementFileCount()

	hashes, err := hashFile(path)
	if err != nil {
		return nil, err
	}

	output.updateProgress(info.Size())

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

func countFiles(entry *DirectoryEntry) int {
	if entry.Type == "file" {
		return 1
	}

	count := 0
	for _, child := range entry.Children {
		count += countFiles(child)
	}
	return count
}
