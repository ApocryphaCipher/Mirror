# syntax=docker/dockerfile:1

# --- Build stage ---
FROM hexpm/elixir:1.20.4-erlang-29.1.1-debian-bookworm-20260918-slim AS builder

WORKDIR /app
ENV MIX_ENV=prod

# git is needed for the heroicons dependency, which mix.exs fetches straight
# from its GitHub repo rather than Hex; the slim base image doesn't include it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY . .
RUN mix compile
RUN mix assets.deploy
RUN mix release

# --- Runtime stage ---
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /usr/sbin/nologin mirror

ENV HOME=/home/mirror
ENV PHX_SERVER=true
WORKDIR /app

COPY --from=builder /app/_build/prod/rel/mirror ./

RUN mkdir -p /game /data && chown -R mirror:mirror /game /data

USER mirror

EXPOSE 4000

CMD ["bin/mirror", "start"]
