# Build dua-tahap: (1) kompilasi release Elixir, (2) image runtime ramping berisi release + kubectl
# (operator butuh kubectl untuk menambal PDB). Image yang sama dipakai peran app dan operator.

# --- Tahap 1: build release ---
FROM elixir:1.16-otp-26 AS build
ENV MIX_ENV=prod
WORKDIR /src
RUN mix local.hex --force && mix local.rebar --force
COPY app/mix.exs app/mix.lock ./
RUN mix deps.get --only prod && mix deps.compile
COPY app/config ./config
COPY app/lib ./lib
RUN mix compile && mix release

# --- Tahap 2: runtime ---
FROM debian:bookworm-slim AS app
RUN apt-get update && apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*
# kubectl (arch-aware) untuk operator.
RUN ARCH="$(case "$(uname -m)" in x86_64) echo amd64;; aarch64|arm64) echo arm64;; *) echo amd64;; esac)" && \
    curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v1.30.0/bin/linux/${ARCH}/kubectl" && \
    chmod +x /usr/local/bin/kubectl
WORKDIR /app
COPY --from=build /src/_build/prod/rel/quorum_budget ./
ENV HOME=/app
CMD ["/app/bin/quorum_budget", "start"]
