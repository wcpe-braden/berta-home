# home-assistant

Deployable infrastructure for the Home Assistant layer of
[home](../docs/apps/HOME.md) — Helm charts and operational notes for running
things on the Olares One.

Companion to [berta-docs](../docs); this repo holds what actually deploys.

## Contents

- `charts/wyoming/` — Whisper (STT) and optionally Piper (TTS), the local voice
  pipeline behind HA Assist. See its [README](charts/wyoming/README.md).
- `.claude/skills/olares/` — an `olares` skill: SSH, Helm installs, the
  NetworkPolicy trap, overlay-gateway networking, GPU, on-disk app data.

## Status

Whisper is deployed and reachable from Home Assistant. Voice pipeline wiring
(Wyoming integration → Assist pipeline → Voice PE satellite) is the next step.

## The two things that cost the most time

**1. `helm` can't find the cluster, `kubectl` can.** `kubectl` is a symlink to
the k3s binary and self-discovers; helm doesn't, and there's no `~/.kube/config`:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

**2. Your service must live in the consuming app's namespace.** Olares puts an
`others-np` NetworkPolicy in namespaces it doesn't own that allows ingress only
from the same namespace — and a controller **deletes any policy you add**
(within ~1s, silently, while Helm reports success). Co-locate instead:

```bash
helm upgrade --install voice charts/wyoming \
  -f charts/wyoming/values-olares.yaml \
  --namespace homeassistant-bradenwright
```

Full detail in the skill.

## Fit with the approved tech list

Helm, kind, and Docker are all on [TECH_OVERVIEW](../docs/tech/TECH_OVERVIEW.md),
and this chart is built to run unchanged on either target (`values-kind.yaml`
for the laptop, `values-olares.yaml` for the Olares One).

Two deliberate gaps against that list, both fine for now but worth naming:

- **Delivery is `helm install` over SSH, not Argo CD.** That's bootstrapping.
  Argo CD is the approved GitOps path and this chart is structured to move to it
  — nothing here depends on being installed by hand.
- **Helmfile** would be the orchestrator once there's more than one release.
