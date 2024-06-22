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
# Generate CA key and certificate
openssl genpkey -algorithm RSA -out misc/certificates/ca.key -pkeyopt rsa_keygen_bits:2048

openssl req -x509 -new -nodes -key misc/certificates/ca.key -sha256 -days 365 -out misc/certificates/ca.crt -config misc/certificates/ca.conf


# Generate server key and certificate
openssl genpkey -algorithm RSA -out misc/certificates/server.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key misc/certificates/server.key -out misc/certificates/server.csr -config misc/certificates/server_csr.conf

openssl x509 -req -in misc/certificates/server.csr -CA misc/certificates/ca.crt -CAkey misc/certificates/ca.key -CAcreateserial -out misc/certificates/server.crt -days 365 -sha256 -extfile misc/certificates/server_csr.conf -extensions req_ext

# Verify the certificate
openssl x509 -in misc/certificates/server.crt -text -noout
openssl verify -CAfile misc/certificates/ca.crt misc/certificates/server.crt
```

# Export the paths as environment variables
export HIVEFORGE_CONTROLLER_CERTFILE=$(pwd)/misc/certificates/server-cert.pem
export HIVEFORGE_CONTROLLER_KEYFILE=$(pwd)/misc/certificates/server-key.pem
```


# Testing and Development notes
```bash
mix deps get
```
Don't forget to create certificate files for testing, and mount them properly for production. TODO: Add mounting and generation in the Helm chart.
1. To run the tests, run `mix test`
2. to run a REPL: `iex -S mix run` and `recompile`


# Run from container doing development:
```bash
make dev-run

# pass in some variables
HIVEFORGE_CONTROLLER_CERTFILE=/hiveforge_controller/misc/certificates/test-server-cert.pem \
HIVEFORGE_CONTROLLER_KEYFILE=/hiveforge_controller/misc/certificates/test-server-key.pem \
make dev-run
```
