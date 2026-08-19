## 0. 前置修正

- [x] 0.1 `argocd/application.yml` 的 `exclude` 加入 `openspec/**`（目前只排除 `terraform/**` 與 `argocd/**`；`openspec/config.yaml` 不是 K8s manifest，root Application 遞迴掃描時會因缺少 `apiVersion`/`kind` 產生 sync 錯誤）

## 1. 叢集容量調整

- [x] 1.1 修改 `terraform/variables.tf`，`node_count` 預設值從 2 改為 3
- [x] 1.2 `terraform apply`，確認第 3 個 node 狀態變成 `Ready`

## 2. Namespace 與目錄骨架

- [x] 2.1 建立 `observability/namespace.yml`，定義 `observability` namespace
- [x] 2.2 建立 `observability/` 目錄放置本次所有新檔案

## 3. ArgoCD Application 共用規範

- [x] 3.1 每個 `*-app.yml` 的 `metadata` 加入 `finalizers: [resources-finalizer.argocd.argoproj.io]`——沒有這個 finalizer，刪除 `Application` 資源不會連帶刪除它部署出來的 Helm 資源，`design.md` 的 rollback 步驟依賴此設定才成立
- [x] 3.2 每個 `source.targetRevision`／`chart` 版本固定明確版號（查 Artifact Hub 當下最新穩定版鎖定），不用空白或 `*`，確保多次 `helm install/upgrade` 結果可重現

## 4. kube-state-metrics（Metrics 資料來源之一）

- [x] 4.1 建立 `observability/kube-state-metrics-app.yml`：ArgoCD `Application`，`source.chart` 指向 `prometheus-community/kube-state-metrics`，`destination.namespace: observability`，`syncPolicy` 先設 manual（套用 3.1/3.2 共用規範）
- [x] 4.2 在 `source.helm.values` 設定保守 resource requests/limits（約 128–256Mi RAM）

## 5. Prometheus（Push 接收端）

- [x] 5.1 建立 `observability/prometheus-app.yml`：ArgoCD `Application`，`source.chart` 指向 `prometheus-community/prometheus`（套用 3.1/3.2 共用規範）
- [x] 5.2 `helm.values` 開啟 `server.extraArgs`：`web.enable-remote-write-receiver`
- [x] 5.3 `helm.values` **明確關閉** chart 內建的子元件，避免與本次架構重複或超出範圍：`alertmanager.enabled: false`、`kube-state-metrics.enabled: false`（已用第 4 節獨立 Application 管理）、`prometheus-node-exporter.enabled: false`（node host metrics 已由 Alloy 收集）、`prometheus-pushgateway.enabled: false`
- [x] 5.4 `helm.values` 設定 retention 7 天、PVC 5–10Gi
- [x] 5.5 `helm.values` 設定保守 resource limits（約 256–512Mi RAM）
- [x] 5.6 確認 5.3 關閉後叢集內沒有殘留任何 ServiceMonitor/PodMonitor CRD 或 Prometheus Operator 相關資源（本地 `helm template` 驗證：只渲染出 server Deployment，無 alertmanager/ksm/node-exporter/pushgateway）

## 6. Loki（Logs 儲存）

- [x] 6.1 建立 `observability/loki-app.yml`：ArgoCD `Application`，`source.chart` 指向 `grafana/loki`（套用 3.1/3.2 共用規範）
- [x] 6.2 `helm.values` 設定 `singleBinary`（monolithic）部署模式
- [x] 6.3 `helm.values` 設定 filesystem PVC 儲存、5–10Gi
- [x] 6.4 `helm.values` 明確設定 retention 相關參數，不能只寫天數：`limits_config.retention_period: 168h`、`compactor.retention_enabled: true`、`compactor.retention_delete_delay`、`compactor.delete_request_store`（filesystem 模式需指定），並確認 schema config 使用支援 retention 的格式（`tsdb` 或 `boltdb-shipper`）——預設不會自動刪舊資料，磁碟滿了也不會自行清理
- [x] 6.5 `helm.values` 設定保守 resource limits（約 256–512Mi RAM）
- [x] 6.6（實作中新增）本地 `helm template` 驗證發現 chart 預設還會多裝出 `gateway`（nginx）、`ruler`、`resultsCache`/`chunksCache`（memcached ×2）、`lokiCanary`（DaemonSet）、`test`（helm test hook，依賴 canary）共 6 個非必要元件，已在 values 全部關閉，確認渲染結果只剩 1 個 StatefulSet

