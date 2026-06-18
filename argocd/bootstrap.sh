#!/usr/bin/env bash
# Bootstrap ArgoCD after terraform apply completes.
# Run this script once — ArgoCD will handle everything after that.
set -euo pipefail

echo "==> Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=120s

echo "==> Registering ArgoCD Application (find-coffee)..."
kubectl apply -f "$(dirname "$0")/application.yml"

echo ""
echo "==> Done. ArgoCD will now sync all manifests from the infra repo."
echo ""
echo "  ArgoCD UI   : kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Admin pass  : kubectl -n argocd get secret argocd-initial-admin-secret \\"
echo "                  -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "  Check sync  : kubectl get application -n argocd"
