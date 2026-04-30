![RiseCue App Icon](resources/drawables/launcher_icon.png)
# RiseCue

Connect IQ watch app for Garmin watches. The app registers for the watch's configured Sleep Time, or an optional manual workflow time, asks a small calendar endpoint for tomorrow morning's first wake target, optionally calculates tomorrow's sunrise on the watch, and schedules a watch notification alert for `target time - lead minutes - buffer minutes`.

Important limitation: this does not create or modify Garmin's built-in alarms. Connect IQ exposes background triggers and notifications, but not native alarm creation.

When calendar and sunrise alerts are both enabled, RiseCue schedules a single alert for whichever target comes first.

By default, the calendar/sunrise workflow runs when the watch reaches its configured Sleep Time. Setting `Manual workflow time` overrides that Sleep Time trigger and runs the workflow daily at the specified watch-local time instead.

## Project Pieces

- `source/` and `resources/`: Connect IQ watch app.
- `endpoint/server.mjs`: small Node HTTP endpoint that reads a remote ICS calendar and returns the JSON contract the watch app expects.
- `endpoint/*.test.mjs`: endpoint/date filtering tests.

Sunrise support is calculated on the watch with Garmin's Weather sunrise API and manually configured latitude/longitude; it does not require a separate sunrise endpoint.

## Calendar Endpoint

Install dependencies:

```sh
npm install
```

Use Node 20 or newer; the local scripts rely on Node's built-in `.env` support.

Create a local environment file, then edit it for your calendar and token:

```sh
cp .env.example .env
```

Run locally:

```sh
npm start
```

`npm start` loads ignored local values from `.env` and the endpoint will listen
on `http://localhost:8787` by default. If you prefer one-off environment
variables, run `node endpoint/server.mjs` directly instead of `npm start`.
By default, the endpoint reads the calendar configured in `CALENDAR_ICS_URL`.
To let callers provide their own private ICS URL in the `X-RiseCue-Calendar-Url`
HTTP request header, set `ALLOW_REQUEST_CALENDAR_URL=true`. Request-supplied
calendar URLs must be HTTPS URLs with public hostnames, must not include
embedded credentials, and are not accepted through query string parameters.
Local, private, link-local, and reserved hostnames/IP ranges are rejected before
the endpoint fetches the calendar.
Normal morning events use their start time as the wake target. Overnight events
that start before the morning window and end inside it use their end time.

### Environment Variables

There are three related but separate places where configuration can live:

| Setup | Deployed endpoint env | Local watch-build env | Garmin app setting |
| --- | --- | --- | --- |
| Built-in public endpoint, `https://risecue.affolder.dev/next-morning-event` | Managed on the public service: `ENDPOINT_TOKEN`, `ALLOW_REQUEST_CALENDAR_URL=true`, `CALENDAR_TIME_ZONE=America/New_York` or another default zone | `RISECUE_PUBLIC_ENDPOINT_TOKEN` must match the deployed public endpoint's `ENDPOINT_TOKEN` when running `build:watch:public` or `package:watch:public` | Keep default endpoint URL, set `Calendar ICS URL`, leave `Calendar endpoint token` blank |
| Self-hosted shared endpoint, each watch supplies its own calendar | `ENDPOINT_TOKEN=replace-with-a-long-random-token`, `ALLOW_REQUEST_CALENDAR_URL=true`, `CALENDAR_TIME_ZONE=America/New_York`; `CALENDAR_ICS_URL` optional fallback | None required for normal `build:watch`; use `ENDPOINT_TOKEN` only if also running the endpoint locally | Set your endpoint URL, set `Calendar ICS URL`, set `Calendar endpoint token` to `ENDPOINT_TOKEN` |
| Self-hosted single-calendar endpoint | `ENDPOINT_TOKEN=replace-with-a-long-random-token`, `CALENDAR_ICS_URL=https://.../basic.ics`, `ALLOW_REQUEST_CALENDAR_URL=false`, `CALENDAR_TIME_ZONE=America/New_York` | None required for normal `build:watch`; use `ENDPOINT_TOKEN` only if also running the endpoint locally | Set your endpoint URL, leave `Calendar ICS URL` blank, set `Calendar endpoint token` to `ENDPOINT_TOKEN` |

