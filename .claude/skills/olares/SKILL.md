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

## Giving a workload LAN access (macvlan) - and its two gotchas

Some workloads need real LAN presence: IPv6, multicast, mDNS. The pod overlay
cannot do this (it is IPv4-only, `10.233.64.0/24`). Matter is the clear example.

Reuse the same NetworkAttachmentDefinition Olares uses for its overlay gateway:

```yaml
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: kube-system/underlay-macvlan
```

The pod then gets a `net1` interface with a DHCP IPv4 **and** SLAAC IPv6
(global ULA + link-local) - enough for Matter to commission devices.

**Gotcha 1: attaching macvlan breaks the pod's ClusterIP path.** Verified: with
macvlan attached, other pods get `EHOSTUNREACH` on both the ClusterIP and the
pod IP, while an identical pod without macvlan is reachable normally. Consumers
must use the macvlan **LAN IP** instead. Keep the Service for discovery, but do
not rely on it for traffic.

**Gotcha 2: the MAC is regenerated on every restart**, so the DHCP lease moves
and any URL you configured breaks. A router reservation alone will not help,
because it is keyed on a MAC that keeps changing. Pin the MAC in the annotation,
then reserve *that* at the router:

```yaml
k8s.v1.cni.cncf.io/networks: >-
  [{"name":"underlay-macvlan","namespace":"kube-system","mac":"02:0a:5e:55:80:01"}]
```

Use a locally-administered MAC (second hex digit 2, 6, A or E).

## Matter on Olares

HA Container has no add-on store, so `python-matter-server` runs as its own
workload. It needs the macvlan above; on the overlay alone it cannot see devices.
Persist `/data` (a PVC on the default `local` storage class) - it holds the
fabric credentials, and losing them means re-commissioning every device.

Home Assistant then points at `ws://<macvlan-ip>:5580/ws`, not `localhost:5580`
and not the ClusterIP.

### Matter-over-Thread needs one extra kernel setting

Thread devices (Aqara FP300 and friends) sit on their own IPv6 prefix behind a
Thread Border Router, reachable only via a route the router advertises using
**Route Information Options** in IPv6 RAs. Linux ignores RIOs by default:
`accept_ra_rt_info_max_plen` is `0`, so the route is never installed.

Symptom - commissioning fails while Wi-Fi Matter devices work fine:

```text
SendMessage() to UDP:[fdba:...:5540] failed: OS Error 0x02000065: Network is unreachable
Failed during PASE session pairing request -> Discovery timed out
```

Fix, via a privileged init container (`/proc/sys` is read-only otherwise):

```sh
sysctl -w net.ipv6.conf.net1.accept_ra=2
sysctl -w net.ipv6.conf.net1.accept_ra_rt_info_max_plen=64
```

The routes then appear as `proto ra`, one per border router:

```text
fdba:4741:6204::/64 via fe80::56ef:44ff:fea1:831a dev net1 proto ra
```

Diagnose by comparing prefixes: if the failing address is on a different ULA
prefix than the pod's own `net1` address, it is Thread, not LAN.

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
