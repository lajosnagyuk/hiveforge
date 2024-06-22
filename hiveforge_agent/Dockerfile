# Stage 1: compiler stage
FROM quay.io/lajos_nagy/hiveforge-base-elixir:erlang-27.0-elixir-1.17.0-bookworm-20240617-1 AS compiler

ARG APP_DIR=/app
ARG MIX_ENV=prod
ARG APP_NAME=hiveforge_agent
WORKDIR $APP_DIR
ENV MIX_ENV=$MIX_ENV

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy the mix.exs and mix.lock files to the container
COPY mix.exs mix.lock ./

# Fetch the dependencies
RUN mix deps.get

# Copy the rest of the application code to the container
COPY . .

# Compile the application for MIX_ENV
RUN mix compile && \
    mix release

# Stage 2: runtime stage
FROM hexpm/erlang:27.0-debian-bookworm-20240612-slim

ARG APP_DIR=/app
ARG APP_NAME=hiveforge_agent
ARG MIX_ENV=prod
ARG PORT=4000

WORKDIR $APP_DIR

# Install openssl
RUN apt-get update && apt-get install -y libssl3 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy the app from the compile stage
COPY --from=compiler ${APP_DIR}/_build/${MIX_ENV}/rel/${APP_NAME} ./

# Copy the CA certs directory
COPY ./misc/certificates /hiveforge_agent/misc/certificates

# Set environment variables for the runtime stage
ENV MIX_ENV=$MIX_ENV
ENV HIVEFORGE_CONTROLLER_API_ENDPOINT=https://localhost:4000/
ENV HIVEFORGE_CA_CERT_PATH=/hiveforge_agent/misc/certificates/ca-cert.pem
ENV PATH=/usr/local/elixir/bin:/usr/local/lib:$PATH

# Expose the port the app runs on
EXPOSE $PORT

# Start the application
CMD ["bin/hiveforge_agent", "start"]
