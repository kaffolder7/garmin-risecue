# RiseCue

Connect IQ watch app for Garmin watches. The app registers for the watch's configured Sleep Time, or an optional manual workflow time, asks a small calendar endpoint for tomorrow morning's first event, optionally calculates tomorrow's sunrise on the watch, and schedules a watch notification alert for `target time - lead minutes - buffer minutes`.

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

Run locally:

```sh
CALENDAR_ICS_URL="https://calendar.google.com/calendar/ical/..." \
CALENDAR_TIME_ZONE="America/New_York" \
npm start
```

The endpoint will listen on `http://localhost:8787` by default.

Watch setting value example:

```text
https://your-public-host.example.com/next-morning-event
```

Endpoint response with an event:

```json
{
  "hasEvent": true,
  "eventTitle": "Work meeting",
  "eventStartEpochSec": 1777387200,
  "eventStartLocal": "2026-04-28T08:00:00",
  "eventStartDisplay": "Tue, Apr 28 at 8:00 AM EDT",
  "source": "google-private-ics"
}
```

Endpoint response without an event:

```json
{ "hasEvent": false }
```

### Endpoint Deployment

The watch app needs a hosted calendar endpoint that it can reach over HTTPS. Any Node/Docker-capable host should work; Coolify is one possible option.

Coolify example:

Push this repo to GitHub, Gitea, or another Git host Coolify can read, then in Coolify:

1. Create a new Application resource.
2. Select the repo.
3. Choose the Dockerfile build pack.
4. Set the base directory to `/`.
5. Expose port `8787`.
6. Add runtime environment variables:

```env
CALENDAR_ICS_URL=https://calendar.google.com/calendar/ical/your-private-calendar/basic.ics
CALENDAR_TIME_ZONE=America/New_York
ENDPOINT_TOKEN=use-a-long-random-secret
PORT=8787
HOST=0.0.0.0
```

After deployment, test the endpoint:

```sh
curl https://garmin-risecue.yourdomain.com/health
curl -H "X-RiseCue-Token: use-a-long-random-secret" \
  "https://garmin-risecue.yourdomain.com/next-morning-event?windowStart=04:00&windowEnd=12:00"
```

Use these Garmin app setting values:

```text
Calendar endpoint URL: https://garmin-risecue.yourdomain.com/next-morning-event
Calendar endpoint token: use-a-long-random-secret
Calendar time zone: leave blank to use the endpoint default, or set an IANA zone such as America/New_York
```

## Watch Build

Install the Garmin Connect IQ SDK. The helper scripts default to the SDK under your home directory:

```text
"$(find "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" \
  -maxdepth 1 -type d -name 'connectiq-sdk-*' \
  | sort -V \
  | tail -n 1)/bin"
```

Build all supported watch sizes:

```sh
npm run build:watch
```

Build a single target:

```sh
npm run build:watch -- epix2pro47mm
```

The script uses Homebrew OpenJDK 21 at `/opt/homebrew/opt/openjdk@21` and creates an ignored local `developer_key.der` if one is not already present. Override with `CONNECTIQ_SDK_BIN`, `JAVA_HOME`, or `CONNECTIQ_DEVELOPER_KEY` as needed.

The developer key is not requested from Garmin. It is a local signing key used by `monkeyc -y`. For long-term use, keep it somewhere backed up and private, then point builds at it:

```sh
CONNECTIQ_DEVELOPER_KEY=/secure/path/developer_key.der npm run build:watch
CONNECTIQ_DEVELOPER_KEY=/secure/path/developer_key.der npm run package:watch
```

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

For simulator testing, start Garmin's simulator, then run the matching `.prg` for the device:

```sh
monkeydo \
  bin/RiseCue-epix2pro47mm.prg \
  epix2pro47mm
```

> [!NOTE]
> Ensure that `monkeydo` is on your `PATH`. You can check this by running: `which monkeydo`.

For physical sideload testing, connect the watch over USB and copy the matching `.prg` into:

```text
/GARMIN/APPS/
```

For an epix Pro Gen 2 47mm, use:

```text
bin/RiseCue-epix2pro47mm.prg
```

Garmin's own guide describes real-device sideloading by placing the compiled program in `GARMIN/APPS`. App settings are often easier to test through the Connect IQ Store preview flow than raw sideloading.

Supported manifest targets are `epix2pro42mm`, `epix2pro47mm`, and `epix2pro51mm`.

## Connect IQ Store

Package the app:

```sh
npm run package:watch
```

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
- Include the privacy policy URL (e.g. `https://garmin-risecue.yourdomain.com/privacy`, since event titles and times will pass through a public server endpoint.

## App Settings

Configure these in Garmin Connect / Connect IQ:

- Enable wake alerts
- Calendar endpoint URL
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
- `{eventStartLocal}` which renders as a human-readable local time, such as `Tue, Apr 28 at 8:00 AM EDT`

For sunrise alerts, `{eventTitle}` renders as `Sunrise` and `{eventStartLocal}` renders as the calculated sunrise time.

Manual workflow time notes:

- Leave the field blank to keep the default Sleep Time behavior.
- Enter a valid `HH:MM` 24-hour time to run the calendar/sunrise check at that watch-local time every day. When set, RiseCue unregisters the Sleep Time trigger so the workflow does not also run at bedtime.
- Connect IQ supports only one temporal background event at a time. RiseCue uses that slot for the manual workflow trigger until the workflow schedules a wake alert; the alert then owns the slot until it fires, after which RiseCue schedules the next manual workflow trigger.
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

The tests cover tomorrow-window calculation, single events, all-day event ignoring, and weekly recurrence expansion in the endpoint.
