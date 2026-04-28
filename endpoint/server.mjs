import http from 'node:http';
import { URL } from 'node:url';
import icalImport from 'node-ical';

const ical = icalImport.default ?? icalImport;

const DEFAULT_PORT = 8787;
const DEFAULT_WINDOW_START = '04:00';
const DEFAULT_WINDOW_END = '12:00';
const DEFAULT_TIME_ZONE = 'America/New_York';
const DEFAULT_PRIVACY_EFFECTIVE_DATE = 'April 28, 2026';
const DEFAULT_PRIVACY_APP_NAME = 'RiseCue';

export function parseClockMinutes(value, fallback) {
  if (typeof value !== 'string') return fallback;
  const match = value.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return fallback;

  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return fallback;

  return hours * 60 + minutes;
}

export function getZonedParts(date, timeZone) {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  });

  const parts = Object.fromEntries(
    formatter.formatToParts(date)
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, Number(part.value)])
  );

  if (parts.hour === 24) {
    parts.hour = 0;
  }

  return parts;
}

export function addLocalDays(parts, days) {
  const moved = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + days));
  return {
    year: moved.getUTCFullYear(),
    month: moved.getUTCMonth() + 1,
    day: moved.getUTCDate()
  };
}

function offsetMsAt(utcDate, timeZone) {
  const parts = getZonedParts(utcDate, timeZone);
  const asUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return asUtc - utcDate.getTime();
}

export function zonedTimeToUtc({ year, month, day, hour = 0, minute = 0, second = 0 }, timeZone) {
  const guess = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  const firstOffset = offsetMsAt(guess, timeZone);
  const first = new Date(guess.getTime() - firstOffset);
  const secondOffset = offsetMsAt(first, timeZone);

  if (firstOffset !== secondOffset) {
    return new Date(guess.getTime() - secondOffset);
  }

  return first;
}

export function tomorrowWindow(now, { timeZone, windowStart, windowEnd } = {}) {
  const zone = timeZone || DEFAULT_TIME_ZONE;
  const startMinutes = parseClockMinutes(windowStart || DEFAULT_WINDOW_START, 4 * 60);
  const endMinutes = parseClockMinutes(windowEnd || DEFAULT_WINDOW_END, 12 * 60);
  const today = getZonedParts(now, zone);
  const tomorrow = addLocalDays(today, 1);

  const start = zonedTimeToUtc({
    ...tomorrow,
    hour: Math.floor(startMinutes / 60),
    minute: startMinutes % 60
  }, zone);

  const endDayOffset = endMinutes <= startMinutes ? 1 : 0;
  const endDate = addLocalDays(tomorrow, endDayOffset);
  const end = zonedTimeToUtc({
    ...endDate,
    hour: Math.floor(endMinutes / 60),
    minute: endMinutes % 60
  }, zone);

  return { start, end, timeZone: zone };
}

export function formatLocalIso(date, timeZone) {
  const parts = getZonedParts(date, timeZone);
  return [
    String(parts.year).padStart(4, '0'),
    String(parts.month).padStart(2, '0'),
    String(parts.day).padStart(2, '0')
  ].join('-') + 'T' + [
    String(parts.hour).padStart(2, '0'),
    String(parts.minute).padStart(2, '0'),
    String(parts.second).padStart(2, '0')
  ].join(':');
}

export function formatLocalDisplay(date, timeZone) {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZoneName: 'short'
  });

  const parts = Object.fromEntries(
    formatter.formatToParts(date)
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value])
  );

  return `${parts.weekday}, ${parts.month} ${parts.day} at ${parts.hour}:${parts.minute} ${parts.dayPeriod} ${parts.timeZoneName}`;
}

function isAllDayEvent(event) {
  if (event.datetype === 'date') return true;
  if (event.start?.dateOnly || event.start?.isDate) return true;
  return false;
}

function isExcluded(event, occurrenceStart) {
  if (!event.exdate) return false;
  return Boolean(event.exdate[occurrenceStart.toISOString()]);
}

function recurrenceOverride(event, occurrenceStart) {
  if (!event.recurrences) return null;
  return event.recurrences[occurrenceStart.toISOString()] || null;
}

function eventDurationMs(event) {
  if (!event.start || !event.end) return 0;
  return event.end.getTime() - event.start.getTime();
}

function pushOccurrence(occurrences, event, start, end, rangeStart, rangeEnd) {
  if (start >= rangeStart && start < rangeEnd) {
    occurrences.push({
      title: event.summary || 'Calendar event',
      start,
      end,
      uid: event.uid
    });
  }
}

