package main

type DirectoryHashResult struct {
	RootPath           string          `json:"root"`
	DirectoryStructure *DirectoryEntry `json:"dir"`
	TotalSize          int64           `json:"size"`
	TotalFiles         int             `json:"files"`
	HashingTime        float64         `json:"time"`
	IgnoredItems       []IgnoredItem   `json:"ignoredItems"`
}

type DirectoryEntry struct {
	Name       string            `json:"name"`
	Type       string            `json:"type"` // "file" or "directory"
	Size       int64             `json:"size"`
	Children   []*DirectoryEntry `json:"children,omitempty"`
	FileResult *FileResult       `json:"file_result,omitempty"`
}

type FileResult struct {
	FileInfo     FileInfo     `json:"file_info"`
	ChunkingInfo ChunkingInfo `json:"chunking_info"`
	Chunks       []ChunkInfo  `json:"chunks"`
}

type FileInfo struct {
	Name string `json:"name"`
	Size int64  `json:"size"`
	Hash string `json:"hash"`
}

type ChunkingInfo struct {
	Algorithm        string `json:"algorithm"`
	AverageChunkSize int    `json:"average_chunk_size"`
	MinChunkSize     int    `json:"min_chunk_size"`
	MaxChunkSize     int    `json:"max_chunk_size"`
	TotalChunks      int    `json:"total_chunks"`
}

type ChunkInfo struct {
	Hash   string `json:"hash"`
	Size   int    `json:"size"`
	Offset int64  `json:"offset"`
}

type IgnoredItem struct {
	Path   string `json:"path"`
	Reason string `json:"reason"`
}
