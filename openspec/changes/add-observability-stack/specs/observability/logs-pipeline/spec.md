## Purpose

定義應用程式 container logs 如何被收集、傳輸並持久化儲存，讓應用出錯時能被查詢排查，範圍明確排除 node 系統層級日誌。

## ADDED Requirements

### Requirement: Container log collection
系統 SHALL 收集叢集內所有 pod 的 container logs（stdout 與 stderr）。

#### Scenario: 應用程式拋出錯誤訊息
- **WHEN** 一個 pod（如 web 或 celery）在 stdout/stderr 輸出一筆錯誤訊息
- **THEN** 該筆訊息能在數分鐘內被查詢到

### Requirement: Node system log exclusion
系統 SHALL NOT 收集 node 層級系統日誌（如 journald、syslog）。

#### Scenario: 查詢 journald 內容
- **WHEN** 使用者在日誌查詢介面搜尋 kubelet 或 containerd 的系統日誌內容
- **THEN** 查無對應資料，因為系統未收集這類日誌

### Requirement: Log persistence via filesystem storage
系統 SHALL 將收集到的日誌以 filesystem PVC 方式持久化儲存，不依賴外部物件儲存。

#### Scenario: 儲存 pod 重啟
- **WHEN** 負責儲存日誌的 pod 因故重啟
- **THEN** 重啟前已寫入的日誌資料不遺失，重啟後仍可查詢

### Requirement: Log retention window
系統 SHALL 將日誌保留 7 天，超過保留期的資料 SHALL 被自動清除。

#### Scenario: 查詢超過保留期的日誌
- **WHEN** 使用者查詢 8 天前的日誌
- **THEN** 系統不返回該時間點的日誌（已依保留政策清除）
