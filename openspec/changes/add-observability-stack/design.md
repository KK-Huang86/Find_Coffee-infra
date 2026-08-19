## Context

見 `proposal.md - Why`。現有事實限制這次設計：

- Linode LKE，`node_count=2`、`node_type=g6-standard-1`（各 1 vCPU/2GB RAM），叢集資源緊繃；現有 web/celery/postgres/redis/pgbouncer 都沒有設定 CPU/RAM requests/limits
- GitOps 由 `argocd/application.yml` 追蹤 repo 根目錄（`path: .`, `recurse: true`, `exclude: '{terraform/**,argocd/**}'`, `automated: {prune, selfHeal}`）
- 對外流量走共用 host `194.195.255.69.nip.io` + path 分流，TLS 由 cert-manager 的 `letsencrypt-prod` ClusterIssuer 簽發
- 機密不進 Git，比照 `secret.yml` 手動 `kubectl apply` 的既有模式
- Terraform 只管「雞生蛋」的 bootstrap 元件（ingress-nginx、cert-manager、ArgoCD 本身），其餘一律走 ArgoCD

## Goals / Non-Goals

**Goals:**
- 用最少常駐元件把 Alloy→Loki/Prometheus→Grafana 這條路徑跑起來，且完全走現有 GitOps 模式
- 新增元件不能把既有 app 擠爆（OOM/CPU 飢餓）
- Dashboard 內容要能回答「node 資源夠不夠」「應用有沒有在正常跑」「應用哪裡出錯」三個問題

**Non-Goals:**
- 不做告警（Alertmanager／任何 webhook 通知）
- 不做多副本高可用（Loki/Prometheus/Grafana 都是單副本）
- 不接物件儲存（S3/Linode Object Storage）
- 不裝 Prometheus Operator/CRD，不用 ServiceMonitor/PodMonitor

## Decisions

### 1. ArgoCD Application 而非 Terraform helm_release
沿用 repo 既有的「bootstrap（Terraform）vs 應用層（ArgoCD）」分界：ingress-nginx/cert-manager/ArgoCD 是叢集能跑 GitOps 前的先決條件，才不得不用 Terraform。Observability 不是先決條件，屬於可迭代的應用層資源，理應跟 web/celery 一樣走 GitOps，改動只需要 `git push`。

### 2. 每元件各自獨立 ArgoCD Application，`source.chart` 直連官方 Helm repo
考慮過 App-of-Apps（一個 parent Application 管一個 `observability/` 目錄下的子 Application）與手動 `helm template` 轉 raw manifest 兩種替代方案。前者是好架構但現階段只有 5 個元件，多一層間接反而增加維護成本；後者升版要手動重新 render，違背「宣告式 + 自動同步」的 repo 精神。故選最直接的做法：5 個平行的 `Application`，各自的 `source.chart`/`source.repoURL`/`targetRevision` 指向官方 chart，透過 `source.helm.values` 帶入本次設計的參數。

### 3. Metrics 用 Push（Alloy `remote_write`）而非 Pull（ServiceMonitor + Prometheus Operator）
Pull 模式是多數教學文的預設路徑（`kube-prometheus-stack` + Operator + CRD），但 Operator 常駐開銷（controller pod、webhook、CRD reconcile）對 2 個 2GB RAM node 的叢集是不必要的負擔。Alloy 原生支援 `prometheus.remote_write` 元件，Prometheus 只要開 `--web.enable-remote-write-receiver` 就能接收，元件數量更少、設定更直接。取捨：失去 Operator 提供的自動 scrape 目標發現，但這裡的 scrape 目標集合本來就小且固定（各 node 的 Alloy + kube-state-metrics），用 Alloy 自身的 `discovery.kubernetes` 元件去發現、再一起 remote_write 出去即可，不需要 Prometheus 端做發現。

### 4. kube-state-metrics 走獨立 Application，由 Alloy scrape 後轉送
`prometheus-community/prometheus` chart 實際上預設會**內建**部署 `kube-state-metrics`、`prometheus-node-exporter`、`alertmanager`、`prometheus-pushgateway` 這幾個子元件（先前版本此文件誤寫成「不包含」，已更正）。這些子元件必須在 Prometheus 的 `helm.values` 中明確關閉（`kube-state-metrics.enabled: false` 等，見 `tasks.md` 5.3），否則會跟本次架構重複部署，或裝進 non-goals 明確排除的 Alertmanager。關閉之後，`kube-state-metrics` 改由獨立 chart 部署，讓 Alloy 用 `prometheus.scrape` 元件抓它的 `/metrics`，跟 node host metrics 一起走同一條 `remote_write` pipeline 送出，不需要 Prometheus 直接碰它——這樣版本、資源設定都能獨立控管，也符合「每元件各自獨立 Application」的既定模式（決策 2）。

