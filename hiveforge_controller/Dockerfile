FROM quay.io/lajos_nagy/hiveforge-base-elixir:erlang-27.0-elixir-1.17.0-bookworm-20240623-1 AS compiler

ARG APP_DIR=/app
ARG MIX_ENV=prod
WORKDIR $APP_DIR
ENV MIX_ENV=$MIX_ENV

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy the mix.exs file to the container
COPY mix.exs ./

# Copy the rest of the application code to the container
COPY . .

# Clean up any existing build artifacts
RUN rm -rf _build deps priv test mix.lock

# Get dependencies and compile
RUN mix deps.get && \
    mix deps.compile --force && \
    MIX_DEBUG=1 mix compile --force --verbose

# Compile the application for MIX_ENV and create release
RUN mix release && \
    cd _build/$MIX_ENV/rel/hiveforge_controller/ && \
    pwd && \
    ls -lash

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
COPY --from=compiler ${APP_DIR}/_build/${MIX_ENV}/rel/${APP_NAME} ./

ENV PATH=/usr/local/elixir/bin:/usr/local/lib:$PATH

# Expose the port the app runs on
EXPOSE $PORT

# Set the shell
ENV SHELL=/bin/bash

# Start the application
CMD ["bin/hiveforge_controller", "start"]
