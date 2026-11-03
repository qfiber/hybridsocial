# Stage 1: Build
FROM node:22-alpine AS builder

WORKDIR /app

# Install dependencies. adapter-node is a pinned devDependency in the
# lockfile; it used to be `npm install`ed here unversioned, which broke the
# image the day adapter-node 6 (SvelteKit 3 only) was published.
COPY package.json package-lock.json ./
RUN npm ci

# Copy source
COPY . .

# Use production svelte config with adapter-node
RUN cp svelte.config.node.js svelte.config.js

# Build. VITE_WEB_SHA is baked into the bundle (import.meta.env) so the
# footer can show which frontend commit is deployed. Pass with
# `docker compose build --build-arg GIT_SHA=<short-sha> frontend`.
ARG GIT_SHA=dev
ENV NODE_ENV=production
ENV VITE_WEB_SHA=$GIT_SHA
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