### 5. Loki singleBinary + filesystem PVC
叢集規模不需要考慮 Loki 的 distributed（read/write/backend 分離）模式。物件儲存能拿到更長保留期與更高持久性，但要多開 Linode Object Storage bucket、管理 access key，屬於額外的雲端依賴，跟現階段「先讓路徑跑起來」的目標不成比例。先用 filesystem PVC，之後有需要再遷移（見 `docs/adr` 若後續建立）。

實作時用 `helm template` 實際渲染確認：`grafana/loki` chart 即使選了 `SingleBinary` 模式，預設仍會一併裝出 `gateway`（nginx 反代）、`ruler`、`resultsCache`/`chunksCache`（各一個 memcached）、`lokiCanary`（每個 node 一份的自我測試 DaemonSet）——這些都不是「一個 pod 搞定」的必要部分，已在 Helm values 全部關閉，實測渲染結果確認只剩 1 個 StatefulSet。

### 6. Datasource 與 Dashboard 都用 sidecar ConfigMap 動態載入
Grafana chart 的 sidecar container 會 watch 帶特定 label 的 ConfigMap 並自動 reload，不需要重啟 Grafana pod。Datasource 只有 2 個（Prometheus、Loki），原本考慮直接寫在 Helm values 更省事，但為了跟 Dashboard 走同一套機制、維持設定來源單一化（都是「套用一個 ConfigMap 就生效」），改用 sidecar 統一處理。

### 7. `node_count` 2→3 + 新元件保守 resource limits
兩者互補，缺一不可：只加 node 解決不了「單一元件突然吃爆記憶體」的問題（仍會 OOM 排擠鄰居）；只設 limits 解決不了「總容量真的不夠、Pod 一直 Pending」的問題。Alloy 是 DaemonSet，加了第 3 個 node 會自動長一份上去；其餘元件（Loki/Prometheus/Grafana/kube-state-metrics）維持單副本，加 node 純粹是騰出排程空間。具體 limits 值（Prometheus/Loki 256–512Mi、Alloy/kube-state-metrics 128–256Mi、Grafana 256Mi）留給 `tasks.md` 實作時依 chart 預設值微調，這裡只定調「必須明確設定，不用 chart 預設的無限制」。

### 8. Grafana 對外走 Ingress path，密碼比照 `secret.yml` 模式
沿用現有 `ingress-admin.yml` 的做法：同一個共用 host，用新 path（`/grafana`）分流，加 `nginx.ingress.kubernetes.io/limit-rps` 之類的 annotation。管理員密碼另建一個不進 Git 的 `observability/grafana-admin-secret.yml`，手動 apply 一次，Helm values 用 `admin.existingSecret` 指向它，跟現有機密管理模式完全一致。

兩個容易漏掉的技術細節（已補進 `tasks.md`）：
- **Sub-path 設定**：Grafana 預設假設自己跑在 host 根路徑。跑在 `/grafana` 這種子路徑下，必須額外設定 `server.root_url` 與 `server.serve_from_sub_path: true`，否則登入 redirect、靜態資源、Grafana Live（WebSocket）都會連到錯誤路徑
- **TLS Secret 是 namespace-scoped**：Grafana Ingress 開在 `observability` namespace，不能直接引用 `find-coffee` namespace 底下的 `find-coffee-tls`（K8s Secret 無法跨 namespace 引用）。做法跟現有 `ingress.yml` 一樣：在新 Ingress 上加 `cert-manager.io/cluster-issuer` annotation，讓 cert-manager 在 `observability` namespace 內另外簽發、自動建立一份獨立的 TLS Secret，而不是「共用」既有那份

### 9. 首次上線 5 個 Application 都設 `syncPolicy` 為 manual
這次一口氣新增 5 個 Helm chart、一個新 namespace、一條新 Secret、還有 node_count 變更，變數比平常單一 app 更新多。先手動 `argocd app sync` 逐一驗證（Pod 都 Running、Dashboard 抓得到資料）後，再把每個 Application 的 `syncPolicy` 改回 `automated: {prune: true, selfHeal: true}`，之後跟現有 `argocd/application.yml` 一樣的長期運作方式：`git push` 即自動套用。

## Risks / Trade-offs

