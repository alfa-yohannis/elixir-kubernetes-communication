# Satu image untuk DUA peran (env GRACE_ROLE memilih app vs operator). Konteks build = folder code/.
#   docker build -t grace:dev code/
#
# Memakai multi-stage build: tahap "build" mengompilasi rilis Elixir, lalu tahap "app" hanya menyalin
# hasilnya (image akhir jadi kecil, tanpa toolchain build).

# --- Tahap 1: build rilis produksi ---
FROM elixir:1.16-alpine AS build
RUN apk add --no-cache build-base git
WORKDIR /src
ENV MIX_ENV=prod
# Salin manifest dependensi dulu lalu unduh deps — agar layer cache Docker tidak terbuang saat kode
# berubah tetapi dependensinya tetap.
COPY app/mix.exs app/mix.lock* ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only prod
COPY app/ .
RUN mix deps.compile && mix release

# --- Tahap 2: image runtime ---
# Base yang SAMA dengan builder agar NIF crypto ter-link ke OpenSSL yang cocok (menghindari error
# "EVP_MD_CTX_get_size_ex: symbol not found" akibat ketidakcocokan alpine/OpenSSL).
FROM elixir:1.16-alpine AS app
# wget (untuk preStop hook) sudah ada di busybox; tambahkan curl + kubectl untuk peran operator.
RUN apk add --no-cache curl \
 && ARCH=$(case "$(uname -m)" in x86_64) echo amd64;; aarch64|arm64) echo arm64;; *) echo amd64;; esac) \
 && curl -sSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.30.0/bin/linux/${ARCH}/kubectl" \
 && chmod +x /usr/local/bin/kubectl
WORKDIR /app
# Salin rilis yang sudah dibangun dari tahap "build".
COPY --from=build /src/_build/prod/rel/grace_convergence ./
ENV HOME=/app
# Port 4000 = HTTP (probe/drain); 4369 = epmd (penemuan node BEAM untuk distribusi).
EXPOSE 4000 4369
CMD ["bin/grace_convergence", "start"]
