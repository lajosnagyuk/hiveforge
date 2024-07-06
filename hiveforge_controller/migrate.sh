#!/bin/sh
set -e

# Print environment variables for debugging
echo "DB_USERNAME: $DB_USERNAME"
echo "DB_PASSWORD: $DB_PASSWORD"
echo "DB_NAME: $DB_NAME"
echo "DB_HOST: $DB_HOST"
echo "DB_PORT: $DB_PORT"

# Set database URL
export DATABASE_URL="ecto://$DB_USERNAME:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"

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