## 7. Alloy（Metrics + Logs 收集）

- [x] 7.1 建立 `observability/alloy-app.yml`：ArgoCD `Application`，`source.chart` 指向 `grafana/alloy`（DaemonSet 模式，套用 3.1/3.2 共用規範；`controller.type` chart 預設就是 `daemonset`，不用額外設定）
- [x] 7.2 撰寫 Alloy config 收集 **host** metrics（而非容器自身資料）：`prometheus.exporter.unix` 元件，透過 `controller.volumes.extra` + `alloy.mounts.extra` 掛載 host 的 `/proc`、`/sys`、根檔案系統到 `/host/proc`、`/host/sys`、`/host/root`，並設定對應的 `procfs_path`、`sysfs_path`、`rootfs_path`；用 `prometheus.relabel` + `sys.env("NODE_NAME")`（透過 Downward API 注入的 env var）加上 `node_name` label 方便 Dashboard 依 node 分組
- [x] 7.3（實作調整）kube-state-metrics 是固定的單一 Service，改用 `prometheus.scrape` 直接指定靜態 target `kube-state-metrics.observability.svc.cluster.local:8080`，沒有另外用 `discovery.kubernetes` 動態發現——效果相同（照樣抓到 `/metrics` 轉發到 `prometheus.remote_write`），但少一層依賴，更簡單可靠
- [x] 7.4（實作調整）改用 `loki.source.kubernetes`（透過 K8s API 讀 log，不需要 host mount）+ `discovery.kubernetes` role=pod 提供 targets + `loki.write` 指向 Loki push endpoint；確認不含任何 journald/syslog 收集元件。原本設想的「host mount 讀 log 檔案」改成 API-based 方式，因為 chart 預設 RBAC 已內建此元件所需權限，不需要額外掛 host 目錄，更少 moving parts
- [x] 7.5 確認 Alloy chart 建立的 RBAC（`rbac.create: true` 為預設值）：chart 內建的 ClusterRole 規則已明確涵蓋 `discovery.kubernetes` 與 `loki.source.kubernetes` 所需權限，不需額外設定；host metrics 靠 volume mount 而非 RBAC
- [x] 7.6 `helm.values` 設定保守 resource limits（`requests: 50m/128Mi`、`limits: 256Mi`，DaemonSet 每個 node 各一份）
- [x] 7.7（驗證）用 `docker run grafana/alloy:v1.11.1 alloy fmt` 與 `alloy validate` 對實際 River config 內容做語法與 component 依賴圖驗證，皆無錯誤

## 8. Grafana（視覺化）

