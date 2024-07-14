package main

import (
	"golang.org/x/crypto/argon2"
	"encoding/base64"
	"fmt"
	"math/rand"
)

func hashKey(key string) string {
	time := uint32(3)
	memory := uint32(65536)
	threads := uint8(4)
	keyLen := uint32(32)

	salt := make([]byte, 16)
	rand.Read(salt)
	hash := argon2.IDKey([]byte(key), salt, time, memory, threads, keyLen)

	encodedHash := fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, memory, time, threads,
		base64.RawStdEncoding.EncodeToString(nil), // empty salt
		base64.RawStdEncoding.EncodeToString(hash))

	return encodedHash
}
