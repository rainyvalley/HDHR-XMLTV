# HDHR-XMLTV

Gets the TV guide for your HDHomeRun tuner and serves it at one URL, so Plex and Jellyfin can both use it.

## Install

1. Put your tuner's address in a file named `.env` next to `docker-compose.yml`:

       DEVICE_IP=192.0.2.50

2. Start it:

       docker compose up -d --build

3. Check it. After a few seconds you should see the guide:

       docker logs -f hdhr-xmltv
       curl -s http://localhost:8088/guide.xml | head -c 300

If `DEVICE_IP` is not set, the container stops with `ERROR: DEVICE_IP is not set - set DEVICE_IP to your HDHomeRun's address`, and `docker compose` refuses to start.

## Use it

- **Plex** (Plex Pass): during DVR setup, click **Have an XMLTV program guide on your server?** and enter `http://<docker-host>:8088/guide.xml`. An existing DVR has to be deleted and set up again to add XMLTV.
- **Jellyfin**: **Live TV** -> **TV Guide Data Providers** -> **XMLTV** -> `http://<docker-host>:8088/guide.xml`.

Guide data is 2 days without a DVR guide subscription, 14 days with one. See the [SiliconDust docs](https://github.com/Silicondust/documentation/wiki/XMLTV-Guide-Data).

## What happens next

| You see in the log | It means | Do this |
|---|---|---|
| `published .../guide.xml` | The guide is ready. | Nothing. |
| `next fetch in N s` | The next download is 20-28 hours away. | Nothing. |
| `can't reach tuner` | The tuner did not answer at `DEVICE_IP`. | Check the address and that the tuner is on. |
| `response doesn't look like complete XMLTV, keeping old guide` | The download was wrong or cut short. The old guide stays. | Wait for the retry. |
| `retrying in N min` | A fetch failed. Retries start at 15 min and double up to 6 h. | Fix the cause above. |
| `HTTP server stopped, restarting` | The web server died and was started again. | Nothing. |

The container also reports **healthy** in `docker ps` once the guide is being served. It shows **starting** or **unhealthy** until the first fetch works.

## How it works

- Every fetch reads `DeviceID` and `DeviceAuth` (the tuner's login token) from `http://<tuner>/discover.json`. The token changes every 16-24 hours, so nothing is stored.
- It downloads `https://api.hdhomerun.com/api/xmltv` (gzip). The new file replaces `guide.xml` only if it is complete XMLTV (it must contain `<tv`, at least one `<programme`, and end with `</tv>`).
- It fetches every 20-28 hours at a random time, as SiliconDust asks. On a restart it skips the fetch if the file is under 20 hours old.
- Only `guide.xml` (from `/data/www`) is served, on port 8088. Download temp files live in `/data/.tmp` and are never served.
- `API_BASE` must start with `https://`, because the token is sent in the URL. (`http://localhost` is allowed for tests.)

## Settings

Set these as environment variables, in `.env` or in `docker-compose.yml`.

| Variable | Default | Meaning |
|---|---|---|
| `DEVICE_IP` | none (**required**) | Tuner address, e.g. `192.0.2.50` |
| `DEVICE_URL` | `http://$DEVICE_IP` | Full tuner URL. If set, `DEVICE_IP` is not needed |
| `PORT` | `8088` | Port inside the container |
| `SERVE` | `1` | `0` = do not start the web server |
| `RUN_ONCE` | `0` | `1` = fetch once and exit |
| `API_BASE` | `https://api.hdhomerun.com` | SiliconDust API address (https only) |
| `DATA_DIR` | `/data` | State directory. The guide is `www/guide.xml` |
| `MAX_FILESIZE` | `268435456` | Largest download in bytes (256 MiB). A bigger one is rejected and the old guide kept |
| `TZ` | `America/Los_Angeles` | Timezone for log lines. Can be set in `.env` |

If you change `PORT`, also change the published port in `docker-compose.yml` (`8088:8088`). An IPv6 `DEVICE_IP` needs brackets in `DEVICE_URL`.

One-off test fetch without starting the server:

    docker compose run --rm -e RUN_ONCE=1 hdhr-xmltv

## Security settings

The compose file runs the container with a read-only root filesystem (only `./data` is writable), all capabilities dropped except `CHOWN`, `SETUID` and `SETGID`, `no-new-privileges`, and a small init process so `docker stop` is immediate. The app runs as uid/gid 10001. The guide is mode 0644. Port 8088 is open on every host interface and has no login. The guide is public TV listings.

## Upgrading / permissions

- The guide now lives at `./data/www/guide.xml`. A `guide.xml` left in `./data` by an older version is moved there on first start.
- On first start the container changes ownership of `./data` to uid/gid 10001. To skip that, run it as a user that already owns the directory (`user: "1000:1000"` in compose). It then does no chown and no privilege drop.

## License

MIT. See [LICENSE](LICENSE).

---

## A note on AI assistance

Most of this project — code, configuration, and documentation — was written with the help of generative AI. Everything in here was reviewed, tested against real hardware, and corrected by a human before being committed; nothing was accepted on the model's say-so.
