#!/usr/bin/env bash
# Stand up a local kind cluster with ingress-nginx + Argo CD, then apply the ApplicationSet.
# Re-runnable: skips creation of things that already exist.
set -euo pipefail

CLUSTER="${CLUSTER:-tess-preview}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APPSET="$HERE/../applicationset.yaml"

echo "==> create kind cluster '$CLUSTER' (if missing)"
if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER"
else
  echo "    already exists"
fi

echo "==> install ingress-nginx (kind provider)"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
echo "    waiting for ingress-nginx controller..."
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s || true

echo "==> install Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side avoids the "metadata.annotations: Too long" failure on the large
# ApplicationSet CRD (client-side apply can't store its last-applied annotation).
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo "    waiting for the ApplicationSet controller..."
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s

echo "==> apply the ApplicationSet"
if grep -q "REPLACE-ME" "$APPSET"; then
  echo "!!  $APPSET still contains REPLACE-ME placeholders — fill them in first (see README)." >&2
  exit 1
fi
kubectl apply -n argocd -f "$APPSET"

cat <<'EOF'

Done. Next:
  1) In Repo A, open a PR to main and add the `preview` label.
  2) Watch it appear:
       kubectl get applications -n argocd
       kubectl get ns | grep tess-pr
  3) Reach it:
       kubectl -n tess-pr-<N> port-forward svc/tess 8080:80
       open http://localhost:8080
  4) Close the PR -> namespace is pruned.

Argo CD UI (optional):
  kubectl -n argocd port-forward svc/argocd-server 8081:443
  # admin password:
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo
EOF
