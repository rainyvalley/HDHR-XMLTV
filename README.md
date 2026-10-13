# HDHR-XMLTV

Tiny container that pulls the DeviceAuth from an HDHomeRun tuner on your LAN, downloads the
SiliconDust XMLTV guide, and serves it as `guide.xml` so Plex and Jellyfin can both use one URL.

- Reads `DeviceID` / `DeviceAuth` from `http://<tuner>/discover.json` on every fetch (DeviceAuth
  rotates every 16-24 h, so nothing is hard-coded).
- Downloads `https://api.hdhomerun.com/api/xmltv?DeviceAuth=...` (gzip) and only replaces
  `guide.xml` if the response looks like XMLTV.
- Refetches every 20-28 h at a randomized interval, as SiliconDust asks. Skips the fetch on
  container restart if the file is under 20 h old. Retries in 15 min after a failure.
- Serves only `guide.xml` (from `/data/www`) with busybox httpd on port 8088. Download temp files
  live in `/data/.tmp`, which is never served.
- Runs as an unprivileged user (uid/gid 10001). The container starts as root only long enough to
  `chown -R` the data directory (so volumes created by older, root-running versions keep working),
  then drops privileges. Port 8088 is above 1024, so no root is needed to listen.
- The compose file hardens the container: `read_only: true` root filesystem (only the `/data`
  volume is writable), `cap_drop: [ALL]` with just `CHOWN`, `SETUID` and `SETGID` added back (what
  the entrypoint needs to chown the volume and drop privileges), and `no-new-privileges`.
  `init: true` runs a minimal init as PID 1 so `docker stop` is immediate instead of waiting out
  the 10 s kill timeout. Published `guide.xml` is mode 0644.

## Run

    docker compose up -d --build
    docker logs -f hdhr-xmltv
    curl -s http://localhost:8088/guide.xml | head -c 300

One-off test fetch without starting the server:

    docker compose run --rm -e RUN_ONCE=1 hdhr-xmltv

## Use it

- **Plex** (Plex Pass): during DVR setup, click "Have an XMLTV program guide on your server?" and
  enter `http://<docker-host>:8088/guide.xml`. An existing DVR has to be deleted and set up again
  to add XMLTV.
- **Jellyfin**: Live TV -> TV Guide Data Providers -> XMLTV -> `http://<docker-host>:8088/guide.xml`.

## Config (environment variables)

| Variable    | Default                     | Meaning                                  |
|-------------|-----------------------------|------------------------------------------|
| `DEVICE_IP` | `192.168.3.193`             | Tuner address                            |
| `PORT`      | `8088`                      | HTTP port inside the container           |
| `SERVE`     | `1`                         | `0` = don't start the HTTP server        |
| `RUN_ONCE`  | `0`                         | `1` = fetch once and exit                |
| `API_BASE`  | `https://api.hdhomerun.com` | SiliconDust API base URL                 |
| `DATA_DIR`  | `/data`                     | State directory (`www/guide.xml` is the published guide) |
| `MAX_FILESIZE` | `268435456`              | Max XMLTV download in bytes (256 MiB); larger responses are rejected and the old guide kept |

## Upgrading / permissions

- The guide now lives at `./data/www/guide.xml`. A `guide.xml` left in `./data` by an older version
  is moved there on first start, so the freshness check still works.
- On first start the entrypoint changes ownership of `./data` to uid/gid 10001. To skip that, run
  the container as a user that already owns the directory (`user: "1000:1000"` in compose); the
  entrypoint then does no chown and no privilege drop (the capabilities above are then unused).
- `MAX_FILESIZE` is enforced by curl from the response size when the server announces one.

Guide data is 2 days without a DVR guide subscription, 14 days with one. See the
[SiliconDust docs](https://github.com/Silicondust/documentation/wiki/XMLTV-Guide-Data).

---

## A note on AI assistance

Most of this project — code, configuration, and documentation — was written with the help of generative AI. Everything in here was reviewed, tested against real hardware, and corrected by a human before being committed; nothing was accepted on the model's say-so.
