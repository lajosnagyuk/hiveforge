package main

import (
	"bufio"
	"context"
	"encoding/json"
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

type IgnoreRules struct {
	patterns []string
	source   string // to keep track of where the rule came from
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
			progressbar.OptionOnCompletion(func() {}),
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

	// Capture the current status
	currentFile := ho.currentFile
	recentFiles := make([]string, len(ho.recentFiles))
	copy(recentFiles, ho.recentFiles)
	processedFiles := ho.processedFiles
	totalFiles := ho.totalFiles
	processedSize := ho.processedSize
	totalSize := ho.totalSize
	startTime := ho.startTime
	barString := ho.bar.String()

	// Clear previous lines
	if ho.lastLines > 0 {
		fmt.Printf("\033[%dA\033[J", ho.lastLines)
	}

	// Print new status without holding the lock
	ho.mutex.Unlock()
	fmt.Print(barString + "\n")
	fmt.Printf("Files: %d/%d | Size: %.2f MB / %.2f MB | Time: %s\n",
		processedFiles, totalFiles,
		float64(processedSize)/1024/1024,
		float64(totalSize)/1024/1024,
		time.Since(startTime).Round(time.Second),
	)
	fmt.Printf("Current file: %s\n", currentFile)
	fmt.Println("Recent files:")
	ho.mutex.Lock()

	recentFilesCount := len(recentFiles)
	if recentFilesCount > 4 {
		recentFilesCount = 4
	}
	for i := 0; i < recentFilesCount; i++ {
		fmt.Printf("  %s\n", recentFiles[i])
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

	// Capture the final summary details
	processedFiles := ho.processedFiles
	processedSize := ho.processedSize
	startTime := ho.startTime
	barString := ho.bar.String()
	ignoredItems := make([]IgnoredItem, len(ho.ignoredItems))
	copy(ignoredItems, ho.ignoredItems)

	// Clear the last update
	if ho.lastLines > 0 {
		fmt.Printf("\033[%dA\033[J", ho.lastLines)
	}

	// Print the final summary without holding the lock
	ho.mutex.Unlock()
	fmt.Print(barString + "\n")
	fmt.Println("Hashing completed!")
	fmt.Printf("Total files processed: %d\n", processedFiles)
	fmt.Printf("Total size: %.2f MB\n", float64(processedSize)/1024/1024)
	fmt.Printf("Time taken: %s\n", time.Since(startTime).Round(time.Second))
	ho.mutex.Lock()

	if len(ignoredItems) > 0 {
		fmt.Println("\nIgnored items:")
		for _, item := range ignoredItems {
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
		ho.mutex.Unlock()
		ho.printStatus()
	}
}

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

	// Create a context with a timeout
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	resultChan := make(chan *DirectoryHashResult)
	errChan := make(chan error)

	go func() {
		result, err := hashDirectory(ctx, directory)
		if err != nil {
			errChan <- err
		} else {
			resultChan <- result
		}
	}()

	select {
	case result := <-resultChan:
		if err := sendHashResultToAPI(config, jwt, result); err != nil {
			return fmt.Errorf("error sending hash result to API: %w", err)
		}
		fmt.Println("Hash result successfully sent, handleHash complete.")
		return nil
	case err := <-errChan:
		return fmt.Errorf("error hashing directory: %w", err)
	case <-ctx.Done():
		return fmt.Errorf("hashing operation timed out after 30 minutes")
	}
}

func hashDirectory(ctx context.Context, rootPath string) (*DirectoryHashResult, error) {
	var totalSize int64
	var totalFiles int

	fmt.Println("Scanning directory...")
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

	fmt.Printf("Found %d files, total size: %.2f MB\n", totalFiles, float64(totalSize)/1024/1024)

	output := newHashingOutput(totalSize, totalFiles)
	go output.updateDisplay()

	ignoreRules := loadIgnoreRules(rootPath, &IgnoreRules{})
	rootEntry, err := processDirectory(ctx, rootPath, rootPath, ignoreRules, output)
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

	jsonFileName := "hash_result.json"
	if err := writeResultToJSONFile(result, jsonFileName); err != nil {
		return nil, fmt.Errorf("error writing hash result to JSON file: %w", err)
	}

	return result, nil
}

func processDirectory(ctx context.Context, rootPath string, dirPath string, rules *IgnoreRules, output *HashingOutput) (*DirectoryEntry, error) {
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
	}

	entries, err := os.ReadDir(dirPath)
	if err != nil {
		return nil, err
	}

	dirEntry := &DirectoryEntry{
		Name:     filepath.Base(dirPath),
		Type:     "directory",
		Children: make([]*DirectoryEntry, 0),
		Size:     0,
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
			childEntry, err := processDirectory(ctx, rootPath, childPath, childRules, output)
			if err != nil {
				output.addIgnoredItem(childPath, fmt.Sprintf("Error processing directory: %v", err))
				continue
			}
			dirEntry.Children = append(dirEntry.Children, childEntry)
			dirEntry.Size += childEntry.Size
		} else if info.Mode().IsRegular() {
			childEntry, err := processFile(ctx, childPath, info, output)
			if err != nil {
				output.addIgnoredItem(childPath, fmt.Sprintf("Error processing file: %v", err))
				continue
			}
			dirEntry.Children = append(dirEntry.Children, childEntry)
			dirEntry.Size += childEntry.Size
		} else {
			output.addIgnoredItem(childPath, "Skipped special file")
		}

		output.updateProgress(info.Size())
	}

	return dirEntry, nil
}

