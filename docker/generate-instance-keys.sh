#!/bin/sh
# Generate instance actor RSA keypair on first startup.
# Writes to .env file if keys don't exist yet.

ENV_FILE="${1:-.env}"

if grep -q "INSTANCE_PUBLIC_KEY=" "$ENV_FILE" 2>/dev/null; then
  echo "[keys] Instance keys already exist in $ENV_FILE, skipping generation."
  exit 0
fi

echo "[keys] Generating instance actor RSA keypair..."

# Generate 2048-bit RSA key
PRIVATE_KEY=$(openssl genrsa 2048 2>/dev/null)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | openssl rsa -pubout 2>/dev/null)

# Base64 encode (single line, no wrapping)
PRIVATE_B64=$(echo "$PRIVATE_KEY" | base64 -w 0)
PUBLIC_B64=$(echo "$PUBLIC_KEY" | base64 -w 0)

# Append to .env
echo "" >> "$ENV_FILE"
echo "# Instance actor RSA keypair (auto-generated, do not delete)" >> "$ENV_FILE"
echo "INSTANCE_PUBLIC_KEY=$PUBLIC_B64" >> "$ENV_FILE"
echo "INSTANCE_PRIVATE_KEY=$PRIVATE_B64" >> "$ENV_FILE"

echo "[keys] Instance keys generated and saved to $ENV_FILE"