- [x] 8.1（實作調整）建立 `observability/grafana-admin.secret.yml`（用 `*.secret.yml` 命名，剛好吃現有 `.gitignore` 第 3 行既有規則，不用另外改 `.gitignore`），內含隨機產生的 admin 帳密（`admin` / 24 字元隨機字串），已確認 `git check-ignore` 生效、從未進過 git 歷史
- [x] 8.2（實作調整）建立 `observability/grafana-app.yml`：ArgoCD `Application`，`source.chart` 指向 `grafana/grafana`（套用 3.1/3.2 共用規範）。**注意**：`helm show chart grafana/grafana` 查出這個舊 repo（`https://grafana.github.io/helm-charts`）的 grafana chart 已標記 `deprecated: true`，官方遷移公告是搬到 `grafana-community/helm-charts`（repo `https://grafana-community.github.io/helm-charts`），舊 repo 2026-01-30 後不再更新——已改用新 repo，`chart: grafana`、`targetRevision: 12.11.0`（新版，非舊 repo 的 10.5.15），Loki/Alloy/Prometheus/kube-state-metrics 這幾個 chart 逐一確認過沒有 deprecated 標記，維持原 repo
- [x] 8.3 `helm.values` 設定 `admin.existingSecret: grafana-admin`（對應 8.1 的 Secret name），`sidecar.datasources.enabled` 與 `sidecar.dashboards.enabled` 皆設 `true`（label key 用 chart 預設值 `grafana_datasource`/`grafana_dashboard`，跟 8.6–8.9 的 ConfigMap label 對齊，不用額外指定）
- [x] 8.4 `helm.values` 設定 `grafana.ini.server.root_url: https://194.195.255.69.nip.io/grafana/` 與 `serve_from_sub_path: true`，對齊第 9 節 Ingress 的 `/grafana` path
- [x] 8.5 `helm.values` 設定保守 resource limits（`requests: 50m/128Mi`、`limits: 256Mi`）
- [x] 8.6 建立 `observability/grafana-datasource-configmap.yml`：帶 `grafana_datasource: "1"` label，內含 Prometheus（`uid: prometheus`）與 Loki（`uid: loki`）兩個 datasource 定義，給 dashboard JSON 用固定 uid 引用
- [x] 8.7 建立 `observability/grafana-dashboard-node.yml`：帶 `grafana_dashboard: "1"` label，4 個 panel（CPU/記憶體/磁碟使用率、網路流量），PromQL 依 `node_name` label 分組
- [x] 8.8 建立 `observability/grafana-dashboard-k8s-health.yml`：帶 dashboard sidecar label，4 個 panel（pod 重啟次數、Deployment/StatefulSet replica 狀態、非 Running pod 列表），限定 `namespace="find-coffee"`
- [x] 8.9 建立 `observability/grafana-dashboard-app-errors.yml`：帶 dashboard sidecar label，LogQL 篩選 `find-coffee` namespace 內含 error/exception/traceback 關鍵字（不分大小寫）的日誌，含錯誤筆數趨勢圖與明細 log panel
- [x] 8.10（驗證）三個 Dashboard JSON 用 Python `json.loads` 驗證語法正確；全部 11 個 `observability/*.yml` 用 `kubectl apply --dry-run=client` 對實際叢集驗證 K8s schema，皆通過

## 9. 對外存取