- **[風險] 5 個新常駐工作負載可能仍讓 2GB RAM node 吃緊，即使加到 3 個 node** → 緩解：先用短保留期（7 天）與保守 limits 上線，實際觀察資源餘裕後再調整；`node_count`/`node_type`、PVC 大小、保留天數都是可事後調整的參數，不是一次性決定
- **[風險] Push 模式下若 Alloy 或 Prometheus 短暫離線，該段時間的 metrics 直接遺失（無 Operator/緩衝機制補抓）** → 緩解：Alloy 的 `remote_write` 元件本身有內建的 WAL（write-ahead log）暫存機制，短暫斷線可重試補送；長時間離線的資料遺失視為可接受風險（非金融/計費關鍵資料）
- **[風險] `observability/` 目錄會被現有 root Application（`recurse: true`）掃到並自動建立這 5 個 `Application` CRD 本身** → 這是預期行為且無害：`Application` 資源被建立不代表其內容被同步，各自 `syncPolicy: manual` 會擋下實際的 Helm 安裝動作，直到人工執行 `argocd app sync`
- **[風險] `argocd/application.yml` 目前只排除 `terraform/**` 與 `argocd/**`，沒排除 `openspec/**`** → 這個 repo 新增 `openspec/` 之後，root Application 遞迴掃描會碰到 `openspec/config.yaml`（沒有 `apiVersion`/`kind`），導致該資源在 ArgoCD 出現 sync 錯誤，屬於既有缺口、此次一併修正（見 Migration Plan 步驟 0）
- **[取捨] 不裝 Prometheus Operator，換來的是若未來需要更複雜的 scrape 目標動態發現（例如大量微服務各自曝露 `/metrics`），現在的手動 `discovery.kubernetes` 設定會比 ServiceMonitor 麻煩** → 目前元件數量少（僅 Alloy 自身 + kube-state-metrics），可接受；日後元件大量增加時可重新評估
- **[風險] `prometheus-community/prometheus` chart 預設會一併裝出 `kube-state-metrics`/`node-exporter`/`alertmanager`/`pushgateway`，若沒關閉會跟本次架構的獨立 kube-state-metrics Application 重複部署，且裝出 non-goals 明確排除的 Alertmanager** → 緩解：`tasks.md` 5.3 明確要求在 Prometheus 的 `helm.values` 關閉這 4 個子元件，10.4 驗證步驟包含確認沒有多餘 pod
- **[風險] Loki 只設定「保留 7 天」的天數口號，不足以讓資料真的被刪除**（Loki 預設不啟用 retention，filesystem 儲存也不會因為快滿而自動清理）→ 緩解：`tasks.md` 6.4 明確列出 `compactor.retention_enabled`、`limits_config.retention_period`、`compactor.retention_delete_delay` 等必要參數

## Migration Plan

0. 修正 `argocd/application.yml` 的 `exclude`，加入 `openspec/**`（見 Risks；不修這個，push 之後 root Application 會因掃到 `openspec/config.yaml` 而出現 sync 錯誤）
1. `terraform apply` 套用 `node_count: 3`，確認第 3 個 node `Ready`
2. Push 本次變更（`observability/` 目錄下所有 yaml，每個 `Application` 都帶 `resources-finalizer.argocd.argoproj.io` finalizer），root Application 自動同步出 5 個 `Application` CRD（`syncPolicy: manual`，尚未部署實際 workload）
3. 手動 `kubectl apply -f observability/grafana-admin-secret.yml`（不進 Git）
4. 依序手動 `argocd app sync`：先 `kube-state-metrics` → `prometheus` → `loki` → `alloy` → `grafana`（讓資料來源先於消費者就緒）
5. 逐一驗證：Pod 皆 `Running`（且 Prometheus 沒有多裝出 alertmanager/node-exporter/pushgateway）、Prometheus 收到 remote_write 資料、Loki 收到 log 且會依保留政策清除、Grafana 三個 Dashboard 都有資料、`/grafana` sub-path 的登入/靜態資源/WebSocket 都正常
6. 驗證通過後，把 5 個 `Application` 的 `syncPolicy` 改為 `automated: {prune: true, selfHeal: true}`，push 進 repo，之後回歸標準 GitOps 流程

**Rollback**：任一元件驗證失敗，直接刪除對應的 `Application` yaml 檔並 push。這個 cascade delete（連帶移除該 Application 部署出的所有 Helm 資源）**依賴步驟 2 已經加上 `resources-finalizer.argocd.argoproj.io` finalizer**——沒有這個 finalizer，ArgoCD 只會刪除 `Application` CRD 本身，底下的 Deployment/PVC/ConfigMap 等資源會變成孤兒殘留，需要手動 `kubectl delete` 清理；`node_count` 若需回退，`terraform apply` 改回 2 即可（此為 scale-down，不影響現有 app 排程，僅減少可用容量）。
