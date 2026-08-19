## Purpose

定義叢集 node 與 K8s 物件的 metrics 如何被收集、以 push 模式傳輸、並儲存在 Prometheus 供查詢，不依賴 Prometheus Operator 或 pull-based scrape。

## ADDED Requirements

### Requirement: Node host metrics collection
系統 SHALL 在每個叢集 node 上收集 host-level metrics（CPU、記憶體、磁碟、網路）。

#### Scenario: 新 node 加入叢集
- **WHEN** 一個新的 worker node 加入叢集
- **THEN** 該 node 的 host metrics 開始被收集，不需要額外手動設定

### Requirement: Push-based metrics delivery
系統 SHALL 以 push 模式將收集到的 metrics 主動送往 Prometheus，Prometheus SHALL NOT 依賴 ServiceMonitor、PodMonitor 或其他 Prometheus Operator CRD 來取得 metrics。

#### Scenario: 未部署 Prometheus Operator 仍能取得 metrics
- **WHEN** 叢集內沒有安裝 Prometheus Operator 或任何 ServiceMonitor/PodMonitor 資源
- **THEN** Prometheus 仍然持續收到並儲存最新的 metrics

### Requirement: Kubernetes object state metrics
系統 SHALL 收集 K8s 物件層級狀態（pod 狀態、deployment replica 數、container 重啟次數），並與 node host metrics 一併送往 Prometheus。

#### Scenario: Deployment replica 數變動
- **WHEN** 一個 Deployment 的 replica 數被調整
- **THEN** 新的 replica 數量能在數分鐘內反映在 Prometheus 可查詢到的 metrics 中

### Requirement: Metrics retention window
系統 SHALL 將 metrics 保留 7 天，超過保留期的資料 SHALL 被自動清除。

#### Scenario: 查詢超過保留期的資料
- **WHEN** 使用者查詢 8 天前的 metrics
- **THEN** 系統不返回該時間點的資料（已依保留政策清除）
