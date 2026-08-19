## 0. 前置修正

- [ ] 0.1 `argocd/application.yml` 的 `exclude` 加入 `openspec/**`（目前只排除 `terraform/**` 與 `argocd/**`；`openspec/config.yaml` 不是 K8s manifest，root Application 遞迴掃描時會因缺少 `apiVersion`/`kind` 產生 sync 錯誤）

## 1. 叢集容量調整

- [ ] 1.1 修改 `terraform/variables.tf`，`node_count` 預設值從 2 改為 3
- [ ] 1.2 `terraform apply`，確認第 3 個 node 狀態變成 `Ready`

## 2. Namespace 與目錄骨架

- [ ] 2.1 建立 `observability/namespace.yml`，定義 `observability` namespace
- [ ] 2.2 建立 `observability/` 目錄放置本次所有新檔案

## 3. ArgoCD Application 共用規範

- [ ] 3.1 每個 `*-app.yml` 的 `metadata` 加入 `finalizers: [resources-finalizer.argocd.argoproj.io]`——沒有這個 finalizer，刪除 `Application` 資源不會連帶刪除它部署出來的 Helm 資源，`design.md` 的 rollback 步驟依賴此設定才成立
- [ ] 3.2 每個 `source.targetRevision`／`chart` 版本固定明確版號（查 Artifact Hub 當下最新穩定版鎖定），不用空白或 `*`，確保多次 `helm install/upgrade` 結果可重現

## 4. kube-state-metrics（Metrics 資料來源之一）

- [ ] 4.1 建立 `observability/kube-state-metrics-app.yml`：ArgoCD `Application`，`source.chart` 指向 `prometheus-community/kube-state-metrics`，`destination.namespace: observability`，`syncPolicy` 先設 manual（套用 3.1/3.2 共用規範）
- [ ] 4.2 在 `source.helm.values` 設定保守 resource requests/limits（約 128–256Mi RAM）

## 5. Prometheus（Push 接收端）

- [ ] 5.1 建立 `observability/prometheus-app.yml`：ArgoCD `Application`，`source.chart` 指向 `prometheus-community/prometheus`（套用 3.1/3.2 共用規範）
- [ ] 5.2 `helm.values` 開啟 `server.extraArgs`：`web.enable-remote-write-receiver`
- [ ] 5.3 `helm.values` **明確關閉** chart 內建的子元件，避免與本次架構重複或超出範圍：`alertmanager.enabled: false`、`kube-state-metrics.enabled: false`（已用第 4 節獨立 Application 管理）、`prometheus-node-exporter.enabled: false`（node host metrics 已由 Alloy 收集）、`prometheus-pushgateway.enabled: false`
- [ ] 5.4 `helm.values` 設定 retention 7 天、PVC 5–10Gi
- [ ] 5.5 `helm.values` 設定保守 resource limits（約 256–512Mi RAM）
- [ ] 5.6 確認 5.3 關閉後叢集內沒有殘留任何 ServiceMonitor/PodMonitor CRD 或 Prometheus Operator 相關資源

## 6. Loki（Logs 儲存）

- [ ] 6.1 建立 `observability/loki-app.yml`：ArgoCD `Application`，`source.chart` 指向 `grafana/loki`（套用 3.1/3.2 共用規範）
- [ ] 6.2 `helm.values` 設定 `singleBinary`（monolithic）部署模式
- [ ] 6.3 `helm.values` 設定 filesystem PVC 儲存、5–10Gi
- [ ] 6.4 `helm.values` 明確設定 retention 相關參數，不能只寫天數：`limits_config.retention_period: 168h`、`compactor.retention_enabled: true`、`compactor.retention_delete_delay`、`compactor.delete_request_store`（filesystem 模式需指定），並確認 schema config 使用支援 retention 的格式（`tsdb` 或 `boltdb-shipper`）——預設不會自動刪舊資料，磁碟滿了也不會自行清理
- [ ] 6.5 `helm.values` 設定保守 resource limits（約 256–512Mi RAM）

## 7. Alloy（Metrics + Logs 收集）

- [ ] 7.1 建立 `observability/alloy-app.yml`：ArgoCD `Application`，`source.chart` 指向 `grafana/alloy`（DaemonSet 模式，套用 3.1/3.2 共用規範）
- [ ] 7.2 撰寫 Alloy config 收集 **host** metrics（而非容器自身資料）：`prometheus.exporter.unix` 元件，掛載 host 的 `/proc`、`/sys`、根檔案系統，並設定對應的 `procfs_path`、`sysfs_path`、`rootfs_path` 指向掛載路徑；加上 node 識別 label（如 `node_name`）方便 Dashboard 依 node 分組
- [ ] 7.3 撰寫 Alloy config：`discovery.kubernetes` + `prometheus.scrape` 抓 kube-state-metrics 的 `/metrics` + `prometheus.remote_write` 指向 Prometheus 的 remote-write endpoint
- [ ] 7.4 撰寫 Alloy config：`loki.source.kubernetes`（或等效 container log 收集元件，含 pod log 目錄的 host mount）+ `loki.write` 指向 Loki 的 push endpoint，確認不含 node 系統日誌（journald/syslog）收集元件
- [ ] 7.5 確認 Alloy chart 建立的 RBAC（ClusterRole/ClusterRoleBinding）涵蓋 `discovery.kubernetes`、host metrics、log 收集所需權限
- [ ] 7.6 `helm.values` 設定保守 resource limits（約 128–256Mi RAM，DaemonSet 每個 node 各一份）

