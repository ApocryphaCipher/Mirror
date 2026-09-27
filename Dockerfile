# syntax=docker/dockerfile:1

# --- Build stage ---
FROM hexpm/elixir:1.20.4-otp-29.1 AS builder

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY . .
RUN mix assets.deploy
RUN mix release

# --- Runtime stage ---
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /usr/sbin/nologin mirror

ENV HOME=/home/mirror
WORKDIR /app

COPY --from=builder /app/_build/prod/rel/mirror/bin/mirror bin/mirror
COPY --from=builder /app/_build/prod/rel/mirror/releases releases/

RUN mkdir -p /game /data && chown -R mirror:mirror /game /data

USER mirror

EXPOSE 4000

CMD ["bin/mirror", "start"]
