import Config
# In tests we don't bind an HTTP port or form a cluster; logic is exercised directly.
config :grace_convergence, start_http: false, start_cluster: false
config :logger, level: :warning
