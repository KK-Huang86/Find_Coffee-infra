## Why

目前 find_coffee-infra 沒有任何可觀測性工具：無法看到 node 資源使用狀況、無法看到 web/celery 等應用的健康狀態，應用出錯時只能靠 `kubectl logs` 逐一手動查。隨著服務持續運作，需要一套集中的 metrics/logs 平台，才能在問題發生時快速定位原因。

## What Changes

- 新增 `observability` namespace，與應用層 `find-coffee` namespace 分離
- 新增 5 個獨立 ArgoCD Application（`observability/` 目錄下），每個各自 `source.chart` 直接指向官方 Helm repo：
  - `grafana/alloy`：DaemonSet，收集每個 node 的 host metrics 與所有 pod 的 container logs（stdout/stderr）
  - `prometheus-community/prometheus`：輕量單體 chart，開啟 `--web.enable-remote-write-receiver` 接收 Alloy 的 push；**不**使用 kube-prometheus-stack、**不**裝 Prometheus Operator/CRD/ServiceMonitor
  - `prometheus-community/kube-state-metrics`：提供 K8s 物件狀態（pod/deployment/container），供 Alloy scrape 後一併 remote_write 到 Prometheus
  - `grafana/loki`：singleBinary（monolithic）模式，filesystem PVC 儲存（不用物件儲存/S3）
  - `grafana/grafana`：透過 sidecar 機制動態載入 datasource（Prometheus + Loki）與 3 個 Dashboard ConfigMap
- 新增 3 個 Grafana Dashboard（帶 `grafana_dashboard` sidecar label 的 ConfigMap）：Node 資源總覽、K8s 應用健康狀態、應用錯誤日誌
- 新增 1 條 Ingress rule，沿用現有共用 host `194.195.255.69.nip.io`，以 `/grafana` path 對外開放 Grafana，套用現有 `letsencrypt-prod` TLS 與 nginx rate limit
- `terraform/variables.tf` 的 `node_count` 從 2 調整為 3，容納新增的常駐工作負載
- 幫 5 個新元件設定保守的 CPU/RAM resource requests/limits，避免排擠既有的 web/celery/postgres/redis
- 這 5 個新 ArgoCD Application 首次上線 `syncPolicy` 設為 manual，待人工驗證跑起來無誤後，再手動改回 `automated`（比照現有 `argocd/application.yml`）

**Non-goals（明確排除，不在此次變更範圍）**：Prometheus Operator/ServiceMonitor/CRD、kube-prometheus-stack、Alertmanager 告警、Loki 物件儲存/S3、node 系統日誌（journald/syslog）收集、Grafana datasource 寫死於 Helm values、多副本高可用設定。

## Capabilities

### New Capabilities
- `observability/metrics-pipeline`: Alloy 收集每個 node 的 host metrics 與 kube-state-metrics 的 K8s 物件狀態，並以 push 模式（remote_write）送進 Prometheus 儲存
- `observability/logs-pipeline`: Alloy 收集所有 pod 的 container logs 並送進 Loki 儲存與查詢
- `observability/dashboards`: Grafana 透過 sidecar 動態載入 datasource 與 Dashboard，呈現 node 資源、K8s 應用健康、應用錯誤日誌三個視圖
- `observability/external-access`: Grafana 透過既有 Ingress host 對外開放，並以密碼保護管理員存取

### Modified Capabilities
（無，`openspec/specs/` 目前為空，此變更全數為新能力）

## Impact

- **新增檔案**：`observability/*.yml`（5 個 ArgoCD Application、3 個 Dashboard ConfigMap、1 個 Datasource ConfigMap、1 個對外 Ingress）、`observability/grafana-admin-secret.yml`（不進 Git）
- **修改檔案**：`terraform/variables.tf`（`node_count` 2→3）
- **叢集資源**：新增 1 個 worker node、新增 `observability` namespace 與其下 5 個常駐工作負載（含 Alloy DaemonSet ×3 node）
- **不影響**：現有 `find-coffee` namespace 內的 web/celery/postgres/redis/pgbouncer 部署邏輯本身（僅共用叢集資源，已透過 resource limits 降低排擠風險）
