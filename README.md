# wowps: your own WoW 3.3.5a server with bots

A personal World of Warcraft: Wrath of the Lich King (3.3.5a) server that runs
in Docker, built from:

- **[AzerothCore, Playerbot branch](https://github.com/mod-playerbots/azerothcore-wotlk/tree/Playerbot)**: the server
- **[mod-playerbots](https://github.com/mod-playerbots/mod-playerbots)**: bots that level, quest, group with you and
  fill the world, so a one-person server doesn't feel empty

You run one script to set it up and one to start it. Then you play with your
normal 3.3.5a game client.

> This repo contains only scripts and settings. It does **not** contain the
> game client or any Blizzard files. You need your own WoW 3.3.5a (build 12340)
> client to play. The server's map data is downloaded automatically during
> setup.

---

## Contents

1. [What you need](#1-what-you-need)
2. [Install](#2-install) (Windows, macOS, Linux)
3. [Create your game account](#3-create-your-game-account)
4. [Connect your game client](#4-connect-your-game-client)
5. [Everyday use](#5-everyday-use)
6. [Settings (.env)](#6-settings-env)
7. [Playing with bots](#7-playing-with-bots)
8. [Backups](#8-backups)
9. [Updating](#9-updating)
10. [Troubleshooting](#10-troubleshooting)
11. [How it works](#11-how-it-works)
12. [Uninstall](#12-uninstall)

---

## 1. What you need

| | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 6+ cores |
| RAM | 8 GB | 16 GB |
| Free disk | 30 GB | 40 GB |
| OS | Windows 10/11 (64-bit), macOS 12+, or 64-bit Linux | |

Most of the disk and time goes to the **first build**, which compiles the
server from source. It takes 30 to 90 minutes depending on your PC. Updates
later are faster.

Software:

- **Docker**
  - Windows / macOS: [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  - Linux: [Docker Engine](https://docs.docker.com/engine/install/) with the Compose plugin
- **Git**
  - Windows: [Git for Windows](https://git-scm.com/download/win) (the default options are fine)
  - macOS: run `git --version` in Terminal and accept the prompt to install it
  - Linux: `sudo apt install git` (or your distro's equivalent)
- **A WoW 3.3.5a client** (version 3.3.5 build 12340), any language.

---

## 2. Install

### Windows

1. Install **Docker Desktop** and **Git** (links above). Start Docker Desktop
   and wait until it says it is running.
2. *(If your PC has 8 GB of RAM)* Docker Desktop on Windows gets half your RAM
   by default, which can be too little for the build. Either close other
   programs during setup, or set `BUILD_JOBS=2` in `.env` after step 5 creates
   it.
3. Open **PowerShell** (Start menu, type `PowerShell`).
4. Download this repo and go into its folder. Pick a folder **without spaces**
   in its path, e.g. `C:\wow`:

   ```powershell
   cd C:\
   git clone https://github.com/RohanToal/wowps.git wow
   cd wow
   ```

5. Allow PowerShell to run the scripts (you only need to do this once per PC),
   then run setup:

   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   .\setup.ps1
   ```

   Setup downloads the source and the map data (~1.2 GB) and builds the
   server. Leave the window open until it says `Setup finished`.

6. Start the server:

   ```powershell
   .\start.ps1
   ```

   The first start creates the databases and the bot characters, so it takes
   a few minutes. Wait until it says `Server is running`.

### macOS and Linux

1. Install Docker and Git (links above) and make sure Docker is running.
   On Linux, also make sure you can run `docker` without `sudo`
   ([how](https://docs.docker.com/engine/install/linux-postinstall/)), or run
   the scripts with `sudo`.
2. Open a terminal and run:

   ```bash
   git clone https://github.com/RohanToal/wowps.git wow
   cd wow
   ./setup.sh
   ```

   Setup downloads the source and the map data (~1.2 GB) and builds the
   server. Wait until it says `Setup finished`.

3. Start the server:

   ```bash
   ./start.sh
   ```

   The first start creates the databases and the bot characters, so it takes
   a few minutes. Wait until it says `Server is running`.

> In the rest of this guide, commands are written as `./script.sh`. On
> Windows, use `.\script.ps1` instead. The scripts behave the same.

---

## 3. Create your game account

The server starts with no player accounts. Open the server console:

```bash
./console.sh          # Windows: .\console.ps1
```

Press **Enter** once and you'll see an `AC>` prompt. Type these two commands,
replacing `myname` and `mypassword` (letters and numbers, max 16 characters):

```text
account create myname mypassword
account set gmlevel myname 3 -1
```

The second line makes you a Game Master (admin) so you can use GM commands
in-game. Skip it for accounts you create for friends.

Press **Ctrl+C** to leave the console. The server keeps running.

---

## 4. Connect your game client

1. Go to your WoW 3.3.5a folder, then into `Data`, then into your language
   folder (`enUS`, `enGB`, `deDE`, ...).
2. Open `realmlist.wtf` with Notepad (or any text editor) and replace
   everything in it with:

   ```text
   set realmlist 127.0.0.1
   ```

   Use the same address you set as `REALM_ADDRESS` in `.env`. The default
   `127.0.0.1` means "this computer".
3. Start `Wow.exe` and log in with the account from step 3.

**Playing from another PC on your network** (or letting a friend on your
Wi-Fi join):

1. Find the server PC's LAN IP. Setup prints it, or run `ipconfig` (Windows)
   or `ip addr` (Linux) and look for something like `192.168.1.50`.
2. In `.env`, set `REALM_ADDRESS=192.168.1.50`, then run `./stop.sh` and
   `./start.sh`.
3. On **every** client (including the server PC) set
   `set realmlist 192.168.1.50`.
4. Windows may ask whether Docker Desktop is allowed through the firewall. Allow
   it on private networks.

**Playing over the internet** works the same way with your public IP, but you
also need to forward ports `3724` and `8085` (TCP) on your router to the server
PC. Only do this if you understand the security implications. Use strong
account passwords.

---

## 5. Everyday use

| What | Linux / macOS | Windows |
|---|---|---|
| Start the server | `./start.sh` | `.\start.ps1` |
| Stop the server (saves everything) | `./stop.sh` | `.\stop.ps1` |
| Open the GM console | `./console.sh` | `.\console.ps1` |
| Make a backup | `./backup.sh` | `.\backup.ps1` |
| Restore a backup | `./restore.sh <name>` | `.\restore.ps1 <name>` |
| Update the server | `./update.sh` | `.\update.ps1` |

Every script has help: `./update.sh --help`, or `Get-Help .\update.ps1` on
Windows.

The server keeps running when you close the terminal. After a reboot it starts
again automatically once Docker is running, unless you stopped it with
`stop`. To see what the server is doing right now:
`docker logs -f ac-worldserver` (Ctrl+C to stop watching).

---

## 6. Settings (.env)

All settings live in the `.env` file in this folder. Setup creates it from
[`.env.example`](.env.example), which explains every option. After changing
`.env`, run `stop` and then `start`.

The ones you're most likely to change:

| Setting | Default | Meaning |
|---|---|---|
| `REALM_NAME` | AzerothCore Playerbots | Name in the realm list |
| `REALM_ADDRESS` | 127.0.0.1 | Address clients connect to (see [section 4](#4-connect-your-game-client)) |
| `BOTS_ENABLED` | 1 | `0` turns random bots off |
| `BOTS_MIN` / `BOTS_MAX` | 100 / 200 | How many random bots are online |
| `BOTS_MIN_LEVEL` / `BOTS_MAX_LEVEL` | 1 / 80 | Level range of random bots |
| `BOTS_PER_PLAYER` | 40 | How many bots you can control at once |
| `BOTS_ONLY_WITH_PLAYERS` | 0 | `1` = bots only log in while a real player is online |
| `TZ` | Etc/UTC | Server time zone (daily resets) |
| `BACKUP_KEEP` | 10 | How many backups to keep |
| `BUILD_JOBS` | auto | Lower this if the build runs out of memory |

**More bots need more power.** 100-200 bots is comfortable on a 4-core PC.
Many people run 500-1000 on a strong machine. If the server lags, lower
`BOTS_MAX`.

### Changing other server settings

Every option in the server config files can also be set in `.env`. Take the
option's name, write it in UPPER_SNAKE_CASE (an `_` between words and in place
of each `.`), and put `AC_` in front:

```ini
# Rate.XP.Kill = 1            in worldserver.conf  becomes:
AC_RATE_XP_KILL=3
# Playerbots.RandomBotJoinBG  in playerbots.conf   becomes:
AC_PLAYERBOTS_RANDOM_BOT_JOIN_BG=0
```

The full lists of options, with explanations, are in
`config/worldserver.conf` and `config/modules/playerbots.conf.dist`. Those files
are created on the first start. You can also edit the config files directly:
`config/worldserver.conf` works as is, and for playerbots copy
`playerbots.conf.dist` to `playerbots.conf` and edit the copy. Values in
`.env` win over values in the files.

### Changing the database password

`DB_ROOT_PASSWORD` is only used when the database is first created. To change
it later, change it inside MySQL first, then in `.env`:

```bash
docker exec -it ac-database mysql -uroot -p     # enter the OLD password
```
```sql
ALTER USER 'root'@'%' IDENTIFIED BY 'NewPassword123';
ALTER USER 'root'@'localhost' IDENTIFIED BY 'NewPassword123';
exit
```

Then put the new password in `.env` and run `stop` and `start`.

---

## 7. Playing with bots

Random bots log in by themselves and live in the world. You can also bring
bots into your group. Type these in the in-game chat:

| Command | What it does |
|---|---|
| `.playerbots bot addclass warrior` | Adds a bot of a class to your group (`dk` for death knight) |
| `.playerbots bot add Charname` | Logs in one of your own other characters as a bot (an "altbot") |
| `.playerbots bot remove Charname` | Logs that bot out |
| `/p follow` / `/p stay` | Party bots follow you / stay where they are |

Bots understand many more commands, and community addons (such as Multibot)
give you buttons for them. See the
[Playerbots wiki: commands](https://github.com/mod-playerbots/mod-playerbots/wiki/Playerbot-Commands)
and the
[addons list](https://github.com/mod-playerbots/mod-playerbots/wiki/Playerbot-Addons-and-Sub%E2%80%90Modules).

---

## 8. Backups

```bash
./backup.sh                 # Windows: .\backup.ps1
./backup.sh before-raid     # optional label in the folder name
```

This saves all databases (accounts, characters, bots, world) plus your
`config/` folder and `.env` into `backups/<date>_<time>[_label]/`. It works
whether the server is running or not. The newest `BACKUP_KEEP` backups are
kept and older ones are deleted. `update` also makes a backup automatically
before changing anything.

> Backups contain your `.env`, which has the database password. Keep the
> `backups` folder private.

**Restore** (this replaces everything since that backup):

```bash
./restore.sh                                     # lists backups
./restore.sh 2026-11-02_20-15-00_before-update   # restores one
```

Copy the `backups` folder somewhere else (cloud drive, USB disk) now and then.
A backup on the same disk won't help if the disk dies.

To back up automatically, schedule `backup.sh` with cron (Linux/macOS) or
`backup.ps1` with Task Scheduler (Windows), e.g. once a day.

---

## 9. Updating

The exact AzerothCore and mod-playerbots versions are **pinned** (fixed) in
[`versions.env`](versions.env). The server only changes when that file
changes, so an upstream change can't break your build overnight.

**Normal update** (get the versions this repo pins):

```bash
git pull           # gets the newest scripts and pins
./update.sh        # Windows: .\update.ps1
```

**Newest upstream code** (not tested by this repo):

```bash
./update.sh --latest       # Windows: .\update.ps1 -Latest
```

What `update` does:

1. Downloads the new source and builds new images. The server **keeps
   running** during the build.
2. If the build fails, it puts the old source and pins back and stops. Your
   server is untouched.
3. Backs up the databases (label `before-update`).
4. Stops the server, downloads new map data if the new version needs it, and
   starts it again. Database updates are applied automatically on start.

**Going back** after an update you don't like:

```bash
git checkout versions.env          # back to this repo's pins (or: git checkout <old commit> -- versions.env)
./update.sh
./restore.sh <the before-update backup>
```

---

## 10. Troubleshooting

**"Docker is installed but not running"**: start Docker Desktop and wait until
it shows "running". On Linux: `sudo systemctl start docker`.

**The build fails with "Killed", "signal 9" or "cannot allocate memory"**:
the compiler ran out of memory. Set `BUILD_JOBS=2` in `.env` (or `1` on 8 GB
machines) and run setup again. It continues where it stopped. On Windows/macOS
you can also give Docker Desktop more memory in *Settings > Resources*.

**"port is already allocated" / "address already in use"**: another program
uses that port. For 3306 (another MySQL on your PC), set `DB_PORT=3307` in
`.env`. For 3724/8085, another WoW server is probably running. Stop it first.

**Can't log in / stuck at "Connecting"**: check that `realmlist.wtf` matches
`REALM_ADDRESS`, and that the server finished starting (`./start.sh` says
`Server is running`).

**Logged in, but the realm list hangs / "disconnected" after choosing the
realm**: `REALM_ADDRESS` is not reachable from that client. With the default
`127.0.0.1`, only the server PC itself can play. See
[section 4](#4-connect-your-game-client).

**Bots don't show up**: they log in gradually over the first minutes. On the
very first start the server creates all bot characters first, which can take a
while with high `BOTS_MAX`. Check `docker logs -f ac-worldserver`.

**The worldserver keeps restarting**: run `docker logs --tail 100
ac-worldserver` and look at the last error. A common cause is a database
problem after an update. Restore the `before-update` backup and go back to the
previous pins ([section 9](#9-updating)).

**`setup` says a database from an earlier install already exists**: you
deleted `.env` but not the database. Put the old password back in `.env`, or
delete the old database (all accounts and characters!) with
`docker volume rm wowps_ac-database`.

**Linux: "permission denied" on `config/` or `logs/`**: run
`sudo chown -R $(id -u):$(id -g) config logs backups` and start again.

**Windows: "running scripts is disabled on this system"**: run
`Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` once
(see install step 5).

Still stuck? `logs/Server.log` and `logs/DBErrors.log` have details. The
[Playerbots troubleshooting page](https://github.com/mod-playerbots/mod-playerbots/wiki/Troubleshooting)
and their Discord are good places to ask.

---

## 11. How it works

```text
.
|-- setup / start / stop / console / backup / restore / update   (.sh and .ps1)
|-- versions.env        pinned AzerothCore + mod-playerbots commits
|-- .env.example        all settings, explained (setup copies it to .env)
|-- docker-compose.yml  the containers
|-- docker/             small helper scripts that run inside containers
|-- scripts/            shared code for the .sh / .ps1 scripts
|
|-- .env                your settings + DB password   (created by setup, not in git)
|-- source/             pinned server source code     (created by setup, not in git)
|-- config/             server .conf files            (created on first start, not in git)
|-- logs/               server log files              (not in git)
`-- backups/            your backups                  (not in git)
```

Containers (`docker compose ps` lists them):

| Container | Job |
|---|---|
| `ac-database` | MySQL 8.4. Data is kept in the Docker volume `wowps_ac-database` |
| `ac-client-data-init` | Downloads the map data into the volume `wowps_ac-client-data`, then exits |
| `ac-db-import` | Creates/updates the databases on every start, then exits |
| `ac-realmlist` | Writes `REALM_NAME`/`REALM_ADDRESS` into the realm list, then exits |
| `ac-authserver` | Login server (port 3724) |
| `ac-worldserver` | The game world and the bots (port 8085) |

Some details:

- **Images are built locally** from the pinned source, using AzerothCore's
  own `apps/docker/Dockerfile`. The only change is the number of parallel
  compile jobs (`BUILD_JOBS`), so the build doesn't run out of memory.
- **Map data** (dbc, maps, vmaps, mmaps) is downloaded from
  [wowgaming/client-data](https://github.com/wowgaming/client-data) at the
  version the pinned AzerothCore expects (currently v20.0). It is never put in
  this repo or extracted from your client.
- **The playerbots database** (`acore_playerbots`) is created and updated by
  the worldserver itself at startup, from the SQL files in the module.
- **The database** port is only open to `127.0.0.1` (this computer). You can
  connect a tool like HeidiSQL or DBeaver to `127.0.0.1:3306` as `root` with
  the password from `.env`.
- To change something in `docker-compose.yml` without editing it, create a
  `docker-compose.override.yml` next to it. Git ignores that file.
- You can still use plain Docker Compose commands from this folder, e.g.
  `docker compose ps` or `docker compose logs ac-authserver`.

---

## 12. Uninstall

```bash
./stop.sh
docker compose --profile tools down --volumes --rmi all   # deletes the database, the map data and the images!
```

Then delete this folder. Back up first if you want to keep your characters.
Docker also keeps a build cache. `docker builder prune` frees that space.
