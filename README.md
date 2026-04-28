# RiseCue

Connect IQ watch app for Garmin watches. The app registers for the watch's configured Sleep Time, asks a small calendar endpoint for tomorrow morning's first event, optionally calculates tomorrow's sunrise on the watch, and schedules a watch notification alert for `target time - lead minutes - buffer minutes`.

Important limitation: this does not create or modify Garmin's built-in alarms. Connect IQ exposes background triggers and notifications, but not native alarm creation.

When calendar and sunrise alerts are both enabled, RiseCue schedules a single alert for whichever target comes first.

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
CALENDAR_TIME_ZONE="America/Indiana/Indianapolis" \
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

## Watch Build

Install the Garmin Connect IQ SDK. The helper scripts default to the SDK under your home directory:

```text
$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin
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

Build for an epix Pro Gen 2 47mm:

```sh
CONNECTIQ_SDK_BIN="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin"
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
PATH="$JAVA_HOME/bin:$PATH" "$CONNECTIQ_SDK_BIN/monkeyc" \
  -f monkey.jungle \
  -d epix2pro47mm \
  -o bin/CalendarWake-epix2pro47mm.prg \
  -y developer_key.der
```

Run in the simulator:

```sh
monkeydo bin/CalendarWake.prg epix2pro47mm
```

Supported manifest targets are `epix2pro42mm`, `epix2pro47mm`, and `epix2pro51mm`.

## App Settings

Configure these in Garmin Connect / Connect IQ:

- Enable wake alerts
- Calendar endpoint URL
- Time zone
- Enable sunrise alerts, default `false`
- Sunrise latitude, as decimal degrees such as `39.7684`
- Sunrise longitude, as decimal degrees such as `-86.1581`
- Lead minutes before event, default `60`
- Extra buffer minutes, default `0`
- Morning window start/end, default `04:00` through `12:00`
- Snooze minutes, default `10`
- Alert mode: vibrate, tone and vibrate, or notification only
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
