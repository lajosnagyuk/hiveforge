package main

type DirectoryHashResult struct {
	RootPath           string          `json:"root"`
	TotalFiles         int             `json:"files"`
	TotalSize          int64           `json:"size"`
	HashingTime        float64         `json:"time"`
	DirectoryStructure *DirectoryEntry `json:"dir"`
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
