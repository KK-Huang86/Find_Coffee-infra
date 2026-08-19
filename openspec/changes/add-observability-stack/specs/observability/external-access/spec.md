## Purpose

定義 Grafana 如何對外開放存取，包含路由、TLS 與身份驗證，確保 Dashboard 可從公網瀏覽但不會外洩管理員憑證。

## ADDED Requirements

### Requirement: Ingress-routed external access
系統 SHALL 透過現有共用 Ingress host 與獨立 path，將外部流量路由到 Grafana，並套用既有的 TLS 憑證設定。

#### Scenario: 從外部瀏覽器開啟 Grafana
- **WHEN** 使用者透過 HTTPS 造訪現有共用 host 底下的 Grafana 專屬 path
- **THEN** 瀏覽器建立有效 TLS 連線並顯示 Grafana 登入畫面

### Requirement: Credential-protected admin access
系統 SHALL 要求管理員帳號密碼驗證才能存取 Grafana，且該密碼 SHALL NOT 以明文形式提交進版本控制。

#### Scenario: 未驗證的存取請求
- **WHEN** 使用者造訪 Grafana 但尚未輸入有效帳號密碼
- **THEN** 系統拒絕顯示 Dashboard 內容，要求先完成登入

#### Scenario: 密碼來源
- **WHEN** 檢視版本控制中的設定檔案
- **THEN** 找不到明文的 Grafana 管理員密碼，密碼僅存在於叢集內未提交進 Git 的 Secret 中

### Requirement: Request rate limiting
系統 SHALL 對 Grafana 的對外請求套用速率限制，防止濫用。

#### Scenario: 短時間內大量請求
- **WHEN** 同一來源在極短時間內對 Grafana path 發送遠超過正常瀏覽頻率的請求
- **THEN** 超過限制的請求被拒絕