`ENDPOINT_TOKEN` is what an endpoint service accepts. `RISECUE_PUBLIC_ENDPOINT_TOKEN`
is what public watch builds embed for the built-in public endpoint. Those two
values must be identical for a public watch binary to authenticate with the
public endpoint. Custom or self-hosted endpoint URLs do not use the embedded
public token; they use the visible Garmin `Calendar endpoint token` app setting.
Your local `.env` may contain both values when you run the endpoint locally and
also build public watch binaries, but deployed endpoint services only read
`ENDPOINT_TOKEN`.

The same server also exposes a health check, setup guide, and public privacy policy at:

```text
https://public-host.example.com/health
https://public-host.example.com/how-to
https://public-host.example.com/privacy
```

Set `PRIVACY_CONTACT_EMAIL`, `PRIVACY_PUBLIC_ENDPOINT_ORIGIN`, and optionally `PRIVACY_EFFECTIVE_DATE` before publishing so the policy has current contact details and the right public service URL. The setup guide also uses `PRIVACY_PUBLIC_ENDPOINT_ORIGIN` when showing the public calendar endpoint URL. The `/health`, `/how-to`, and `/privacy` pages are intentionally not protected by `ENDPOINT_TOKEN`.

Watch setting value example:

```text
https://public-host.example.com/next-morning-event
```

Endpoint response with an event:

```json
{
  "hasEvent": true,
  "eventTitle": "Work meeting",
  "eventStartEpochSec": 1777387200,
  "eventStartLocal": "2026-04-28T08:00:00",
  "eventStartDisplay": "Tue, Apr 28 at 8:00 AM EDT",
  "eventEndEpochSec": 1777389000,
  "eventEndLocal": "2026-04-28T08:30:00",
  "eventEndDisplay": "Tue, Apr 28 at 8:30 AM EDT",
  "eventTargetEpochSec": 1777387200,
  "eventTargetLocal": "2026-04-28T08:00:00",
  "eventTargetDisplay": "Tue, Apr 28 at 8:00 AM EDT",
  "eventTargetBasis": "start",
  "source": "google-private-ics"
}
```

Endpoint response without an event:

```json
{ "hasEvent": false }
```

### Endpoint Deployment

The watch app needs a hosted calendar endpoint that it can reach over HTTPS. Any Node/Docker-capable host should work; Coolify is one possible option.
The included Docker image has a health check that calls `/health` on the
configured `PORT`.

Coolify example:

Push this repo to GitHub, Gitea, or another Git host Coolify can read, then in Coolify:

1. Create a new Application resource.
2. Select the repo.
3. Choose the Dockerfile build pack.
4. Set the base directory to `/`.
5. Expose port `8787`.
6. Add runtime environment variables.

For a single-calendar self-hosted endpoint:

```env
CALENDAR_ICS_URL=https://calendar.google.com/calendar/ical/private-calendar/basic.ics
CALENDAR_TIME_ZONE=America/New_York
ENDPOINT_TOKEN=use-a-long-random-secret
ALLOW_REQUEST_CALENDAR_URL=false
PRIVACY_CONTACT_EMAIL=privacy@example.com
PRIVACY_EFFECTIVE_DATE="April 28, 2026"
PRIVACY_PUBLIC_ENDPOINT_ORIGIN=https://risecue.example.com
PORT=8787
HOST=0.0.0.0
```

For a shared self-hosted endpoint where each watch supplies its own private
calendar URL:

```env
CALENDAR_TIME_ZONE=America/New_York
ENDPOINT_TOKEN=use-a-long-random-secret
ALLOW_REQUEST_CALENDAR_URL=true
PRIVACY_CONTACT_EMAIL=privacy@example.com
PRIVACY_EFFECTIVE_DATE="April 28, 2026"
PRIVACY_PUBLIC_ENDPOINT_ORIGIN=https://risecue.example.com
PORT=8787
HOST=0.0.0.0
```

