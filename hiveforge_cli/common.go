package main

import (
    "crypto/sha256"
    "encoding/hex"
)

// HashKey creates a SHA-256 hash of the input string and returns it as a hexadecimal string
func HashKey(key string) string {
    hasher := sha256.New()
    hasher.Write([]byte(key))
    return hex.EncodeToString(hasher.Sum(nil))
}