export function collectOccurrences(events, rangeStart, rangeEnd) {
  const occurrences = [];

  for (const event of Object.values(events)) {
    if (!event || event.type !== 'VEVENT' || !event.start || isAllDayEvent(event)) {
      continue;
    }

    const durationMs = eventDurationMs(event);

    if (event.rrule && typeof event.rrule.between === 'function') {
      const expansionStart = new Date(rangeStart.getTime() - Math.max(durationMs, 0));
      const starts = event.rrule.between(expansionStart, rangeEnd, true);

      for (const occurrenceStart of starts) {
        if (isExcluded(event, occurrenceStart)) {
          continue;
        }

        const override = recurrenceOverride(event, occurrenceStart);
        const start = override?.start || occurrenceStart;
        const end = override?.end || new Date(start.getTime() + durationMs);
        pushOccurrence(occurrences, override || event, start, end, rangeStart, rangeEnd);
      }
    } else {
      pushOccurrence(occurrences, event, event.start, event.end, rangeStart, rangeEnd);
    }
  }

  occurrences.sort((a, b) => a.start.getTime() - b.start.getTime());
  return occurrences;
}

export function responseForOccurrences(occurrences, timeZone, source = 'google-private-ics') {
  if (occurrences.length === 0) {
    return { hasEvent: false };
  }

  const event = occurrences[0];
  return {
    hasEvent: true,
    eventTitle: event.title,
    eventStartEpochSec: Math.floor(event.start.getTime() / 1000),
    eventStartLocal: formatLocalIso(event.start, timeZone),
    eventStartDisplay: formatLocalDisplay(event.start, timeZone),
    source
  };
}

export async function nextMorningEvent({ icsUrl, now = new Date(), timeZone, windowStart, windowEnd }) {
  if (!icsUrl) {
    throw new Error('CALENDAR_ICS_URL is required');
  }

  const window = tomorrowWindow(now, { timeZone, windowStart, windowEnd });
  const events = await ical.async.fromURL(icsUrl);
  const occurrences = collectOccurrences(events, window.start, window.end);
  return responseForOccurrences(occurrences, window.timeZone);
}

export function nextMorningEventFromIcsText({ icsText, now = new Date(), timeZone, windowStart, windowEnd }) {
  const window = tomorrowWindow(now, { timeZone, windowStart, windowEnd });
  const events = ical.sync.parseICS(icsText);
  const occurrences = collectOccurrences(events, window.start, window.end);
  return responseForOccurrences(occurrences, window.timeZone, 'test-ics');
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[character]));
}

function renderContactHtml(appName, contactEmail) {
  if (!contactEmail) {
    return `Use the contact method listed on the ${appName} Garmin Connect IQ Store listing.`;
  }

  const safeEmail = escapeHtml(contactEmail);
  return `Email: <a href="mailto:${encodeURIComponent(contactEmail)}">${safeEmail}</a>`;
}

