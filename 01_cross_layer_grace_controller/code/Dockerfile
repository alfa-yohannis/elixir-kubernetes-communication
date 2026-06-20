# Single image for both roles (GRACE_ROLE selects app vs operator). Build context = code/.
#   docker build -t grace:dev code/
FROM elixir:1.16-alpine AS build
RUN apk add --no-cache build-base git
WORKDIR /src
ENV MIX_ENV=prod
COPY app/mix.exs app/mix.lock* ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only prod
COPY app/ .
RUN mix deps.compile && mix release

# Same base as the builder so the crypto NIF links the matching OpenSSL (avoids
# "EVP_MD_CTX_get_size_ex: symbol not found" from an alpine/OpenSSL mismatch).
FROM elixir:1.16-alpine AS app
# wget (preStop hook) is in busybox; add curl + kubectl for the operator role
RUN apk add --no-cache curl \
 && curl -sSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl \
 && chmod +x /usr/local/bin/kubectl
WORKDIR /app
COPY --from=build /src/_build/prod/rel/grace_convergence ./
ENV HOME=/app
EXPOSE 4000 4369
CMD ["bin/grace_convergence", "start"]
