# Stage 1: Build
FROM elixir:1.18-otp-28-alpine AS builder

ENV MIX_ENV=prod

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache build-base git

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY config config
COPY lib lib
COPY priv priv

# Compile the release
RUN mix compile
RUN mix release

# Stage 2: Runtime
FROM debian:bookworm-slim AS runner

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

WORKDIR /app

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 \
      openssl \
      libncurses5 \
      locales \
      ca-certificates \
      postgresql-client \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN groupadd --system app && \
    useradd --system --gid app --home /app app

# Copy the release from the builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/hybridsocial ./

USER app

EXPOSE 4000

ENTRYPOINT ["bin/hybridsocial"]
CMD ["start"]