export function renderPrivacyPolicyHtml({
  appName = process.env.PRIVACY_APP_NAME || DEFAULT_PRIVACY_APP_NAME,
  contactEmail = process.env.PRIVACY_CONTACT_EMAIL || '',
  effectiveDate = process.env.PRIVACY_EFFECTIVE_DATE || DEFAULT_PRIVACY_EFFECTIVE_DATE
} = {}) {
  const safeAppName = escapeHtml(appName);
  const safeEffectiveDate = escapeHtml(effectiveDate);
  const contactHtml = renderContactHtml(safeAppName, contactEmail);

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${safeAppName} Privacy Policy</title>
  <style>
    :root {
      color-scheme: light dark;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.55;
    }

    body {
      margin: 0;
      background: Canvas;
      color: CanvasText;
    }

    main {
      max-width: 820px;
      margin: 0 auto;
      padding: 48px 20px 72px;
    }

    h1 {
      margin: 0 0 8px;
      font-size: clamp(2rem, 4vw, 3rem);
      line-height: 1.1;
    }

    h2 {
      margin: 32px 0 8px;
      font-size: 1.25rem;
    }

    p,
    li {
      font-size: 1rem;
    }

    .muted {
      color: color-mix(in srgb, CanvasText 70%, Canvas);
    }

    a {
      color: LinkText;
    }
  </style>
</head>
<body>
  <main>
    <h1>${safeAppName} Privacy Policy</h1>
    <p class="muted">Effective date: ${safeEffectiveDate}</p>

    <p>${safeAppName} is a Garmin Connect IQ app that helps schedule a wake notification based on your next morning calendar event and, if enabled, sunrise. This policy explains what data is processed by the app and by the calendar endpoint used with it.</p>

    <h2>Data processed by the watch app</h2>
    <p>The app stores the settings you configure on your Garmin device or through Garmin Connect, such as the calendar endpoint URL, optional endpoint token, time zone, morning window, notification text, lead and buffer minutes, snooze length, and alert preferences. If you enable sunrise alerts, the app also stores the latitude and longitude you enter for sunrise calculation.</p>
    <p>When a wake notification is scheduled, the app may temporarily store the selected event title and start time on the watch so it can show the notification later.</p>

    <h2>Data processed by the calendar endpoint</h2>
    <p>The calendar endpoint fetches the configured ICS calendar feed and looks for the first timed event in the configured morning window. Calendar event titles, start times, end times, recurrence details, and the calendar feed response pass through the endpoint while the request is processed. The endpoint returns only the event status, event title, and event start time needed by the watch app.</p>
    <p>Requests to the endpoint may also include technical metadata such as IP address, user agent, request path, query parameters for the morning window or time zone, and an endpoint token if you provide one. The default, public endpoint may keep access logs containing some of that metadata.</p>

    <h2>How data is used</h2>
    <p>Data is used to find the next morning calendar event, schedule or display a wake notification, troubleshoot the service, secure the endpoint, and maintain the app. It is not used for advertising, profiling, or sale to third parties.</p>

    <h2>Retention</h2>
    <p>The included endpoint code processes calendar data in memory and does not intentionally store calendar contents, event titles, or event times after the request completes. Operational logs kept by a hosting provider, reverse proxy, or deployment platform may be retained according to that service's settings. On the watch, the last scheduled event title and time may remain in local app storage until replaced, cleared, or the app is removed.</p>

    <h2>Sharing</h2>
    <p>Calendar data may be processed by the server or hosting provider that runs the endpoint and by your calendar provider when the endpoint fetches the ICS feed. Data may also be disclosed if required by law or to protect the app, server, users, or others.</p>
    <p>Data submitted to ${safeAppName} or its endpoint is submitted to the app developer or endpoint operator, not to Garmin. Garmin is not responsible for that data.</p>

    <h2>Location data</h2>
    <p>${safeAppName} does not collect location data by default. If you enable sunrise alerts, the latitude and longitude you enter are used on the watch for sunrise calculation and are not sent to the included calendar endpoint.</p>

    <h2>Your choices</h2>
    <p>You can stop endpoint processing by disabling calendar wake alerts, removing the calendar endpoint URL or token from app settings, or uninstalling the app. You can disable sunrise alerts or remove sunrise coordinates in app settings. You may use the contact method below to request deletion of user data under the developer's control. If you self-host the endpoint, you control its calendar feed configuration and any server logs created by your hosting setup.</p>

    <h2>Security</h2>
    <p>Use HTTPS for the endpoint, keep the endpoint token private, and protect the private calendar feed URL. No internet-connected service can be guaranteed completely secure.</p>

    <h2>Changes</h2>
    <p>This policy may be updated when the app or endpoint changes how data is collected, used, stored, or disclosed. Keep the same privacy policy URL active, or redirect it to the new location.</p>

    <h2>Contact</h2>
    <p>${contactHtml}</p>
  </main>
</body>
</html>`;
}

function jsonResponse(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store'
  });
  res.end(body);
}

function htmlResponse(res, statusCode, body) {
  res.writeHead(statusCode, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'public, max-age=3600'
  });
  res.end(body);
}

export function createServer({
  icsUrl = process.env.CALENDAR_ICS_URL,
  defaultTimeZone = process.env.CALENDAR_TIME_ZONE || DEFAULT_TIME_ZONE,
  endpointToken = process.env.ENDPOINT_TOKEN || '',
  privacyPolicyOptions
} = {}) {
  return http.createServer(async (req, res) => {
    const requestUrl = new URL(req.url, 'http://localhost');

    if (requestUrl.pathname === '/health') {
      jsonResponse(res, 200, { ok: true });
      return;
    }

    if (requestUrl.pathname === '/privacy' || requestUrl.pathname === '/privacy/') {
      htmlResponse(res, 200, renderPrivacyPolicyHtml(privacyPolicyOptions));
      return;
    }

    if (requestUrl.pathname !== '/next-morning-event') {
      jsonResponse(res, 404, { error: 'not_found' });
      return;
    }

    if (endpointToken && requestUrl.searchParams.get('token') !== endpointToken && req.headers['x-risecue-token'] !== endpointToken) {
      jsonResponse(res, 401, { error: 'unauthorized' });
      return;
    }

    try {
      const payload = await nextMorningEvent({
        icsUrl,
        now: requestUrl.searchParams.has('now') ? new Date(requestUrl.searchParams.get('now')) : new Date(),
        timeZone: requestUrl.searchParams.get('timeZone') || defaultTimeZone,
        windowStart: requestUrl.searchParams.get('windowStart') || DEFAULT_WINDOW_START,
        windowEnd: requestUrl.searchParams.get('windowEnd') || DEFAULT_WINDOW_END
      });

      jsonResponse(res, 200, payload);
    } catch (error) {
      jsonResponse(res, 500, {
        error: 'calendar_endpoint_failed',
        message: error.message
      });
    }
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.PORT || DEFAULT_PORT);
  const host = process.env.HOST || '0.0.0.0';
  createServer().listen(port, host, () => {
    console.log(`Calendar Wake endpoint listening on http://${host}:${port}`);
  });
}
