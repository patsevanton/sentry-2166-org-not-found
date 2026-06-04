user:
  create: true
  email: "${user_email}"
  password: "${sentry_admin_password}"

ingress:
  enabled: ${ingress_enabled}
  ingressClassName: "${ingress_class_name}"
  hostname: "${ingress_hostname}"

system:
  url: "${system_url}"

config:
  sentryConfPy: |
    SENTRY_AIR_GAP = True

externalClickhouse:
  host: "${external_clickhouse.host}"
  tcpPort: ${external_clickhouse.tcpPort}
  httpPort: ${external_clickhouse.httpPort}
  username: "${external_clickhouse.username}"
  password: "${external_clickhouse.password}"
  database: "${external_clickhouse.database}"
  singleNode: ${external_clickhouse.singleNode}
  clusterName: "${external_clickhouse.clusterName}"
  distributedClusterName: "${external_clickhouse.distributedClusterName}"
  secure: ${external_clickhouse.secure}

postgresql:
  enabled: true

redis:
  enabled: true

kafka:
  enabled: true
  kraft:
    enabled: true
  provisioning:
    enabled: true
    replicationFactor: 1
