locals {
  sentry_admin_password = "admin"

  external_clickhouse = {
    host                   = "clickhouse-sentry-clickhouse.clickhouse.svc.cluster.local"
    tcpPort                = 9000
    httpPort               = 8123
    username               = "default"
    password               = ""
    database               = "default"
    singleNode             = false
    clusterName            = "sentry-cluster"
    distributedClusterName = "sentry-cluster"
    secure                 = false
  }

  sentry_config = templatefile("${path.module}/values_sentry.yaml.tpl", {
    sentry_admin_password = local.sentry_admin_password
    user_email            = "admin@sentry.local"
    system_url            = "http://sentry.apatsev.org.ru"
    ingress_enabled       = true
    ingress_hostname      = "sentry.apatsev.org.ru"
    ingress_class_name    = "traefik"
    external_clickhouse   = local.external_clickhouse
  })
}

resource "local_file" "write_sentry_config" {
  content         = local.sentry_config
  filename        = "values_sentry.yaml"
  file_permission = "0644"
}
