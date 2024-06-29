#!/bin/sh
set -e

# Print environment variables for debugging
echo "PGPOOL_USERNAME: $PGPOOL_USERNAME"
echo "PGPOOL_PASSWORD: $PGPOOL_PASSWORD"
echo "PGPOOL_DATABASE: $PGPOOL_DATABASE"
echo "PGPOOL_HOST: $PGPOOL_HOST"
echo "PGPOOL_PORT: $PGPOOL_PORT"

# Set database URL
export DATABASE_URL="ecto://$PGPOOL_USERNAME:$PGPOOL_PASSWORD@$PGPOOL_HOST:$PGPOOL_PORT/$PGPOOL_DATABASE"

# Log database URL for debugging
echo "DATABASE_URL: $DATABASE_URL"

# Create database if not exists
echo "Starting database creation..."
if bin/hiveforge_controller eval "HiveforgeController.Release.create_db()"; then
  echo "Database creation completed."
else
  echo "Database creation failed."
  exit 1
fi

# Run migrations
echo "Starting migrations..."
if bin/hiveforge_controller eval "HiveforgeController.Release.migrate()"; then
  echo "Migrations completed."
else
  echo "Migrations failed."
  exit 1
fi
