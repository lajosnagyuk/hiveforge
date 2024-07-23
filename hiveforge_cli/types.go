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
	Name     string            `json:"name"`
	Type     string            `json:"type"` // "file" for file, "dir" for directory
	Size     int64             `json:"size"`
	Children []*DirectoryEntry `json:"children,omitempty"`
	Hashes   *FileHashes       `json:"hashes,omitempty"`
}

type FileHashes struct {
	FileName   string   `json:"name"`
	ChunkSize  int      `json:"chunkSize,omitempty"`
	ChunkCount int      `json:"chunkCount,omitempty"`
	Hashes     []string `json:"hashes"`
	TotalSize  int64    `json:"size"`
}
