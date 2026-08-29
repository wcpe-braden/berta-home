# olares

Self-hosted infrastructure for the Olares One — Helm charts and hard-won
operational notes.

_Split out of [wcpe-docs](../../wcpe-docs) so charts live next to the notes
that explain them. Temporary home; expected to move._

## Contents

- `charts/wyoming/` — Whisper (STT) + Piper (TTS) for Home Assistant's voice
  pipeline. See its [README](charts/wyoming/README.md).
- `.claude/skills/olares/` — an `olares` skill: SSH, Helm installs, the
  NetworkPolicy trap, overlay-gateway networking, GPU, on-disk app data.

## The two things that cost the most time

**1. `helm` can't find the cluster, `kubectl` can.** `kubectl` is a symlink to
the k3s binary and self-discovers; helm doesn't. There's no `~/.kube/config`:

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
