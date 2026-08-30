# examples

Point-in-time copies of the Home Assistant config on the Olares One, taken
2026-08-30. **Reference only — nothing here is deployed from this repo.** The
live files are in HA's config directory:

```text
/config/automations.yaml
/config/scripts.yaml
/config/configuration.yaml
/config/.storage/core.network
```

which is a hostPath under
`/olares/rootfs/userspace/pvc-userspace-<user>-<id>/Data/homeassistant`.

They are here because that config existed in exactly one place — the box — with
no history, no diff and no rollback.

## Files

| File | What it is |
| --- | --- |
| `core.network.json` | **The fix that made Sonos discovery work.** Tells HA to listen on `net1`, the overlay-gateway LAN interface, not just the pod overlay. Without it HA has a LAN IP but does all discovery over Kubernetes networking and finds nothing |
| `automations.yaml` | `Play Bass` (conversation trigger), six Sonos grouping automations, and `Office - music follows presence` |
| `scripts.yaml` | `office_speaker_test` (TTS check) and `office_music` |
| `configuration.yaml` | Stock plus Olares-specific `http:` settings — trusted proxies for the in-cluster proxy chain, and IP banning disabled because clients share a proxy IP |

## Caveats

**Entity IDs here are the pre-cleanup ones**, and several are misleading —
`media_player.bedroom_bedroom` is the *Office* Arc, and
`binary_sensor.presence_multi_sensor_fp300_occupancy_2` is the *Office* FP300.
See [HOME_NAMING.md](https://github.com/wcpe-braden/berta-docs) before copying
any of it. Renaming without updating these files silently breaks every
automation.

**`core.network.json` lives in `.storage`**, which Home Assistant owns. Editing
it directly works but needs a full restart, and HA rewrites the file whenever
the setting changes in the UI. Prefer Settings → System → Network → Network
Adapter unless the UI is unavailable.

## Where this should go

Eventually HA's config belongs in git as the *spec*, with the agent reconciling
the box against it — the same spec-versus-observed split planned for the fleet
database. This folder is the first snapshot, not the mechanism.
