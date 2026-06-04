# Развёртывание Sentry в Yandex Cloud на Kubernetes

## Что разворачивается

- **Инфраструктура** через Terraform: VPC, Kubernetes Cluster, Ingress-контроллер, публичный IP, DNS.
- **ClickHouse** через [Altinity clickhouse-operator](https://github.com/Altinity/clickhouse-operator) (1 shard × 3 replicas + ClickHouse Keeper).
- **Sentry** через Helm-чарт `sentry/sentry` со встроенными PostgreSQL, Redis и Kafka (KRaft).

## Применение через Terraform

Подготовка:

```bash
export YC_TOKEN=$(yc iam create-token)
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID="<ваш-folder-id>"
```

Создайте `terraform.tfvars`:

```hcl
folder_id = "<ваш-folder-id>"
```

Применение:

```bash
terraform init
terraform apply
```

После успешного применения будут созданы:
- VPC и подсеть в зоне `ru-central1-a`
- Публичный IP и DNS-запись `sentry.apatsev.org.ru`
- Кластер Managed Kubernetes (1 master, 1 node group с автоскейлингом 1–3)
- Ingress-nginx с закреплённым публичным IP

Получите credentials для kubectl:

```bash
yc managed-kubernetes cluster get-credentials --id id_cluster --external --force
```

### 1. ClickHouse (Altinity clickhouse-operator)

ClickHouse для Sentry/Snuba развёрнут в Kubernetes через clickhouse-operator. Кластер: **1 shard × 3 replicas**, namespace `clickhouse`. Координация репликации через **ClickHouse Keeper** (3 узла).

**1.1. Установка clickhouse-operator**

```bash
helm repo add clickhouse-operator https://helm.altinity.com
helm repo update
helm upgrade --install clickhouse-operator clickhouse-operator/altinity-clickhouse-operator \
  --version 0.27.0 \
  --namespace clickhouse-operator \
  --create-namespace \
  -f clickhouse-operator-values.yaml \
  --wait
```

**1.2. ClickHouse Keeper**

```bash
kubectl create namespace clickhouse
kubectl apply -f k8s/clickhouse/clickhouse-keeper-installation.yaml
```

Дождитесь готовности всех подов:

```bash
kubectl -n clickhouse get pods -l clickhouse-keeper.altinity.com/chk=clickhouse-keeper
```

**1.3. Кластер ClickHouse**

```bash
kubectl apply -f k8s/clickhouse/clickhouse-installation.yaml
```

Проверка готовности:

```bash
kubectl -n clickhouse get clickhouseinstallation sentry-clickhouse
```

**1.4. Endpoint для Sentry**

Кластер доступен из namespace `sentry` по адресу:
- **TCP**: `clickhouse-sentry-clickhouse.clickhouse.svc.cluster.local:9000`
- **HTTP**: `clickhouse-sentry-clickhouse.clickhouse.svc.cluster.local:8123`

В `system.clusters` имя кластера — `sentry-cluster`. Эти значения уже заданы в `values_sentry.yaml.tpl`.

> **Примечание:** Если вы используете другой DNS для ClickHouse или другой namespace, отредактируйте `external_clickhouse` в `templatefile.tf` перед `terraform apply`.


## Тестирование issue #2166

Issue [#2166](https://github.com/sentry-kubernetes/charts/issues/2166): после обновления Sentry Helm chart с `30.4.0` на `31.2.0` появляется ошибка **"The organization you were looking for was not found"**.

### Воспроизведение

Кластер уже развёрнут через Terraform (см. «Применение через Terraform» выше). Установка и upgrade выполняются вручную:

# Установка 30.4.0
```bash
helm upgrade --install sentry sentry/sentry --version 30.4.0 -n sentry --wait \
  -f values_sentry.yaml --timeout=7200s --create-namespace
```
# Дождитесь готовности (30-40 мин)

### Доступ к Sentry

- **URL**: http://sentry.apatsev.org.ru
- **Email**: admin@sentry.local
- **Password**: admin (задаётся в `templatefile.tf`, переменная `sentry_admin_password`)

Убедитесь, что DNS-запись `sentry.apatsev.org.ru` указывает на внешний IP сервиса ingress-nginx:

```bash
kubectl -n ingress-nginx get svc
```

```bash
helm upgrade до 31.2.0 sentry sentry/sentry --version 31.2.0 -n sentry --wait \
  -f values_sentry.yaml --timeout=7200s
```

### Диагностика

```bash
# Проверка организации через Sentry CLI
kubectl exec -n sentry deploy/sentry-web -- sentry organizations list
kubectl exec -n sentry deploy/sentry-web -- sentry users list

# Проверка hook-джобов на ошибки
kubectl get jobs -n sentry
kubectl logs -n sentry job/sentry-db-init
kubectl logs -n sentry job/sentry-snuba-migrate
kubectl logs -n sentry job/sentry-user-create

# Поиск ошибки в логах web-пода
kubectl logs -n sentry deploy/sentry-web --tail=100 | grep -i "organization.*not found"
```

### Известные причины issue #2166

1. **Breaking change в 31.0.0**: пароль администратора больше не имеет значения по умолчанию (`aaaa` → `""`). Если `user.password` не задан, user-create hook падает с ошибкой.
2. **Snuba migration issue**: в версиях 30.4.0 и 31.0.0 есть известная проблема с миграциями Snuba (см. [getsentry/self-hosted#4286](https://github.com/getsentry/self-hosted/issues/4286)).
3. **Изменение memcached dependency**: условие подключения memcached изменилось с `sourcemaps.enabled` на `cache.enabled,sourcemaps.enabled`.
