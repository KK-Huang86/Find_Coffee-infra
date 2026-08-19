## Purpose

定義 Grafana 如何自動載入資料來源與 Dashboard 內容，讓 metrics 與 logs 兩條資料管線的結果能被視覺化呈現，且新增/修改內容不需重新部署 Grafana。

## ADDED Requirements

### Requirement: Sidecar-based datasource provisioning
系統 SHALL 透過 sidecar 機制，自動偵測帶有指定 datasource label 的 ConfigMap 並載入為 Grafana datasource。系統 SHALL NOT 將 datasource 寫死在 Helm values 中。

#### Scenario: 新增 datasource ConfigMap
- **WHEN** 一個帶有 datasource sidecar label 的 ConfigMap 被套用到 `observability` namespace
- **THEN** 該 datasource 在數分鐘內出現在 Grafana 中，不需要重啟 Grafana

### Requirement: Sidecar-based dashboard provisioning
系統 SHALL 透過 sidecar 機制，自動偵測帶有指定 dashboard label 的 ConfigMap 並載入為 Grafana Dashboard。

#### Scenario: 新增 dashboard ConfigMap
- **WHEN** 一個帶有 dashboard sidecar label 的 ConfigMap 被套用到 `observability` namespace
- **THEN** 該 Dashboard 在數分鐘內出現在 Grafana 中，不需要重啟 Grafana

### Requirement: Node resource dashboard
系統 SHALL 提供一個獨立 Dashboard，呈現各 node 的 CPU、記憶體、磁碟、網路使用狀況。

#### Scenario: 查看 node 資源總覽
- **WHEN** 使用者開啟 Node 資源總覽 Dashboard
- **THEN** 能看到每個 node 目前的 CPU/RAM/disk/network 數值與趨勢

### Requirement: Kubernetes application health dashboard
系統 SHALL 提供一個獨立 Dashboard，呈現 pod 重啟次數與 Deployment/StatefulSet 的 replica 健康狀態。

#### Scenario: 查看應用健康狀態
- **WHEN** 使用者開啟 K8s 應用健康狀態 Dashboard
- **THEN** 能看到 web/celery/postgres/redis 等工作負載的 pod 重啟次數與目前 replica 是否符合預期

### Requirement: Application error log dashboard
系統 SHALL 提供一個獨立 Dashboard，篩選並呈現應用程式 pod 中含有錯誤/例外關鍵字的日誌。

#### Scenario: 查看應用錯誤日誌
- **WHEN** 使用者開啟應用錯誤日誌 Dashboard
- **THEN** 能看到已依 error/exception 相關關鍵字篩選過的最近日誌內容
