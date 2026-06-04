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

### 2. Установка Sentry

Terraform сгенерирует `values_sentry.yaml` из шаблона `values_sentry.yaml.tpl`.

**Порядок:** сначала ClickHouse (§1), затем Sentry.

Установка Sentry:

```bash
helm repo add sentry https://sentry-kubernetes.github.io/charts
helm repo update
kubectl create namespace sentry
helm upgrade --install sentry sentry/sentry --version 31.5.0 -n sentry \
  -f values_sentry.yaml --timeout=7200s --create-namespace
```

Первый запуск занимает 20–40 минут.

После установки Sentry доступен по адресу: **http://sentry.apatsev.org.ru**

### 3. Доступ к Sentry

- **URL**: http://sentry.apatsev.org.ru
- **Email**: admin@sentry.local
- **Password**: admin (задаётся в `templatefile.tf`, переменная `sentry_admin_password`)

Убедитесь, что DNS-запись `sentry.apatsev.org.ru` указывает на внешний IP сервиса ingress-nginx:

```bash
kubectl -n ingress-nginx get svc
```
