---
name: olares
description: Operate and deploy to a self-hosted Olares One (k3s-based personal cloud OS). Covers SSH access, installing custom Helm charts, the NetworkPolicy/namespace constraints that break cross-app traffic, overlay-gateway (macvlan) networking for apps like Home Assistant, GPU scheduling via HAMI, and where app data lives on disk. Use when working with Olares, olares-cli, an Olares Market app, or deploying any workload to the Olares One.
---

# Olares One

Olares is a personal cloud OS built on **k3s**. Apps are Kubernetes workloads
in per-app namespaces, managed through the Olares Market. Everything below was
verified on a real device — the published docs cover almost none of it.

## Access

```bash
ssh olares@<olares-ip>          # default user is `olares`
ssh olares@<name>.olares.local  # mDNS name also resolves
```

The SSH password is generated at activation and lives in the **LarePass Vault**
(the item with a terminal icon). Prefer `ssh-copy-id` and key auth.

`olares-cli` is at `/usr/local/bin/olares-cli`. There is no `olares` binary.

## kubectl works, helm doesn't — set KUBECONFIG

This bites immediately and the error is misleading:

```text
Error: Kubernetes cluster unreachable: Get "http://localhost:8080/version"
```

`kubectl` is a **symlink to the k3s binary**, which auto-discovers the cluster
config. Real binaries like `helm` do not. There is no `~/.kube/config`:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml   # world-readable; helm warns, works fine
```

Helm is preinstalled (`/usr/local/bin/helm`). The k3s `helm-controller` CRDs
(`helmcharts.helm.cattle.io`) are also present if you prefer declarative installs.

## Installing a custom Helm chart

Plain `helm install` over SSH works and is the fastest path. The Olares
Application Chart (OAC) format — a Helm chart plus `OlaresManifest.yaml` — is
only needed to *publish to the Market*; it is overkill for running your own service.

```bash
scp -r ./mychart olares@<ip>:~/charts/
ssh olares@<ip>
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm upgrade --install <release> ~/charts/mychart --namespace <ns> --wait
```

Caveat: charts installed this way are invisible to the Olares dashboard and
unmanaged by Olares. Re-check them after OS upgrades.

## ⚠️ The NetworkPolicy trap — read before choosing a namespace

**Olares auto-creates an `others-np` NetworkPolicy in any namespace it does not
own**, permitting ingress **only from that same namespace**. So a service in
your own namespace is unreachable from any Olares app.

**You cannot fix this by adding your own NetworkPolicy.** A controller deletes
any policy it doesn't own — verified: removed **within ~1 second** of creation,
with no event logged. Helm reports success while the object silently vanishes.

**The workaround: install into the consuming app's namespace.** Same-namespace
traffic is already allowed, so the consumer reaches your service by short name:

```bash
helm upgrade --install voice ~/charts/wyoming \
  --namespace homeassistant-bradenwright     # <- the app that needs it
```

Olares app namespaces are named `<app>-<user>` (e.g. `homeassistant-bradenwright`),
plus `<app>server-shared` for shared backends.

To debug reachability, exec into the *consuming* pod and connect from there —
testing from the host proves nothing, since the host bypasses these policies.

## Overlay gateway (giving an app a LAN IP)

Apps are on the pod overlay by default and cannot do LAN discovery (SSDP/mDNS).
**Settings → Network → Overlay gateway** attaches a **Multus macvlan** interface
(`net1`) alongside `eth0`, giving the app a real LAN address.

Three things that follow, all of which cause confusing bugs:

1. **The app must be told to use `net1`.** Assigning the IP is only half. In Home
   Assistant that is Settings → System → Network → Network Adapter: disable
   auto-config, tick **both `eth0` and `net1`**, restart. Auto-config follows the
   default route (`eth0`, the overlay) and will never pick the LAN interface.
   Symptom: the app has a LAN IP, is pingable, but discovers nothing. Verify the
   real state with multicast group membership, not `ip addr`:

   ```bash
   kubectl -n <ns> exec <pod> -- cat /proc/net/igmp
   # 239.255.255.250 (SSDP) = FAFFFFEF, 224.0.0.251 (mDNS) = FB0000E0, little-endian
   ```
   `ip maddr` is unavailable — the images ship BusyBox `ip`.

2. **The IP is DHCP and changes on every restart.** The macvlan IPAM is
   `{"type": "dhcp"}` and each restart creates a new interface with a **new MAC**,
   hence a new lease. Observed three different addresses in one day. Set a DHCP
   reservation at the router, or expect the app's address to move under you.

3. **The app cannot reach the Olares host itself.** macvlan children cannot talk
   to their own parent interface, so `<app> -> <olares-host-ip>` always fails.
   Other LAN peers (a laptop, a speaker) work fine. This rules out `hostNetwork`,
   NodePort, and "just point it at the host IP" designs — use ClusterIP instead.

## GPU

GPUs are exposed through the **HAMI** device plugin, sliced (e.g. `nvidia.com/gpu=30`),
so several pods can share one card. Request both count and memory:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    nvidia.com/gpumem: 5120   # MiB — HAMI-specific, not standard k8s
```

Check with `kubectl get nodes -o jsonpath='{.items[*].status.capacity}'`.

## App data on disk

`/config`-style mounts are **hostPath**, not PVCs, under the user's data volume:

```text
/olares/rootfs/userspace/pvc-userspace-<user>-<id>/Data/<app>
```

Real disk, so it survives pod restarts, rollouts, and reboots. Useful for editing
an app's config directly when its UI won't cooperate — write the file, then
`kubectl rollout restart deploy/<app>` to pick it up.

## Quick reference

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pods -A -o wide                      # everything
kubectl get ns --show-labels                     # bytetrade.io/* labels
kubectl get networkpolicy -A                     # app-np / others-np / shared-np
kubectl -n <ns> exec <pod> -- <cmd>              # test FROM the consumer
helm -n <ns> list
kubectl -n <ns> rollout restart deploy/<name>
```
