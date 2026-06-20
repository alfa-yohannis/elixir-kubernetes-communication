import Config

# Grace-convergence controller configuration.
config :grace_convergence,
  # termination policy: :static30 | :static300 | :prestop_sleep | :m3 (adaptive)
  grace_policy: :m3,
  # grace bounds and safety margin, in seconds (paper Eq. 2)
  g_min: 5,
  g_max: 120,
  sigma: 5,
  # measured/assumed drain time for in-flight work, seconds
  t_d: 1,
  # baseline fixed grace used by :prestop_sleep
  static_grace: 30,
  # handoff throttle: max workers handed off per second (simulates load); nil = unthrottled
  handoff_rate_limit: nil,
  http_port: 4000,
  start_http: true,
  start_cluster: true

# libcluster topology. Local default = Gossip (multi-node on one host / LAN).
# In Kubernetes this is swapped for Cluster.Strategy.Kubernetes (see config/prod.exs).
config :grace_convergence, :topologies,
  local: [strategy: Cluster.Strategy.Gossip]

import_config "#{config_env()}.exs"
