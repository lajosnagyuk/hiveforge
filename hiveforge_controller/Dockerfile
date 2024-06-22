FROM quay.io/lajos_nagy/hiveforge-base-elixir:erlang-27.0-elixir-1.17.0-bookworm-20240617-1 AS compiler
ARG APP_DIR=/app
ARG MIX_ENV=prod
WORKDIR $APP_DIR
ENV MIX_ENV=$MIX_ENV

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

# Set the working directory

# Copy the mix.exs and mix.lock files to the container
COPY mix.exs mix.lock ./

# Fetch the dependencies
RUN mix deps.get

# Copy the rest of the application code to the container
COPY . .

# Delete _build folder
RUN rm -rf _build

# Compile the application for MIX_ENV
RUN mix compile && \
    mix release && \
    cd _build/$MIX_ENV/rel/hiveforge_controller/ && \
    pwd && \
    ls -lash


# Generate test certs using openssl
# RUN openssl genpkey -algorithm RSA -out ca-key.pem -pkeyopt rsa_keygen_bits:2048 && \
#     openssl req -x509 -new -nodes -key ca-key.pem -sha256 -days 3650 -out ca-cert.pem -subj "/C=UK/ST=England/L=London/O=HiveForge Corporation/OU=Operations/CN=localhost" && \
#     openssl genpkey -algorithm RSA -out server-key.pem -pkeyopt rsa_keygen_bits:2048 && \
#     openssl req -new -key server-key.pem -out server.csr -config misc/certificates/test-server-csr.conf && \
#     openssl x509 -req -in server.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem -days 365 -sha256 -extfile misc/certificates/test-server-cert.conf

# Stage 2: runtime stage
FROM hexpm/erlang:27.0-debian-bookworm-20240612-slim

ARG APP_DIR=/app
ARG APP_NAME=hiveforge_controller
ARG MIX_ENV=prod
ARG PORT=4000

WORKDIR $APP_DIR

# Install openssl
RUN apt-get update && apt-get install -y libssl3 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy the app from the compile stage
# # /app/_build/prod/rel/hiveforge_controller
COPY --from=compiler ${APP_DIR}/_build/${MIX_ENV}/rel/${APP_NAME} ./
ENV PATH=/usr/local/elixir/bin:/usr/local/lib:$PATH

# Set the working directory

# Expose the port the app runs on
EXPOSE $PORT

# Start the application
CMD ["bin/hiveforge_controller", "start"]
