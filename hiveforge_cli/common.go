package main

import (
	"encoding/base64"
	"github.com/zeebo/blake3"
	"encoding/hex"
)

func hashKey(key string) string {
	hash := blake3.Sum256([]byte(key))
	return base64.StdEncoding.EncodeToString(hash[:])
}


func solveChallenge(challenge, key string) string {
	hash := blake3.Sum256([]byte(challenge + key))
	return hex.EncodeToString(hash[:])
}
