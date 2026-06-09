# Repo B — manifests + ApplicationSet (Argo deploys from here)

This repo holds the Kubernetes manifests and the Argo CD `ApplicationSet`. Argo CD — running
in your **local kind** cluster — clones this repo, watches **Repo A's** pull requests, and
renders **one namespace per labeled PR**. This is also where you **run and test** the POC.

## Files in this repo

```
.
├── applicationset.yaml            # the PR generator: watches Repo A's PRs, deploys overlays/preview
├── base/
│   ├── kustomization.yaml         # lists base resources + the image to override per-PR
│   ├── namespace.yaml             # name overridden per-PR (so it's tracked & pruned on teardown)
│   ├── app-deployment.yaml        # the app (image name = tess-preview-app)
│   ├── app-service.yaml           # Service named `tess`
│   └── ingress.yaml               # host is a placeholder; replaced per-PR by the ApplicationSet
├── overlays/
│   └── preview/
│       ├── kustomization.yaml     # ../../base + guardrails, replicas=1
│       ├── networkpolicy.yaml     # default-deny ingress (allow only ingress-nginx) + DNS egress
│       └── resourcequota.yaml     # cap CPU/RAM/pods per preview namespace
└── scripts/
    └── kind-up.sh                 # create kind + ingress-nginx + Argo CD + apply the ApplicationSet
```

## Step 1 — fill in the placeholders

Search the repo for `REPLACE-ME` and set:

| Placeholder | In file | Set to |
|---|---|---|
| `REPLACE-ME-OWNER` | `applicationset.yaml` (generator `owner`) | the GitHub owner of **Repo A** |
| `REPLACE-ME-REPO-A` | `applicationset.yaml` (generator `repo`) | the **Repo A** name (e.g. `tess-preview-app`) |
| `REPLACE-ME-OWNER` | `applicationset.yaml` (`repoURL`) | the GitHub owner of **Repo B** (this repo) |
| `REPLACE-ME-REPO-B` | `applicationset.yaml` (`repoURL`) | this repo's name (e.g. `tess-preview-manifests`) |
| `REPLACE-ME-OWNER` | `applicationset.yaml` (`images:`) + `base/kustomization.yaml` | the GHCR owner (= Repo A owner, **lowercase**) |

> The GHCR path in `images:` must match exactly what Repo A's Action pushed:
> `ghcr.io/<repo-a-owner-lowercase>/tess-preview-app`.

## Step 2 — push this repo to GitHub

```bash
cd repo-B-manifests
git init && git add . && git commit -m "POC preview manifests"
git branch -M main
git remote add origin https://github.com/<you>/tess-preview-manifests.git
git push -u origin main
```
Can be **private** (it has no secrets) or public — your choice.

## Step 3 — stand up the local cluster + Argo CD

```bash
# tools needed: docker, kind, kubectl
bash scripts/kind-up.sh
```
This creates the kind cluster, installs ingress-nginx and Argo CD, and applies the
`ApplicationSet`. (For a **public** Repo A no token is needed; the generator may hit GitHub's
anonymous 60 req/hr limit — fine for a demo. To lift it, add a read-only token as a Secret and
uncomment `tokenRef` in `applicationset.yaml`.)

## Step 4 — run the test

```bash
# 1) In Repo A: open a PR to main and add the `preview` label (see Repo A README).

# 2) Within ~60s Argo should generate an Application and a namespace:
kubectl get applicationset -n argocd
kubectl get applications  -n argocd
kubectl get ns | grep tess-pr

# 3) Watch the workload come up:
kubectl -n tess-pr-<N> get pods,svc,ingress

# 4) Reach it (no public DNS needed) — port-forward the Service:
kubectl -n tess-pr-<N> port-forward svc/tess 8080:80
#   open http://localhost:8080  → you should see the page + the PR's build SHA

# 5) Push another commit to the PR → new image → Argo rolls the preview.

# 6) Close/merge the PR → the Application + namespace are pruned:
kubectl get ns | grep tess-pr   # gone
```

Teardown the whole POC when done: `kind delete cluster --name tess-preview`.

## Want to run *real TeSS* instead of the stub?

This overlay deploys a single stub Deployment. To make it production-shaped, add to
`overlays/preview/` the ephemeral data services and an init job, and point the image at TeSS:

- `postgres.yaml`, `solr.yaml`, `redis.yaml` — ephemeral `Deployment`+`Service`+`emptyDir`.
- `init-job.yaml` — `rails db:prepare && rake city:import && rake sunspot:reindex`.
- `sidekiq-deployment.yaml` — the worker.
- wire `DB_*`, `SOLR_URL`, `REDIS_URL`, `SECRET_KEY_BASE` (throwaway) into `app-deployment.yaml`.

The full production layout is documented in `TeSS/docs/argocd-pr-preview-environments.md`
(Appendix B). Get the stub green first, then graduate.