You may add `CALENDAR_ICS_URL` to the shared setup as a fallback calendar for
requests that do not include `X-RiseCue-Calendar-Url`.

After deployment, test the endpoint:

```sh
curl https://risecue.example.com/health
curl https://risecue.example.com/privacy
# Single-calendar endpoint, or shared endpoint with CALENDAR_ICS_URL fallback:
curl -H "X-RiseCue-Token: use-a-long-random-secret" \
  "https://risecue.example.com/next-morning-event?windowStart=04:00&windowEnd=12:00"
# Shared endpoint without fallback, or to test a request-supplied calendar:
curl -H "X-RiseCue-Token: use-a-long-random-secret" \
  -H "X-RiseCue-Calendar-Url: https://calendar.google.com/calendar/ical/private-calendar/basic.ics" \
  "https://risecue.example.com/next-morning-event?windowStart=04:00&windowEnd=12:00"
```

Use these Garmin app setting values:

```text
Calendar endpoint URL: https://risecue.example.com/next-morning-event
Calendar ICS URL: leave blank when the endpoint uses CALENDAR_ICS_URL, or set your private HTTPS .ics URL when the endpoint allows request calendar URLs
Calendar endpoint token: use-a-long-random-secret for custom/self-hosted builds; leave blank for public builds that embed the built-in endpoint token
Calendar time zone: choose Endpoint default, UTC, or a common IANA zone such as America/New_York
```

## Watch Build

Install the Garmin Connect IQ SDK. The helper scripts default to the SDK under your home directory:

```text
"$(find "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" \
  -maxdepth 1 -type d -name 'connectiq-sdk-*' \
  | sort -V \
  | tail -n 1)/bin"
```

Build all manifest-supported watches:

```sh
npm run build:watch
```

Build a single target:

```sh
npm run build:watch -- epix2pro47mm
```

Build a simulator/sideload target that embeds the token for the built-in public
RiseCue endpoint:

```sh
npm run build:watch:public -- epix2pro47mm
```

`build:watch:public` loads ignored local `.env` values, reads
`RISECUE_PUBLIC_ENDPOINT_TOKEN` first, and falls back to `ENDPOINT_TOKEN`.
The output path is still `bin/RiseCue-epix2pro47mm.prg`, so the usual
`monkeydo bin/RiseCue-epix2pro47mm.prg epix2pro47mm` flow works.

The script uses Homebrew OpenJDK 21 at `/opt/homebrew/opt/openjdk@21` and creates an ignored local `developer_key.der` if one is not already present. Override with `CONNECTIQ_SDK_BIN`, `JAVA_HOME`, or `CONNECTIQ_DEVELOPER_KEY` as needed.

The developer key is not requested from Garmin. It is a local signing key used by `monkeyc -y`. For long-term use, keep it somewhere backed up and private, then point builds at it:

```sh
CONNECTIQ_DEVELOPER_KEY=/secure/path/developer_key.der npm run build:watch
CONNECTIQ_DEVELOPER_KEY=/secure/path/developer_key.der npm run package:watch
```

### GitHub Package Workflow

The optional `Garmin Package` GitHub Actions workflow can build the `.iq`
package on demand or from `v*` tags. It is intentionally separate from required
PR CI because it needs Garmin's SDK and signing key.

To enable it:

1. Register a repository self-hosted macOS runner with the custom label
   `connectiq`.
2. Install the Garmin Connect IQ SDK and required devices on that runner through
   Garmin SDK Manager.
3. Add a repository variable named `CONNECTIQ_SDK_BIN` that points to the SDK
   `bin` directory, such as:

```text
/Users/runner/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin
```

4. Add a repository secret named `GARMIN_DEVELOPER_KEY_B64`:

```sh
openssl base64 -A -in developer_key.der
```

Manual runs upload `RiseCue-manual-*.iq` and a `.sha256` checksum as workflow
artifacts. Pushing a tag like `v0.1.0` builds `RiseCue-v0.1.0.iq`, creates or
updates the matching GitHub Release, and uploads the `.iq` plus checksum. The
self-hosted runner also needs the GitHub CLI (`gh`) installed for release asset
uploads.