- [x] 9.1 建立 `observability/grafana-ingress.yml`：沿用共用 host `194.195.255.69.nip.io`，path 設為 `/grafana`，加 `nginx.ingress.kubernetes.io/limit-rps: "5"` 等 rate limit annotation（比照 `ingress-admin.yml`），`backend.service` 指向 `grafana` service port 80（實測 chart 渲染確認的真實 Service 名稱）
- [x] 9.2 TLS 用獨立的 `grafana-tls`（`observability` namespace 內），不引用 `find-coffee` namespace 的 `find-coffee-tls`。靠 `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation 讓 cert-manager 在 `observability` namespace 自動簽發，比照現有 `ingress.yml` 的運作方式
- [x] 9.3（驗證）`kubectl apply --dry-run=client` 通過

## 10. 首次上線與驗證

- [x] 10.1 Push 本次所有變更（含 0.1 的 `argocd/application.yml` 修正與 `observability/*.yml`）進 repo，確認 root ArgoCD Application 自動同步出 5 個 `Application` CRD（`syncPolicy: Manual`，狀態 `OutOfSync/Missing`，尚未部署 workload；用 `argocd app list --core` 確認，不用查 admin 密碼）
- [x] 10.2 手動 `kubectl apply -f observability/grafana-admin.secret.yml`
- [x] 10.3 依序手動 `argocd app sync`：`kube-state-metrics` → `prometheus` → `loki` → `alloy` → `grafana`（用 `argocd app sync <name> --core`，不需要 admin 密碼登入）
- [x] 10.4 驗證每個元件的 Pod 皆為 `Running`（Alloy DaemonSet 在全部 5 個 node 上都有 Pod；Prometheus 只有一個 server pod，確認沒有 alertmanager/node-exporter/pushgateway/kube-state-metrics 子 pod）
- [x] 10.5 驗證 Prometheus 已透過 remote_write 收到 node host metrics（`node_cpu_seconds_total` 40 series，帶正確 `node_name` label）與 kube-state-metrics 資料（`kube_pod_status_phase` 540 series）
- [x] 10.6 驗證 Loki 已收到 pod 的 container logs，且帶正確的 `namespace`/`pod`/`container` label（`{namespace="find-coffee"}` 查得到 pgbouncer log）
- [x] 10.7 用登入後的 session 直接呼叫 Grafana API 驗證：`/api/search` 找到 3 個 Dashboard（Node 資源總覽、K8s 應用健康狀態、應用錯誤日誌）、`/api/datasources` 確認 Prometheus/Loki 兩個 datasource 都在，並透過 `/api/datasources/proxy/uid/<uid>/...` 實際查到 Prometheus（40 series）與 Loki（find-coffee namespace log）資料——等同瀏覽器會看到的結果
- [x] 10.8 驗證從外部瀏覽器可透過 `https://194.195.126.243.nip.io/grafana` 存取（**注意**：實際 LoadBalancer IP 是 `194.195.126.243`，不是規劃階段記的 `194.195.255.69`——那是 IP 換過後的舊資料，已於 9.1/8.4 一併修正）、TLS 由 Let's Encrypt 簽發且驗證通過（`SSL certificate verify ok`）、未登入打 API 回 401、登入後才能查資料、靜態資源連結正確帶 `/grafana/` 前綴

### 實作中發現並修正的問題（原 tasks 沒預期到）

- **Loki ring `replication_factor` 預設 3，但只跑 1 個 replica** → ring 判定「unhealthy instances 太多」，所有查詢回 500。修正：`loki.commonConfig.replication_factor: 1`
- **Grafana 12+ 預設背景下載安裝一批內建 app plugin**，對外呼叫逾時，拖慢啟動到 liveness probe 超時、被反覆重啟殺掉 → 修正：`grafana.ini.plugins.preinstall_disabled: true`
- **`loki.source.kubernetes` 沒有 relabel，log stream 只有 `instance`/`job`，沒有可查詢的 `namespace`/`pod`/`container` label** → 三個 Dashboard 的 LogQL 全部查不到東西。修正：加 `discovery.relabel` 把 `__meta_kubernetes_namespace` 等 meta label 轉成正式 stream label
- **5 個新 workload + 現有 app 全部塞進小節點，`node_count` 3 仍不夠**：排程集中到單一 node、Grafana rollout 新舊 pod 並存的瞬間把該 node 記憶體壓爆，**3 個節點一度全部 `MemoryPressure: True`，正式環境的 `web` Deployment 被 OOM killer 波及降到 0/2 available（真的當機，不是模擬）**。處理：① 幫 4 個單副本元件加 soft pod anti-affinity 分散排程 ② Grafana 改 `Recreate` 部署策略避免換版瞬間雙倍記憶體 ③ 詢問後把 `node_count` 從 3 加到 5（同型號 g6-standard-1，同步改 `terraform.tfvars`，因為它會蓋掉 `variables.tf` 的預設值）④ 清理 evicted/crash 殘留 pod，`web` Deployment 手動重新排程到新 node 後恢復 2/2
- **Ingress host 用的是規劃階段查到的舊 LoadBalancer IP**（`194.195.255.69.nip.io`），叢集在規劃與實作之間重建過，實際 IP 已變成 `194.195.126.243`（現有 `ingress.yml`/`ingress-admin.yml` 已經先改過，只有我們新加的 `grafana-ingress.yml`/`grafana-app.yml` 的 `root_url` 沒同步更新）→ cert-manager 的 HTTP-01 self-check 連不到自己的 challenge path，卡了 37 分鐘簽不出憑證。修正 host 後 20 秒內完成簽發

## 11. 切回自動同步

- [x] 11.1 將 5 個 `observability/*-app.yml` 的 `syncPolicy` 改為 `automated: {prune: true, selfHeal: true}`，比照現有 `argocd/application.yml`
- [x] 11.2 Push 變更，`argocd app list --core` 確認全部 6 個 Application（含 root `find-coffee`）都是 `Synced / Healthy / Auto-Prune`
