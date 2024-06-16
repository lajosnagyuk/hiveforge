# HiveforgeController

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `hiveforge_controller` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hiveforge_controller, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/hiveforge_controller>.

# generate a test certificate
```bash
openssl genpkey -algorithm RSA -out ca-key.pem -pkeyopt rsa_keygen_bits:2048
openssl req -x509 -new -nodes -key ca-key.pem -sha256 -days 3650 -out ca-cert.pem -subj "/C=UK/ST=England/L=London/O=HiveForge Corporation/OU=Operations/CN=localhost"
openssl genpkey -algorithm RSA -out server-key.pem -pkeyopt rsa_keygen_bits:2048
openssl req -new -key server-key.pem -out server.csr -config misc/certificates/test-server-csr.conf
openssl req -new -key server-key.pem -out server.csr -config misc/certificates/test-server-csr.conf
openssl x509 -req -in server.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem -days 365 -sha256 -extfile misc/certificates/test-server-cert.conf
export HIVEFORGE_CONTROLLER_CERTFILE=$(pwd)/server-cert.pem
export HIVEFORGE_CONTROLLER_KEYFILE=$(pwd)/server-key.pem
```
