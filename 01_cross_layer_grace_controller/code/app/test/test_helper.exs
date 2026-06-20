# :cluster tests need a distributed primary node; they are excluded from the default
# `mix test` and run explicitly (see app/README.md):
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster
ExUnit.start(exclude: [:cluster])
