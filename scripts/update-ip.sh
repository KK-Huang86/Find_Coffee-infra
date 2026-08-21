#!/usr/bin/env bash
# 叢集重建後 ingress-nginx LoadBalancer IP 會變，這個 script 一次改掉全部寫死該 IP 的地方。
#
# 用法：
#   ./scripts/update-ip.sh <新IP>
#
# 例如：
#   ./scripts/update-ip.sh 194.195.100.1
#
# 跑完後自己看 git diff 確認沒改錯，再 commit + push。

set -euo pipefail

NEW_IP="${1:-}"
if [[ -z "$NEW_IP" ]]; then
  echo "用法: $0 <新IP>" >&2
  echo "例如: $0 194.195.100.1" >&2
  exit 1
fi

if ! [[ "$NEW_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo "看起來不像 IPv4 位址: $NEW_IP" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# 舊值一定要從「檔案裡現在寫的是什麼」讀，不能從 kubectl 讀。
# kubectl 讀到的是叢集當下的真實 IP——如果叢集已經重建過、IP 已經換了，
# 那個值會跟你要設的新 IP 一樣，導致誤判成「不用改」，但檔案其實還是舊的。
OLD_IP="$(grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' ingress.yml 2>/dev/null | head -1 || true)"

if [[ -z "$OLD_IP" ]]; then
  echo "在 ingress.yml 裡找不到現有的 IP。" >&2
  echo "改用手動指定舊 IP：$0 <新IP> <舊IP>" >&2
  OLD_IP="${2:-}"
  if [[ -z "$OLD_IP" ]]; then
    exit 1
  fi
fi

if [[ "$OLD_IP" == "$NEW_IP" ]]; then
  echo "檔案裡的 IP 跟新 IP 一樣 ($OLD_IP)，不用改。"
  exit 0
fi

# 順手提醒一下：新 IP 跟叢集目前實際的 LoadBalancer IP 對不對得起來
LIVE_IP="$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
if [[ -n "$LIVE_IP" && "$LIVE_IP" != "$NEW_IP" ]]; then
  echo "提醒：叢集目前實際的 LoadBalancer IP 是 $LIVE_IP，跟你要設的 $NEW_IP 不一樣，確認一下是不是打錯。" >&2
fi

echo "把 $OLD_IP 換成 $NEW_IP ..."

FILES=(
  ingress.yml
  ingress-admin.yml
  ingress-callback.yml
  configmap.yml
  web/deployment.yml
  observability/grafana-ingress.yml
  observability/grafana-app.yml
)

CHANGED=0
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "跳過 (檔案不存在): $f"
    continue
  fi
  if grep -q "$OLD_IP" "$f"; then
    sed -i '' "s/${OLD_IP//./\\.}/${NEW_IP}/g" "$f"
    echo "已更新: $f"
    CHANGED=$((CHANGED + 1))
  else
    echo "沒找到舊 IP，跳過: $f"
  fi
done

echo ""
echo "共更新 $CHANGED 個檔案。接下來："
echo "  git diff                 # 檢查改動"
echo "  git add -A && git commit -m 'chore: update LoadBalancer IP to $NEW_IP'"
echo "  git push                 # ArgoCD 會自動同步套用"
