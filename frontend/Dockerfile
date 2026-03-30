# Stage 1: Build
FROM node:22-alpine AS builder

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json* ./
RUN npm ci

# Install adapter-node for production
RUN npm install @sveltejs/adapter-node

# Copy source
COPY . .

# Swap adapter-auto for adapter-node in svelte.config.js
RUN sed -i "s|import adapter from '@sveltejs/adapter-auto'|import adapter from '@sveltejs/adapter-node'|" svelte.config.js

# Build
ENV NODE_ENV=production
RUN npm run build

# Stage 2: Runtime
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV ORIGIN=http://localhost:3000

# Copy built output
COPY --from=builder /app/build ./build
COPY --from=builder /app/package.json ./

# Install only production deps needed by adapter-node
RUN npm install --omit=dev 2>/dev/null || true

# Create non-root user
RUN addgroup -S app && adduser -S app -G app
USER app

EXPOSE 3000

CMD ["node", "build"]
