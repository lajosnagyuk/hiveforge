package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
	"encoding/json"
	"github.com/zeebo/blake3"
)

const (
	minChunkSize = 64 * 1024   // 64 KB
	maxChunkSize = 1024 * 1024 // 1 MB
	maxChunks    = 1024
)

func handleHash(args []string, config Config, jwt *JWT) error {
    if len(args) < 1 {
        return fmt.Errorf("usage: hiveforgectl hash <directory>")
    }

    directory := args[0]
    fmt.Printf("DEBUG: Starting hash operation for directory: %s\n", directory)

    startTime := time.Now()

    result, err := hashDirectory(directory)
    if err != nil {
        return fmt.Errorf("error hashing directory: %w", err)
    }

    result.HashingTime = time.Since(startTime).Seconds()

    fmt.Printf("DEBUG: Hashing completed. Total files: %d, Total size: %d bytes, Time taken: %.2f seconds\n",
               result.TotalFiles, result.TotalSize, result.HashingTime)

    jsonData, err := json.MarshalIndent(result, "", "  ")
    if err != nil {
        return fmt.Errorf("error marshaling hash result to JSON: %w", err)
    }

    fmt.Printf("DEBUG: JSON data size before compression: %d bytes\n", len(jsonData))

    if err := sendHashResultToAPI(config, jwt, result); err != nil {
        return fmt.Errorf("error sending hash result to API: %w", err)
    }

    fmt.Println("Hash result successfully sent to API")
    return nil
}


func hashDirectory(rootPath string) (*DirectoryHashResult, error) {
	result := &DirectoryHashResult{
		RootPath: rootPath,
	}

	rootInfo, err := os.Stat(rootPath)
	if err != nil {
		return nil, fmt.Errorf("error accessing root directory: %w", err)
	}

	rootEntry, err := processDirectory(rootPath, rootInfo)
	if err != nil {
		return nil, fmt.Errorf("error processing directory: %w", err)
	}

	result.DirectoryStructure = rootEntry
	result.TotalSize = rootEntry.Size
	result.TotalFiles = countFiles(rootEntry)

	return result, nil
}

func processDirectory(path string, info os.FileInfo) (*DirectoryEntry, error) {
	entry := &DirectoryEntry{
		Name: info.Name(),
		Type: "directory",
		Size: info.Size(),
	}

	entries, err := os.ReadDir(path)
	if err != nil {
		return nil, fmt.Errorf("error reading directory %s: %w", path, err)
	}

	for _, e := range entries {
		childPath := filepath.Join(path, e.Name())
		childInfo, err := e.Info()
		if err != nil {
			fmt.Printf("Warning: Error accessing %s: %v\n", childPath, err)
			continue
		}

		if childInfo.IsDir() {
			childEntry, err := processDirectory(childPath, childInfo)
			if err != nil {
				fmt.Printf("Warning: Error processing directory %s: %v\n", childPath, err)
				continue
			}
			entry.Children = append(entry.Children, childEntry)
			entry.Size += childEntry.Size
		} else if childInfo.Mode().IsRegular() {
			childEntry, err := processFile(childPath, childInfo)
			if err != nil {
				fmt.Printf("Warning: Error processing file %s: %v\n", childPath, err)
				continue
			}
			entry.Children = append(entry.Children, childEntry)
			entry.Size += childEntry.Size
		}
	}

	return entry, nil
}

func processFile(path string, info os.FileInfo) (*DirectoryEntry, error) {
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