## 8. Grafana（視覺化）

- [ ] 8.1 建立不進 Git 的 `observability/grafana-admin-secret.yml`（加進 `.gitignore`），內含 admin 帳密
- [ ] 8.2 建立 `observability/grafana-app.yml`：ArgoCD `Application`，`source.chart` 指向 `grafana/grafana`（套用 3.1/3.2 共用規範）
- [ ] 8.3 `helm.values` 設定 `admin.existingSecret` 指向 8.1 的 Secret，`sidecar.datasources.enabled` 與 `sidecar.dashboards.enabled` 皆開啟並指定對應的 label key
- [ ] 8.4 `helm.values` 設定 `grafana.ini.server.root_url` 與 `grafana.ini.server.serve_from_sub_path: true`，對齊第 9 節 Ingress 的 `/grafana` path——沒設定的話登入 redirect、靜態資源載入、Grafana Live（WebSocket）都會導向錯誤路徑
- [ ] 8.5 `helm.values` 設定保守 resource limits（約 256Mi RAM）
- [ ] 8.6 建立 `observability/grafana-datasource-configmap.yml`：帶 datasource sidecar label，內含 Prometheus 與 Loki 兩個 datasource 定義
- [ ] 8.7 建立 `observability/grafana-dashboard-node.yml`：帶 dashboard sidecar label，Dashboard JSON 呈現各 node CPU/RAM/disk/network
- [ ] 8.8 建立 `observability/grafana-dashboard-k8s-health.yml`：帶 dashboard sidecar label，Dashboard JSON 呈現 pod 重啟次數與 Deployment/StatefulSet replica 狀態（來自 kube-state-metrics）
- [ ] 8.9 建立 `observability/grafana-dashboard-app-errors.yml`：帶 dashboard sidecar label，Dashboard JSON 用 LogQL 篩選 web/celery 等 pod 中 error/exception 相關日誌

## 9. 對外存取

- [ ] 9.1 建立 `observability/grafana-ingress.yml`：沿用共用 host `194.195.255.69.nip.io`，path 設為 `/grafana`，加 `nginx.ingress.kubernetes.io/limit-rps` 等 rate limit annotation（比照 `ingress-admin.yml`）
- [ ] 9.2 TLS **不可**直接引用 `find-coffee` namespace 的 `find-coffee-tls`（Secret 是 namespace-scoped，跨 namespace 引用無效）。改為在此 Ingress 上加 `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation，讓 cert-manager 在 `observability` namespace 內自動簽發並建立獨立的 TLS Secret（如 `grafana-tls`），比照現有 `ingress.yml` 的運作方式（該檔案本身也是靠這個 annotation 觸發自動簽發，而非手動共用憑證）

## 10. 首次上線與驗證

- [ ] 10.1 Push 本次所有變更（含 0.1 的 `argocd/application.yml` 修正與 `observability/*.yml`）進 repo，確認 root ArgoCD Application 自動同步出 5 個 `Application` CRD（`syncPolicy: manual`，尚未部署 workload）
- [ ] 10.2 手動 `kubectl apply -f observability/grafana-admin-secret.yml`
- [ ] 10.3 依序手動 `argocd app sync`：`kube-state-metrics` → `prometheus` → `loki` → `alloy` → `grafana`
- [ ] 10.4 驗證每個元件的 Pod 皆為 `Running`（含 Alloy DaemonSet 在 3 個 node 上都有 Pod，且 Prometheus 只有一個 server pod、沒有 alertmanager/node-exporter/pushgateway pod）
- [ ] 10.5 驗證 Prometheus 已透過 remote_write 收到 node host metrics（確認是 host 數值而非容器自身數值）與 kube-state-metrics 資料
- [ ] 10.6 驗證 Loki 已收到 web/celery 等 pod 的 container logs
- [ ] 10.7 驗證 Grafana 三個 Dashboard 皆能正確顯示資料（Node 資源、K8s 應用健康、應用錯誤日誌）
- [ ] 10.8 驗證從外部瀏覽器可透過 `https://194.195.255.69.nip.io/grafana` 存取、TLS 有效、需要登入，且頁面內部連結/靜態資源沒有導向錯誤路徑

## 11. 切回自動同步

- [ ] 11.1 將 5 個 `observability/*-app.yml` 的 `syncPolicy` 改為 `automated: {prune: true, selfHeal: true}`，比照現有 `argocd/application.yml`
- [ ] 11.2 Push 變更，確認 ArgoCD 後續改動皆自動同步
