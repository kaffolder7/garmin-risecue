import http from 'node:http';
import net from 'node:net';
import { URL } from 'node:url';
import icalImport from 'node-ical';

const ical = icalImport.default ?? icalImport;

const DEFAULT_PORT = 8787;
const DEFAULT_WINDOW_START = '04:00';
const DEFAULT_WINDOW_END = '12:00';
const DEFAULT_TIME_ZONE = 'America/New_York';
export const REQUEST_CALENDAR_URL_HEADER = 'x-risecue-calendar-url';

class CalendarUrlError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'CalendarUrlError';
    this.code = code;
    this.statusCode = 400;
  }
}

export function parseBooleanFlag(value) {
  if (value === true) return true;
  if (typeof value !== 'string') return false;
  return value.trim().toLowerCase() === 'true';
}

function stripIpv6Brackets(hostname) {
  if (hostname.startsWith('[') && hostname.endsWith(']')) {
    return hostname.slice(1, -1);
  }

  return hostname;
}

function isBlockedIpv4(hostname) {
  const parts = hostname.split('.').map((part) => Number(part));
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) {
    return false;
  }

  const [first, second] = parts;
  return first === 0 ||
    first === 10 ||
    first === 127 ||
    first >= 224 ||
    (first === 100 && second >= 64 && second <= 127) ||
    (first === 169 && second === 254) ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && (second === 0 || second === 168)) ||
    (first === 198 && (second === 18 || second === 19));
}

function mappedIpv4FromIpv6(hostname) {
  const match = hostname.match(/^::ffff:(?:0:)?([0-9a-f]{1,4}):([0-9a-f]{1,4})$/i);
  if (!match) return null;

  const high = Number.parseInt(match[1], 16);
  const low = Number.parseInt(match[2], 16);
  return [
    (high >> 8) & 255,
    high & 255,
    (low >> 8) & 255,
    low & 255
  ].join('.');
}

function isBlockedIpv6(hostname) {
  const normalized = hostname.toLowerCase();
  const mappedIpv4 = mappedIpv4FromIpv6(normalized);
  if (mappedIpv4) {
    return isBlockedIpv4(mappedIpv4);
  }

  return normalized === '::' ||
    normalized === '::1' ||
    normalized.startsWith('fc') ||
    normalized.startsWith('fd') ||
    normalized.startsWith('fe8') ||
    normalized.startsWith('fe9') ||
    normalized.startsWith('fea') ||
    normalized.startsWith('feb');
}

export function isBlockedCalendarHostname(hostname) {
  const normalized = stripIpv6Brackets(hostname).toLowerCase();
  if (!normalized) return true;
  if (normalized === 'localhost' ||
    normalized === 'localhost.localdomain' ||
    normalized.endsWith('.localhost') ||
    normalized.endsWith('.localhost.localdomain') ||
    normalized.endsWith('.local')) {
    return true;
  }

  const ipType = net.isIP(normalized);
  if (ipType === 4) return isBlockedIpv4(normalized);
  if (ipType === 6) return isBlockedIpv6(normalized);

  return false;
}

export function validateRequestCalendarUrl(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new CalendarUrlError('invalid_calendar_url', 'Calendar URL must be a non-empty HTTPS URL');
  }

  let parsed;
  try {
    parsed = new URL(value.trim());
  } catch {
    throw new CalendarUrlError('invalid_calendar_url', 'Calendar URL must be a valid HTTPS URL');
  }

  if (parsed.protocol !== 'https:') {
    throw new CalendarUrlError('invalid_calendar_url', 'Calendar URL must use HTTPS');
  }

  if (!parsed.hostname) {
    throw new CalendarUrlError('invalid_calendar_url', 'Calendar URL must include a hostname');
  }

  if (parsed.username || parsed.password) {
    throw new CalendarUrlError('invalid_calendar_url', 'Calendar URL must not include embedded credentials');
  }

  if (isBlockedCalendarHostname(parsed.hostname)) {
    throw new CalendarUrlError('invalid_calendar_url', 'Calendar URL hostname is not allowed');
  }

  return parsed.toString();
}

function headerValue(headers, name) {
  const value = headers[name];
  if (Array.isArray(value)) return value[0] || '';
  return value || '';
}

export function resolveCalendarIcsUrl({ defaultIcsUrl, requestIcsUrl, allowRequestCalendarUrl }) {
  if (typeof requestIcsUrl !== 'string' || requestIcsUrl.trim() === '') {
    return defaultIcsUrl;
  }

  if (!parseBooleanFlag(allowRequestCalendarUrl)) {
    return defaultIcsUrl;
  }

  return validateRequestCalendarUrl(requestIcsUrl);
}

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

function jsonResponse(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store'
  });
  res.end(body);
}

export function createServer({
  icsUrl = process.env.CALENDAR_ICS_URL,
  defaultTimeZone = process.env.CALENDAR_TIME_ZONE || DEFAULT_TIME_ZONE,
  endpointToken = process.env.ENDPOINT_TOKEN || '',
  allowRequestCalendarUrl = process.env.ALLOW_REQUEST_CALENDAR_URL,
  nextMorningEventHandler = nextMorningEvent
} = {}) {
  const requestCalendarUrlsAllowed = parseBooleanFlag(allowRequestCalendarUrl);

  return http.createServer(async (req, res) => {
    const requestUrl = new URL(req.url, 'http://localhost');

    if (requestUrl.pathname === '/health') {
      jsonResponse(res, 200, { ok: true });
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
      const resolvedIcsUrl = resolveCalendarIcsUrl({
        defaultIcsUrl: icsUrl,
        requestIcsUrl: headerValue(req.headers, REQUEST_CALENDAR_URL_HEADER),
        allowRequestCalendarUrl: requestCalendarUrlsAllowed
      });

      const payload = await nextMorningEventHandler({
        icsUrl: resolvedIcsUrl,
        now: requestUrl.searchParams.has('now') ? new Date(requestUrl.searchParams.get('now')) : new Date(),
        timeZone: requestUrl.searchParams.get('timeZone') || defaultTimeZone,
        windowStart: requestUrl.searchParams.get('windowStart') || DEFAULT_WINDOW_START,
        windowEnd: requestUrl.searchParams.get('windowEnd') || DEFAULT_WINDOW_END
      });

      jsonResponse(res, 200, payload);
    } catch (error) {
      if (error instanceof CalendarUrlError) {
        jsonResponse(res, error.statusCode, {
          error: error.code,
          message: error.message
        });
        return;
      }

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
