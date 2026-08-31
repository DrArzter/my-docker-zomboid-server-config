# Project Zomboid server profiles

Authoring source for Project Zomboid server configurations, built on the
[`Terule/pz-dedicated-server`](https://github.com/Terule/pz-dedicated-server) image. A profile describes one playable
server runtime: the game build it targets, the Compose configuration, and the Workshop items it runs. Saves, the
player database and secrets are deliberately not stored in Git.

The sibling repositories are
[`my-docker-minecraft-server-config`](https://github.com/DrArzter/my-docker-minecraft-server-config) and
[`my-docker-factorio-server-config`](https://github.com/DrArzter/my-docker-factorio-server-config). One repository per
game keeps each game's authoring contract honest, and every profile declares `"game"` so Spawnpoint knows which
contract it is reading — absence would mean Minecraft.

## Profiles

| ID | Gameplay | Runtime |
| --- | --- | --- |
| `zomboid-vanilla` | Vanilla | Build 42, no Workshop items |

Each profile is self-contained below `profiles/<id>/`:

```text
profile.json    machine-readable identity and mod contract
compose.yaml    standalone local runtime
.env.example    the server's own operator secrets; no Steam account is needed
extras/         authoring inputs such as the Workshop id list, when applicable
data/           the game's Zomboid folder — saves, databases, server config; ignored by Git
```

**No Steam account is required.** The dedicated server is a separate Steam app that installs with an anonymous login,
and it downloads its own Workshop items. Only the people joining need to own the game.

## Run locally

```bash
cd profiles/zomboid-vanilla
cp .env.example .env
# Fill ZOMBOID_RCON_PASSWORD and ZOMBOID_ADMIN_PASSWORD.
docker compose up -d
```

The first boot creates the server's configuration and its world. **The server names its own save directory** — this
image documents no variable for the server name — so nothing here assumes what that name will be, and neither does
Spawnpoint's backup contract.

Validate every profile without starting containers:

```bash
scripts/validate-profiles.sh
```

## Workshop items, and why this file is not the pin

A modded profile lists Workshop ids in `extras/workshop-items.txt`, one numeric id per line. That list is an
authoring input and **not** a reproducible pin: the Steam Workshop has no versions, so an id means "whatever that item
is today".

Reproducibility comes from a release instead. Spawnpoint cuts one by booting the server once, letting it download the
items itself, and keeping the resulting files as an immutable payload with hashes — so a promotion or a rollback
returns the files that were actually played on. That capture step is not built yet; a vanilla profile needs no
payload at all.

One consequence worth knowing before pinning: players' clients update their own Workshop mods, so a pinned server can
fall behind them. The remedy is cutting a new release, which is the recorded and revertible version of the usual
"restart the server so it re-pulls".
