## Тестирование issue #2166

Issue [#2166](https://github.com/sentry-kubernetes/charts/issues/2166): после обновления Sentry Helm chart с `30.0.0` на `31.2.0` появляется ошибка **"The organization you were looking for was not found"**.


### 1. ClickHouse (Altinity clickhouse-operator)

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


# Установка 30.0.0
```bash
helm upgrade --install sentry sentry/sentry --version 30.0.0 -n sentry --wait \
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
helm upgrade --install sentry sentry/sentry --version 31.2.0 -n sentry --wait \
  -f values_sentry.yaml --timeout=7200s --create-namespace
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
2. **Snuba migration issue**: в версиях 30.0.0 и 31.0.0 есть известная проблема с миграциями Snuba (см. [getsentry/self-hosted#4286](https://github.com/getsentry/self-hosted/issues/4286)).
3. **Изменение memcached dependency**: условие подключения memcached изменилось с `sourcemaps.enabled` на `cache.enabled,sourcemaps.enabled`.
