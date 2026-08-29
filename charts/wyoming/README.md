# wyoming

Wyoming-protocol voice services for Home Assistant — Whisper (STT) and
optionally Piper (TTS).

## Install

**Olares (k3s)** — must go in Home Assistant's namespace, see below:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml     # helm needs this; k3s kubectl doesn't
helm upgrade --install voice charts/wyoming \
  -f charts/wyoming/values-olares.yaml \
  --namespace homeassistant-bradenwright
```

**kind (local laptop)** — needs matching `extraPortMappings` in the cluster config:

```bash
helm upgrade --install voice charts/wyoming \
  -f charts/wyoming/values-kind.yaml \
  --namespace voice --create-namespace
```

## Wiring into Home Assistant

Settings → Devices & Services → Add Integration → **Wyoming Protocol**

| Target | Host | Port |
| --- | --- | --- |
| Olares | `voice-wyoming-whisper` | 10300 |
| kind on laptop | the Mac's LAN IP | 10300 |

## The namespace constraint (Olares)

Olares drops an `others-np` NetworkPolicy into any namespace it doesn't
own, allowing ingress **only from the same namespace**. Adding your own
policy does not work — an Olares controller deletes it within about a
second of creation.

So on Olares, install into `homeassistant-bradenwright`. Same-namespace
traffic is already permitted, and HA reaches the service by short name.

## Values worth knowing

| Key | Default | Notes |
| --- | --- | --- |
| `whisper.model` | `base-int8` | `distil-large-v3` on GPU; `tiny-int8` if CPU-bound |
| `whisper.gpu.enabled` | `false` | Adds `nvidia.com/gpu` + `nvidia.com/gpumem` (HAMI) |
| `whisper.persistence.enabled` | `false` | Off means the model re-downloads on restart |
| `piper.enabled` | `false` | Stage 1 uses HA's existing Google Translate TTS |
| `networkPolicy.enabled` | `true` | Leave **off** on Olares — it gets deleted |