A Garmin developer/store account is only needed when uploading to the Connect IQ Store.

Build for an epix Pro Gen 2 47mm:

```sh
CONNECTIQ_SDK_BIN="$(find "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" \
  -maxdepth 1 -type d -name 'connectiq-sdk-*' \
  | sort -V \
  | tail -n 1)/bin"
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
PATH="$JAVA_HOME/bin:$PATH" "$CONNECTIQ_SDK_BIN/monkeyc" \
  -f monkey.jungle \
  -d epix2pro47mm \
  -o bin/RiseCue-epix2pro47mm.prg \
  -y developer_key.der
```

## Watch Testing

First, build the app:

```sh
npm run build:watch
```

For simulator testing, start Garmin's simulator first:

```sh
connectiq
```

Wait for the Connect IQ Simulator app to open, then run the matching `.prg` for
the device in another terminal. Include the generated settings JSON so the
simulator can open `File > Edit Persistent Storage > Edit Application.Properties
data`:

```sh
monkeydo \
  bin/RiseCue-epix2pro47mm.prg \
  epix2pro47mm \
  -a "bin/RiseCue-epix2pro47mm-settings.json:GARMIN/Settings/RISECUE-EPIX2PRO47MM-settings.json"
```

> [!NOTE]
> Ensure that `monkeydo` is on your `PATH`. You can check this by running: `which monkeydo`.
> If the simulator still says no settings file is available, run
> `File > Reset All App Data`, then run `monkeydo` again with the `-a` flag.

For physical sideload testing, connect the watch over USB and copy the matching `.prg` into:

```text
/GARMIN/APPS/
```

For an epix Pro Gen 2 47mm, use:

```text
bin/RiseCue-epix2pro47mm.prg
```

Garmin's own guide describes real-device sideloading by placing the compiled program in `GARMIN/APPS`. App settings are often easier to test through the Connect IQ Store preview flow than raw sideloading.

Supported manifest targets are focused on Garmin watch-class devices that support this app's Connect IQ `minApiLevel` of `5.1.0` or newer. That currently includes recent Forerunner models (`165`, `255`, `265`, `570`, `955`, `965`, `970`), fenix 7/8/E variants, epix Gen 2/Pro variants, Enduro 3, Instinct 3/E/Crossover AMOLED, Venu 3/4/X1, vivoactive 5/6, MARQ Gen 2, Approach S50/S70, D2 Mach, and Descent G2/Mk3 devices.

## Connect IQ Store

Package the app:

```sh
npm run package:watch
```

Package a Store/public-endpoint build with a token embedded for the built-in
RiseCue endpoint:

```sh
RISECUE_PUBLIC_ENDPOINT_TOKEN=use-a-long-random-secret npm run package:watch:public
```

`package:watch:public` also loads ignored local `.env` values via Node's
`--env-file-if-exists=.env`; it reads `RISECUE_PUBLIC_ENDPOINT_TOKEN` first and
falls back to `ENDPOINT_TOKEN`. The embedded token is only sent when the watch is
using the built-in public endpoint URL,
`https://risecue.affolder.dev/next-morning-event`. Custom endpoint URLs
continue to use the visible `Calendar endpoint token` app setting.

The package is written to:

```text
bin/RiseCue.iq
```

Before upload, make sure `manifest.xml` includes every product you want to support. Garmin's submission flow is to generate an `.iq` package containing all binaries, upload it to the Connect IQ Store, and wait for Garmin validation/review. While approval is pending, Garmin lets you preview and download the app yourself for testing.

For the listing, be explicit:

- RiseCue creates a wake notification/alert, not a native Garmin Alarm.
- It requires the Background, Communications, and Notifications permissions.
- It requires a hosted calendar endpoint.
- Calendar data is processed by either a free, public (and private) endpoint or you may self-host your own calendar event-processing endpoint.
- Include the setup guide URL (e.g. `https://risecue.affolder.dev/how-to` for the built-in endpoint or your own `/how-to` URL when self-hosting) as the recommended support/setup page.
- Include the privacy policy URL (e.g. `https://risecue.affolder.dev/privacy` for the built-in endpoint or your own `/privacy` URL when self-hosting), since private ICS URLs, event titles, and event times may pass through a public server endpoint.

