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

# Stage 2: Runtime — must match the builder's Alpine version for OpenSSL compatibility
FROM elixir:1.18-otp-28-alpine AS runner

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

WORKDIR /app

# Install runtime dependencies (Elixir/OTP already present from base)
RUN apk add --no-cache \
      libstdc++ \
      ncurses-libs \
      ca-certificates \
      postgresql-client

# Create a non-root user
RUN addgroup --system app && \
    adduser --system --ingroup app --home /app app

# Copy the release from the builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/hybridsocial ./

USER app

EXPOSE 4000

ENTRYPOINT ["bin/hybridsocial"]
CMD ["start"]
