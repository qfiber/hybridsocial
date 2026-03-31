#!/bin/sh
# Generate secrets on first startup.
# Writes to .env file if values don't exist yet.

ENV_FILE="${1:-.env}"

# ---- SECRET_KEY_BASE ----
if grep -q "^SECRET_KEY_BASE=." "$ENV_FILE" 2>/dev/null && \
   ! grep -q "^SECRET_KEY_BASE=changeme" "$ENV_FILE" 2>/dev/null; then
  echo "[secrets] SECRET_KEY_BASE already set in $ENV_FILE, skipping."
else
  echo "[secrets] Generating SECRET_KEY_BASE..."
  SECRET=$(openssl rand -base64 64 | tr -d '\n')
  if grep -q "^SECRET_KEY_BASE=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$SECRET|" "$ENV_FILE"
  else
    echo "" >> "$ENV_FILE"
    echo "# Phoenix secret key base (auto-generated, do not delete)" >> "$ENV_FILE"
    echo "SECRET_KEY_BASE=$SECRET" >> "$ENV_FILE"
  fi
  echo "[secrets] SECRET_KEY_BASE generated and saved to $ENV_FILE"
fi

# ---- Instance actor keys ----
if grep -q "^INSTANCE_PUBLIC_KEY=." "$ENV_FILE" 2>/dev/null; then
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