func processFile(ctx context.Context, path string, info os.FileInfo, output *HashingOutput) (*DirectoryEntry, error) {
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
	}

	output.updateCurrentFile(path)
	// fmt.Printf("Processing file: %s\n", path) // Additional logging

	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	chunks, err := FastCDC(file, info.Size())
	if err != nil {
		return nil, fmt.Errorf("FastCDC error for file %s: %w", path, err)
	}

	// Reset file pointer to the beginning
	_, err = file.Seek(0, 0)
	if err != nil {
		return nil, fmt.Errorf("error resetting file pointer for %s: %w", path, err)
	}

	// Calculate the file hash with a timeout
	hashCtx, hashCancel := context.WithTimeout(ctx, 10*time.Minute)
	defer hashCancel()

	fileHasher := blake3.New()
	doneChan := make(chan error, 1)

	go func() {
		_, err := io.Copy(fileHasher, file)
		doneChan <- err
	}()

	select {
	case <-hashCtx.Done():
		return nil, fmt.Errorf("hashing file %s timed out", path)
	case err := <-doneChan:
		if err != nil {
			return nil, err
		}
	}

	fileHash := fmt.Sprintf("%x", fileHasher.Sum(nil))

	chunkInfos := make([]ChunkInfo, len(chunks))
	for i, chunk := range chunks {
		chunkInfos[i] = ChunkInfo{
			Hash:   chunk.Hash,
			Size:   chunk.Size,
			Offset: chunk.Offset,
		}
	}

	var averageChunkSize int
	if len(chunks) > 0 {
		averageChunkSize = int(info.Size()) / len(chunks)
	} else {
		averageChunkSize = 0
	}

	fileResult := FileResult{
		FileInfo: FileInfo{
			Name: info.Name(),
			Size: info.Size(),
			Hash: fileHash,
		},
		ChunkingInfo: ChunkingInfo{
			Algorithm:        "FastCDC",
			AverageChunkSize: averageChunkSize,
			MinChunkSize:     minChunkSize,
			MaxChunkSize:     maxChunkSize,
			TotalChunks:      len(chunks),
		},
		Chunks: chunkInfos,
	}

	return &DirectoryEntry{
		Name:       info.Name(),
		Type:       "file",
		Size:       info.Size(),
		FileResult: &fileResult,
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

func writeResultToJSONFile(result *DirectoryHashResult, filename string) error {
	jsonData, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal result to JSON: %w", err)
	}

	err = os.WriteFile(filename, jsonData, 0644)
	if err != nil {
		return fmt.Errorf("failed to write JSON to file: %w", err)
	}

	return nil
}