## App Settings

Configure these in Garmin Connect / Connect IQ:

- Enable wake alerts
- Calendar endpoint URL, default `https://risecue.affolder.dev/next-morning-event`; keep this for the built-in public endpoint or replace it with your self-hosted endpoint
- Calendar ICS URL, optional; set this to a private HTTPS `.ics` URL only when the hosted endpoint has `ALLOW_REQUEST_CALENDAR_URL=true`
- Calendar endpoint token, used for custom/self-hosted endpoints; public builds use the embedded token only with the built-in endpoint URL
- Time zone
- Manual workflow time, optional `HH:MM` 24-hour watch-local time such as `21:30`; leave blank to use the watch's Sleep Time trigger
- Enable sunrise alerts, default `false`
- Sunrise latitude, as decimal degrees such as `39.7684`
- Sunrise longitude, as decimal degrees such as `-86.1581`
- Lead minutes before event, default `60`
- Extra buffer minutes, default `0`
- Morning window start/end, default `04:00` through `12:00`
- Snooze minutes, default `10`, configurable from `6` to `60`
- Alert mode: vibrate, tone and vibrate, tone only, or notification only
- Tone style: alarm, loud beep, alert high, alert low, time alert, canary, or custom pattern
- Custom tone pattern, using `frequency:duration,frequency:duration`
- Tone repeat count, default `1`, used for custom tone patterns
- Vibration style: double pulse, long buzz, progressive ramp, urgent pulse, or custom pattern
- Custom vibration pattern, using `strength:duration,strength:duration`
- Notification body template, default `Upcoming: {eventTitle} at {eventStartLocal}`

Notification body templates support:

- `{eventTitle}`
- `{eventStartLocal}` which renders as a human-readable wake target time, such as `Tue, Apr 28 at 8:00 AM EDT`

For sunrise alerts, `{eventTitle}` renders as `Sunrise` and `{eventStartLocal}` renders as the calculated sunrise time.

Manual workflow time notes:

- Leave the field blank to keep the default Sleep Time behavior.
- Enter a valid `HH:MM` 24-hour time to run the calendar/sunrise check at that watch-local time every day. When set, RiseCue unregisters the Sleep Time trigger so the workflow does not also run at bedtime.
- Connect IQ supports only one temporal background event at a time. RiseCue uses that slot for the manual workflow trigger until the workflow schedules a wake alert; the alert then owns the slot until it fires, after which RiseCue schedules the next manual workflow trigger.
- Press START on the watch face to open the action menu. Choose `Check` to re-check the calendar/sunrise target. When an alert is queued, the menu also shows `Clear`; choosing it clears the queued alert and resumes the Sleep Time or manual workflow trigger without contacting the endpoint. During `Check`, a new valid target replaces the queued alert, a successful no-target check clears it, and request or replacement-scheduling failures keep the existing queued alert.
- Invalid values, such as `25:00` or `9pm`, are ignored and RiseCue falls back to the Sleep Time trigger.

Tone and vibration notes:

- Connect IQ does not support embedded `.wav` or `.mp3` notification samples for this watch app. Tone styles use Garmin's built-in tone constants or generated beep sequences.
- Custom tone values are clamped to `100-10000` Hz and `50-2000` ms, with at most 8 steps.
- Custom vibration values are clamped to strength `0-100` and `50-3000` ms, with at most 8 steps.
- A vibration strength of `0` creates a pause between pulses.
- Invalid custom patterns fall back to the default alarm tone or double-pulse vibration.

## Tests

```sh
npm test
```

The tests cover tomorrow-window calculation, single events, overnight event
targets, all-day event ignoring, weekly recurrence expansion, request calendar
URL validation, endpoint privacy/token behavior, and watch request configuration.
