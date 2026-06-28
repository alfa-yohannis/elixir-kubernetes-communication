# Tes :cluster butuh node terdistribusi (primary + peer); dikecualikan dari `mix test` baku dan
# dijalankan eksplisit (lihat app/README.md):
#   MIX_ENV=test elixir --name primary@127.0.0.1 --cookie ck -S mix test --only cluster
ExUnit.start(exclude: [:cluster])
