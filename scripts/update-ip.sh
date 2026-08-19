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

# 直接從 kubectl 讀目前叢集實際的 LoadBalancer IP 當作「舊值」，
# 這樣不用手動猜舊 IP 是多少，也比較不會抓錯字串。
OLD_IP="$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

if [[ -z "$OLD_IP" ]]; then
  echo "抓不到目前叢集的 LoadBalancer IP (kubectl 連不到叢集，或 ingress-nginx 還沒起來)。" >&2
  echo "改用手動指定舊 IP：$0 <新IP> <舊IP>" >&2
  OLD_IP="${2:-}"
  if [[ -z "$OLD_IP" ]]; then
    exit 1
  fi
fi

if [[ "$OLD_IP" == "$NEW_IP" ]]; then
  echo "舊 IP 跟新 IP 一樣 ($OLD_IP)，不用改。"
  exit 0
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
