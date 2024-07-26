package main

import (
	"encoding/hex"
	"io"
	"math"
	"math/bits"

	"github.com/zeebo/blake3"
)

const (
	minChunkSize       = 4 * 1024                   // 4 KiB (sector-aligned)
	maxChunkSize       = 128 * 1024                 // 128 KiB (for typical files)
	normChunkSize      = 16 * 1024                  // 16 KiB (optimized for source code)
	largeFileThreshold = 1 * 1024 * 1024 * 1024     // 1 GB
	absoluteMaxChunks  = 1000000                    // Hard limit on number of chunks
	maskS              = uint64(0x0000d90003530000) // For chunks smaller than normChunkSize
	maskL              = uint64(0x0000d90003100000) // For chunks larger than normChunkSize
	hashSize           = 16                         // 16-byte hash (128 bits)
)

type Chunk struct {
	Offset int64
	Size   int
	Hash   string
}

func FastCDC(reader io.Reader, fileSize int64) ([]Chunk, error) {
	chunkSizes := calculateChunkSizes(fileSize)
	minSize, maxSize, normalSize := chunkSizes.min, chunkSizes.max, chunkSizes.normal

	var chunks []Chunk
	var offset int64
	buf := make([]byte, maxSize)
	hasher := blake3.New()

	for offset < fileSize {
		n, err := io.ReadFull(reader, buf)
		if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
			return nil, err
		}

		if n == 0 {
			break
		}

		data := buf[:n]
		dataSize := len(data)

		chunkSize := dataSize
		if dataSize > minSize {
			chunkSize = findCutPoint(data, minSize, maxSize, normalSize)
		}

		hasher.Reset()
		hasher.Write(data[:chunkSize])
		hash := hasher.Sum(nil)
		chunks = append(chunks, Chunk{
			Offset: offset,
			Size:   chunkSize,
			Hash:   hex.EncodeToString(hash[:hashSize]), // Truncate to desired hash size
		})

		offset += int64(chunkSize)

		// Check if we've reached the chunk limit
		if len(chunks) >= absoluteMaxChunks-1 && offset < fileSize {
			// If we have, create one final chunk for the remaining data
			remainingSize := fileSize - offset
			hasher.Reset()
			hasher.Write(data[chunkSize:n])
			hash := hasher.Sum(nil)
			chunks = append(chunks, Chunk{
				Offset: offset,
				Size:   int(remainingSize),
				Hash:   hex.EncodeToString(hash[:hashSize]), // Truncate to desired hash size
			})
			break
		}
	}

	return chunks, nil
}

func findCutPoint(data []byte, minSize, maxSize, normalSize int) int {
	n := len(data)
	if n <= minSize {
		return n
	}
	if n >= maxSize {
		n = maxSize
	}

	fp := 0
	i := minSize

	if n <= normalSize {
		for ; i < n-minSize; i++ {
			if (gear(data[i]) & maskS) == 0 {
				fp = i + 1
				break
			}
		}
	} else {
		for ; i < normalSize-minSize; i++ {
			if (gear(data[i]) & maskL) == 0 {
				fp = i + 1
				break
			}
		}
		if fp == 0 {
			for ; i < n-minSize; i++ {
				if (gear(data[i]) & maskS) == 0 {
					fp = i + 1
					break
				}
			}
		}
	}

	if fp > 0 {
		return fp
	}
	return n
}

func gear(x byte) uint64 {
	return uint64(bits.Reverse32(uint32(x)))
}

type chunkSizes struct {
	min, max, normal int
}

func calculateChunkSizes(fileSize int64) chunkSizes {
	if fileSize < largeFileThreshold {
		return chunkSizes{minChunkSize, maxChunkSize, normChunkSize}
	}

	// For large files, adjust chunk sizes to limit the total number of chunks
	averageChunkSize := int(math.Ceil(float64(fileSize) / float64(absoluteMaxChunks)))
	minSize := max(minChunkSize, averageChunkSize/2)
	maxSize := max(maxChunkSize, averageChunkSize*2)
	normalSize := averageChunkSize

	return chunkSizes{minSize, maxSize, normalSize}
}
