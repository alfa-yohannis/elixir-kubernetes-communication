import Config

# In Kubernetes, form the cluster from the headless service via the Kubernetes strategy.
# (Requires RBAC for the pod to list endpoints; see ../k8s/.)
config :grace_convergence, :topologies,
  k8s: [
    strategy: Cluster.Strategy.Kubernetes,
    config: [
      mode: :ip,
      kubernetes_ip_lookup_mode: :pods,
      kubernetes_node_basename: "grace",
      kubernetes_selector: "app=grace",
      kubernetes_namespace: "default",
      polling_interval: 3_000
    ]
  ]
