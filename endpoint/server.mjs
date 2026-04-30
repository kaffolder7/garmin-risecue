import http from 'node:http';
import net from 'node:net';
import { readFile } from 'node:fs/promises';
import { URL } from 'node:url';
import icalImport from 'node-ical';

const ical = icalImport.default ?? icalImport;

const DEFAULT_PORT = 8787;
const DEFAULT_WINDOW_START = '04:00';
const DEFAULT_WINDOW_END = '12:00';
const DEFAULT_TIME_ZONE = 'America/New_York';
const DEFAULT_PRIVACY_EFFECTIVE_DATE = 'April 28, 2026';
const DEFAULT_PRIVACY_APP_NAME = 'RiseCue';
const DEFAULT_PUBLIC_ENDPOINT_ORIGIN = 'https://risecue.affolder.dev';
const PUBLIC_CALENDAR_ENDPOINT_PATH = '/next-morning-event';
const FAVICON_PATH = '/favicon.png';
const APP_ICON_URL = new URL('../resources/drawables/launcher_icon.png', import.meta.url);
export const REQUEST_CALENDAR_URL_HEADER = 'x-risecue-calendar-url';
const REQUEST_CALENDAR_URL_HEADER_DISPLAY = 'X-RiseCue-Calendar-Url';

class CalendarUrlError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'CalendarUrlError';
    this.code = code;
    this.statusCode = 400;
  }
}

class RequestParameterError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'RequestParameterError';
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
  const hasDefaultIcsUrl = typeof defaultIcsUrl === 'string' && defaultIcsUrl.trim() !== '';
  const requestCalendarUrlsAllowed = parseBooleanFlag(allowRequestCalendarUrl);

  if (typeof requestIcsUrl !== 'string' || requestIcsUrl.trim() === '') {
    if (!hasDefaultIcsUrl && requestCalendarUrlsAllowed) {
      throw new CalendarUrlError(
        'missing_calendar_url',
        `${REQUEST_CALENDAR_URL_HEADER_DISPLAY} header is required`
      );
    }

    return defaultIcsUrl;
  }

  if (!requestCalendarUrlsAllowed) {
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

function parseNowQueryParameter(searchParams) {
  if (!searchParams.has('now')) {
    return new Date();
  }

  const now = new Date(searchParams.get('now'));
  if (!Number.isFinite(now.getTime())) {
    throw new RequestParameterError(
      'invalid_now',
      'now query parameter must be a valid date/time'
    );
  }

  return now;
}

function resolveTimeZoneQueryParameter(value, fallback) {
  if (!value) {
    return fallback;
  }

  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value }).format(new Date(0));
  } catch (error) {
    if (error instanceof RangeError) {
      throw new RequestParameterError(
        'invalid_time_zone',
        'timeZone query parameter must be a valid IANA time zone'
      );
    }

    throw error;
  }

  return value;
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

function isValidDate(value) {
  return value && typeof value.getTime === 'function' && Number.isFinite(value.getTime());
}

function dateInWindow(date, rangeStart, rangeEnd) {
  return date >= rangeStart && date < rangeEnd;
}

function occurrenceTarget(start, end, rangeStart, rangeEnd) {
  if (!isValidDate(start)) {
    return null;
  }

  if (dateInWindow(start, rangeStart, rangeEnd)) {
    return { date: start, basis: 'start' };
  }

  if (start < rangeStart &&
    isValidDate(end) &&
    end > start &&
    dateInWindow(end, rangeStart, rangeEnd)) {
    return { date: end, basis: 'end' };
  }

  return null;
}

function pushOccurrence(occurrences, event, start, end, rangeStart, rangeEnd) {
  const target = occurrenceTarget(start, end, rangeStart, rangeEnd);
  if (!target) {
    return;
  }

  occurrences.push({
    title: event.summary || 'Calendar event',
    start,
    end,
    target: target.date,
    targetBasis: target.basis,
    uid: event.uid
  });
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

  occurrences.sort((a, b) =>
    a.target.getTime() - b.target.getTime() ||
    a.start.getTime() - b.start.getTime()
  );
  return occurrences;
}

export function responseForOccurrences(occurrences, timeZone, source = 'google-private-ics') {
  if (occurrences.length === 0) {
    return { hasEvent: false };
  }

  const event = occurrences[0];
  const target = isValidDate(event.target) ? event.target : event.start;
  const response = {
    hasEvent: true,
    eventTitle: event.title,
    eventStartEpochSec: Math.floor(event.start.getTime() / 1000),
    eventStartLocal: formatLocalIso(event.start, timeZone),
    eventStartDisplay: formatLocalDisplay(event.start, timeZone),
    eventTargetEpochSec: Math.floor(target.getTime() / 1000),
    eventTargetLocal: formatLocalIso(target, timeZone),
    eventTargetDisplay: formatLocalDisplay(target, timeZone),
    eventTargetBasis: event.targetBasis || 'start',
    source
  };

  if (isValidDate(event.end)) {
    response.eventEndEpochSec = Math.floor(event.end.getTime() / 1000);
    response.eventEndLocal = formatLocalIso(event.end, timeZone);
    response.eventEndDisplay = formatLocalDisplay(event.end, timeZone);
  }

  return response;
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

function normalizePublicEndpointOrigin(value) {
  const normalized = String(value || DEFAULT_PUBLIC_ENDPOINT_ORIGIN).replace(/\/+$/, '');
  return normalized || DEFAULT_PUBLIC_ENDPOINT_ORIGIN;
}

export function renderHowToHtml({
  appName = process.env.PRIVACY_APP_NAME || DEFAULT_PRIVACY_APP_NAME,
  publicEndpointOrigin = process.env.PRIVACY_PUBLIC_ENDPOINT_ORIGIN || DEFAULT_PUBLIC_ENDPOINT_ORIGIN
} = {}) {
  const safeAppName = escapeHtml(appName);
  const publicOrigin = normalizePublicEndpointOrigin(publicEndpointOrigin);
  const publicEndpointUrl = `${publicOrigin}${PUBLIC_CALENDAR_ENDPOINT_PATH}`;
  const safePublicEndpointUrl = escapeHtml(publicEndpointUrl);

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${safeAppName} Setup Guide</title>
  <link rel="icon" type="image/png" href="${FAVICON_PATH}">
  <style>
    :root {
      color-scheme: light dark;
      --color-bg: #f4f7f6;
      --color-surface: #ffffff;
      --color-panel: #e9eef1;
      --color-text: #1d2521;
      --color-muted: #5f6d68;
      --color-primary: #1f5b49;
      --color-primary-strong: #154537;
      --color-accent: #b85f2f;
      --color-border: #d6dedb;
      --color-code: #edf5f1;
      --shadow-sm: 0 10px 24px rgba(37, 49, 43, 0.08);
      --shadow-md: 0 18px 48px rgba(37, 49, 43, 0.13);
      --space-xs: 6px;
      --space-sm: 10px;
      --space-md: 18px;
      --space-lg: 28px;
      --space-xl: 44px;
      --font-display: Charter, "Iowan Old Style", "Palatino Linotype", Georgia, serif;
      --font-body: "Avenir Next", "Trebuchet MS", Verdana, sans-serif;
      font-family: var(--font-body);
      line-height: 1.55;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --color-bg: #101613;
        --color-surface: #18201c;
        --color-panel: #202a25;
        --color-text: #eef2ec;
        --color-muted: #b5c0b9;
        --color-primary: #a8dcc0;
        --color-primary-strong: #d0f2df;
        --color-accent: #f1a26d;
        --color-border: #34423b;
        --color-code: #243129;
        --shadow-sm: 0 10px 24px rgba(0, 0, 0, 0.24);
        --shadow-md: 0 18px 48px rgba(0, 0, 0, 0.32);
      }
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      background: var(--color-bg);
      color: var(--color-text);
    }

    a {
      color: var(--color-primary-strong);
      font-weight: 700;
      text-decoration-thickness: 1px;
      text-underline-offset: 3px;
    }

    code {
      overflow-wrap: anywhere;
      border-radius: 6px;
      background: var(--color-code);
      padding: 2px 6px;
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
      font-size: 0.92em;
    }

    .page {
      width: min(1120px, calc(100% - 32px));
      margin: 0 auto;
      padding: 40px 0 72px;
    }

    .hero {
      display: grid;
      grid-template-columns: minmax(0, 1.08fr) minmax(280px, 0.92fr);
      gap: var(--space-xl);
      align-items: center;
      padding: 16px 0 38px;
    }

    .eyebrow {
      margin: 0 0 var(--space-sm);
      color: var(--color-accent);
      font-size: 0.78rem;
      font-weight: 800;
      text-transform: uppercase;
    }

    h1,
    h2,
    h3 {
      font-family: var(--font-display);
      line-height: 1.08;
    }

    h1 {
      max-width: 760px;
      margin: 0;
      font-size: 4.5rem;
      font-weight: 700;
    }

    h2 {
      margin: 0 0 var(--space-md);
      font-size: 2.25rem;
    }

    h3 {
      margin: 0 0 var(--space-xs);
      font-size: 1.35rem;
    }

    p {
      margin: 0 0 var(--space-md);
    }

    .lede {
      max-width: 700px;
      margin-top: var(--space-lg);
      color: var(--color-muted);
      font-size: 1.16rem;
    }

    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: var(--space-sm);
      margin-top: var(--space-lg);
    }

    .button {
      display: inline-flex;
      min-height: 44px;
      align-items: center;
      border: 1px solid var(--color-primary);
      border-radius: 8px;
      background: var(--color-primary);
      color: var(--color-surface);
      padding: 10px 16px;
      text-decoration: none;
    }

    .button.secondary {
      background: transparent;
      color: var(--color-primary-strong);
    }

    .quick-panel,
    .callout,
    .advanced,
    .troubleshooting {
      border: 1px solid var(--color-border);
      border-radius: 8px;
      background: var(--color-surface);
      box-shadow: var(--shadow-sm);
    }

    .quick-panel {
      padding: var(--space-lg);
    }

    .quick-panel h2 {
      font-size: 1.55rem;
    }

    .setting-list {
      display: grid;
      gap: 12px;
      margin: 0;
      padding: 0;
      list-style: none;
    }

    .setting-list li {
      display: grid;
      grid-template-columns: minmax(140px, 0.35fr) minmax(0, 0.65fr);
      gap: var(--space-md);
      border-top: 1px solid var(--color-border);
      padding-top: 12px;
    }

    .setting-list li:first-child {
      border-top: 0;
      padding-top: 0;
    }

    .label {
      color: var(--color-muted);
      font-size: 0.9rem;
      font-weight: 800;
      text-transform: uppercase;
    }

    .steps {
      display: grid;
      gap: var(--space-lg);
      margin-top: var(--space-xl);
    }

    .step {
      display: grid;
      grid-template-columns: minmax(0, 0.62fr) minmax(260px, 0.38fr);
      gap: var(--space-lg);
      align-items: stretch;
      border-top: 1px solid var(--color-border);
      padding-top: var(--space-lg);
    }

    .step-number {
      display: inline-flex;
      width: 34px;
      height: 34px;
      align-items: center;
      justify-content: center;
      margin-bottom: var(--space-sm);
      border: 1px solid var(--color-primary);
      border-radius: 50%;
      color: var(--color-primary-strong);
      font-weight: 900;
    }

    .checklist {
      display: grid;
      gap: 10px;
      margin: var(--space-md) 0 0;
      padding: 0;
      list-style: none;
    }

    .checklist li {
      position: relative;
      padding-left: 24px;
    }

    .checklist li::before {
      position: absolute;
      left: 0;
      color: var(--color-accent);
      content: "OK";
      font-size: 0.72rem;
      font-weight: 900;
    }

    .screenshot-frame {
      margin: 0;
      border: 1px solid var(--color-border);
      border-radius: 8px;
      background: var(--color-panel);
      padding: 14px;
      box-shadow: var(--shadow-md);
    }

    .phone-placeholder {
      min-height: 340px;
      border: 1px solid var(--color-border);
      border-radius: 8px;
      background: var(--color-surface);
      padding: 18px;
    }

    .screen-bar,
    .screen-line,
    .screen-field {
      border-radius: 6px;
      background: var(--color-panel);
    }

    .screen-bar {
      width: 42%;
      height: 12px;
      margin: 0 auto 20px;
    }

    .screen-line {
      height: 10px;
      margin-bottom: 12px;
    }

    .screen-line.short {
      width: 62%;
    }

    .screen-field {
      display: flex;
      min-height: 58px;
      align-items: center;
      margin: 18px 0;
      border: 1px dashed var(--color-accent);
      padding: 12px;
      color: var(--color-muted);
      font-size: 0.9rem;
      font-weight: 800;
    }

    figcaption {
      margin-top: 10px;
      color: var(--color-muted);
      font-size: 0.9rem;
    }

    .callout {
      margin: var(--space-xl) 0;
      padding: var(--space-lg);
      border-left: 6px solid var(--color-accent);
    }

    .settings-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--space-md);
    }

    .mini-panel {
      border-top: 1px solid var(--color-border);
      padding-top: var(--space-md);
    }

    .mini-panel p {
      color: var(--color-muted);
    }

    .advanced,
    .troubleshooting {
      margin-top: var(--space-xl);
      padding: var(--space-lg);
    }

    details summary {
      cursor: pointer;
      color: var(--color-primary-strong);
      font-family: var(--font-display);
      font-size: 1.35rem;
      font-weight: 700;
    }

    .trouble-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--space-md);
    }

    .trouble-grid div {
      border-top: 1px solid var(--color-border);
      padding-top: var(--space-md);
    }

    .footer {
      margin-top: var(--space-xl);
      color: var(--color-muted);
      font-size: 0.95rem;
    }

    @media (max-width: 780px) {
      .hero,
      .step,
      .settings-grid,
      .trouble-grid {
        grid-template-columns: 1fr;
      }

      .setting-list li {
        grid-template-columns: 1fr;
        gap: var(--space-xs);
      }

      h1 {
        font-size: 2.75rem;
      }

      h2 {
        font-size: 1.85rem;
      }

      .lede {
        font-size: 1.05rem;
      }
    }
  </style>
</head>
<body>
  <main class="page">
    <section class="hero" aria-labelledby="page-title">
      <div>
        <p class="eyebrow">RiseCue setup</p>
        <h1 id="page-title">Set up ${safeAppName} in Garmin Connect</h1>
        <p class="lede">${safeAppName} checks your calendar and optional sunrise time, then schedules a wake notification on your watch. It does not create or change Garmin native alarms.</p>
        <div class="actions">
          <a class="button" href="#setup-steps">Start setup</a>
          <a class="button secondary" href="/privacy">Read privacy policy</a>
        </div>
      </div>
      <figure class="screenshot-frame screenshot-placeholder">
        <div class="phone-placeholder" role="img" aria-label="Placeholder screenshot: Garmin app settings screen">
          <div class="screen-bar"></div>
          <div class="screen-line"></div>
          <div class="screen-line short"></div>
          <div class="screen-field">Garmin app settings screen</div>
          <div class="screen-line"></div>
          <div class="screen-line short"></div>
        </div>
        <figcaption>Placeholder screenshot: Garmin app settings screen.</figcaption>
      </figure>
    </section>

    <section class="quick-panel" aria-labelledby="quick-values-title">
      <h2 id="quick-values-title">Use these public endpoint settings</h2>
      <ul class="setting-list">
        <li>
          <span class="label">Calendar endpoint URL</span>
          <span>Keep the default value: <code>${safePublicEndpointUrl}</code></span>
        </li>
        <li>
          <span class="label">Calendar ICS URL</span>
          <span>Paste your private HTTPS <code>.ics</code> calendar link.</span>
        </li>
        <li>
          <span class="label">Calendar endpoint token</span>
          <span>Leave blank for public builds. The public app includes the built-in endpoint token automatically.</span>
        </li>
      </ul>
    </section>

    <section id="setup-steps" class="steps" aria-labelledby="steps-title">
      <h2 id="steps-title">Setup steps</h2>

      <article class="step">
        <div>
          <span class="step-number">1</span>
          <h3>Open the app settings</h3>
          <p>In Garmin Connect or Connect IQ, open ${safeAppName}, then open App Settings. Keep <strong>Enable wake alerts</strong> turned on.</p>
          <ul class="checklist">
            <li>The app needs Background, Communications, and Notifications permissions.</li>
            <li>Your watch must be paired and able to sync settings from your phone.</li>
          </ul>
        </div>
        <figure class="screenshot-frame screenshot-placeholder">
          <div class="phone-placeholder" role="img" aria-label="Placeholder screenshot: Garmin Connect app settings screen">
            <div class="screen-bar"></div>
            <div class="screen-field">App Settings</div>
            <div class="screen-line"></div>
            <div class="screen-line short"></div>
          </div>
          <figcaption>Placeholder screenshot: Garmin Connect app settings screen.</figcaption>
        </figure>
      </article>

      <article class="step">
        <div>
          <span class="step-number">2</span>
          <h3>Add your calendar link</h3>
          <p>Paste a private HTTPS calendar feed into <strong>Calendar ICS URL</strong>. Google Calendar, Apple iCloud Calendar, Outlook, and many calendar tools can publish private <code>.ics</code> links.</p>
          <ul class="checklist">
            <li>Use the private address, not a public webpage link.</li>
            <li>Keep the link private because anyone with it may be able to read that calendar feed.</li>
          </ul>
        </div>
        <figure class="screenshot-frame screenshot-placeholder">
          <div class="phone-placeholder" role="img" aria-label="Placeholder screenshot: Calendar ICS URL field">
            <div class="screen-bar"></div>
            <div class="screen-line"></div>
            <div class="screen-field">Calendar ICS URL field</div>
            <div class="screen-line short"></div>
          </div>
          <figcaption>Placeholder screenshot: Calendar ICS URL field.</figcaption>
        </figure>
      </article>

      <article class="step">
        <div>
          <span class="step-number">3</span>
          <h3>Choose timing</h3>
          <p>Choose your <strong>Calendar time zone</strong>, set the <strong>Morning window start</strong> and <strong>Morning window end</strong>, then decide when RiseCue should check for tomorrow's wake target.</p>
          <ul class="checklist">
            <li>Leave <strong>Manual workflow time</strong> blank to use the watch's configured Sleep Time.</li>
            <li>Enter a 24-hour time such as <code>21:30</code> if you want RiseCue to check at a fixed watch-local time.</li>
            <li>Use <strong>Minutes before event</strong> and <strong>Extra buffer minutes</strong> to move the alert earlier.</li>
          </ul>
        </div>
        <figure class="screenshot-frame screenshot-placeholder">
          <div class="phone-placeholder" role="img" aria-label="Placeholder screenshot: time and alert settings">
            <div class="screen-bar"></div>
            <div class="screen-field">Calendar time zone</div>
            <div class="screen-field">Manual workflow time</div>
            <div class="screen-line short"></div>
          </div>
          <figcaption>Placeholder screenshot: time and alert settings.</figcaption>
        </figure>
      </article>
    </section>

    <section class="callout" aria-labelledby="public-token-title">
      <h2 id="public-token-title">Public app token setting</h2>
      <p>For the built-in public endpoint, leave <strong>Calendar endpoint token</strong> blank. Public RiseCue builds send the developer-managed token automatically only when the endpoint URL is <code>${safePublicEndpointUrl}</code>.</p>
    </section>

    <section aria-labelledby="optional-title">
      <h2 id="optional-title">Optional settings</h2>
      <div class="settings-grid">
        <div class="mini-panel">
          <h3>Sunrise alerts</h3>
          <p>Turn on <strong>Enable sunrise alerts</strong>, then enter decimal latitude and longitude. Sunrise is calculated on the watch and is not sent to the calendar endpoint.</p>
        </div>
        <div class="mini-panel">
          <h3>Alert feel</h3>
          <p>Set <strong>Snooze minutes</strong>, <strong>Alert mode</strong>, <strong>Tone style</strong>, and <strong>Vibration style</strong> to match how forceful the wake alert should be.</p>
        </div>
        <div class="mini-panel">
          <h3>Notification body</h3>
          <p>Use <code>{eventTitle}</code> and <code>{eventStartLocal}</code> in the notification body template.</p>
        </div>
        <div class="mini-panel">
          <h3>Morning window</h3>
          <p>RiseCue looks for timed events inside the morning window and ignores all-day events.</p>
        </div>
      </div>
    </section>

    <section class="advanced" aria-labelledby="advanced-title">
      <details>
        <summary id="advanced-title">Custom or self-hosted endpoint</summary>
        <p>Use this only when you run your own RiseCue-compatible endpoint. Set <strong>Calendar endpoint URL</strong> to your hosted <code>/next-morning-event</code> URL, set <strong>Calendar endpoint token</strong> to the token your service expects, and set <strong>Calendar ICS URL</strong> only when your endpoint allows request-supplied calendar URLs.</p>
        <p>If your endpoint already has <code>CALENDAR_ICS_URL</code> configured on the server, leave <strong>Calendar ICS URL</strong> blank in Garmin app settings.</p>
      </details>
    </section>

    <section class="troubleshooting" aria-labelledby="troubleshooting-title">
      <h2 id="troubleshooting-title">Troubleshooting</h2>
      <div class="trouble-grid">
        <div>
          <h3>Missing calendar URL</h3>
          <p>Confirm <strong>Calendar ICS URL</strong> is filled in when using the public endpoint, then sync settings to the watch.</p>
        </div>
        <div>
          <h3>Invalid endpoint or token</h3>
          <p>For the public app, keep the default endpoint URL and leave the token blank. Custom endpoints need their own matching token.</p>
        </div>
        <div>
          <h3>Sunrise says setup</h3>
          <p>Turn on sunrise alerts and enter both latitude and longitude as decimal degrees.</p>
        </div>
        <div>
          <h3>No wake target found</h3>
          <p>Check that tomorrow has a timed event inside the morning window, or enable sunrise alerts as a fallback target.</p>
        </div>
      </div>
    </section>

    <p class="footer">Need the privacy details? Read the <a href="/privacy">${safeAppName} Privacy Policy</a>.</p>
  </main>
</body>
</html>`;
}

export function renderPrivacyPolicyHtml({
  appName = process.env.PRIVACY_APP_NAME || DEFAULT_PRIVACY_APP_NAME,
  contactEmail = process.env.PRIVACY_CONTACT_EMAIL || '',
  effectiveDate = process.env.PRIVACY_EFFECTIVE_DATE || DEFAULT_PRIVACY_EFFECTIVE_DATE,
  publicEndpointOrigin = process.env.PRIVACY_PUBLIC_ENDPOINT_ORIGIN || DEFAULT_PUBLIC_ENDPOINT_ORIGIN
} = {}) {
  const safeAppName = escapeHtml(appName);
  const safeEffectiveDate = escapeHtml(effectiveDate);
  const publicOrigin = normalizePublicEndpointOrigin(publicEndpointOrigin);
  const publicEndpointUrl = `${publicOrigin}${PUBLIC_CALENDAR_ENDPOINT_PATH}`;
  const safePublicOrigin = escapeHtml(publicOrigin);
  const safePublicEndpointUrl = escapeHtml(publicEndpointUrl);
  const contactHtml = renderContactHtml(safeAppName, contactEmail);

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${safeAppName} Privacy Policy</title>
  <link rel="icon" type="image/png" href="${FAVICON_PATH}">
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

    <p>${safeAppName} is a Garmin Connect IQ app that helps schedule a wake notification based on your next morning calendar event and, if enabled, sunrise. This policy applies when the app uses the public RiseCue service at <a href="${safePublicOrigin}">${safePublicOrigin}</a>, including the calendar endpoint at <code>${safePublicEndpointUrl}</code>. If you change the app to use another endpoint, that service's privacy practices are separate from this policy.</p>

    <h2>Data processed by the watch app</h2>
    <p>The app stores the settings you configure on your Garmin device or through Garmin Connect, such as the calendar endpoint URL, optional Calendar ICS URL, time zone, morning window, notification text, lead and buffer minutes, snooze length, and alert preferences. If you use the public endpoint, you do not need to enter a calendar endpoint token; public builds may include a developer-managed endpoint token in the app package so the public endpoint can reject unauthenticated requests. If you choose a different endpoint, any endpoint token you enter is stored as an app setting and sent only to that configured endpoint. If you enable sunrise alerts, the app also stores the latitude and longitude you enter for sunrise calculation.</p>
    <p>When a wake notification is scheduled, the app may temporarily store the selected event title and start time on the watch so it can show the notification later.</p>

    <h2>Data processed by the calendar endpoint</h2>
    <p>When your watch is configured to use <code>${safePublicEndpointUrl}</code> with your own calendar, the watch sends your private HTTPS Calendar ICS URL to the public endpoint in the <code>X-RiseCue-Calendar-Url</code> request header. The public endpoint fetches that ICS calendar feed and looks for the first timed event in the configured morning window. Calendar event titles, start times, end times, recurrence details, the private calendar feed URL, and the calendar feed response pass through the public endpoint while the request is processed. The public endpoint returns only the event status, event title, and event start time needed by the watch app.</p>
    <p>Requests to the public endpoint may also include technical metadata such as IP address, user agent, request path, query parameters for the morning window or time zone, the <code>X-RiseCue-Calendar-Url</code> header if configured, and the developer-managed endpoint token embedded in public app builds. The public endpoint may keep access logs containing some of that metadata.</p>

    <h2>How data is used</h2>
    <p>Data is used to find the next morning calendar event, schedule or display a wake notification, troubleshoot the service, secure the public endpoint, reduce unauthenticated endpoint traffic, and maintain the app. It is not used for advertising, profiling, or sale to third parties.</p>

    <h2>Retention</h2>
    <p>The public endpoint processes calendar data in memory and does not intentionally store calendar feed URLs, calendar contents, event titles, or event times after the request completes. Operational logs kept by the hosting provider, reverse proxy, or deployment platform may be retained according to that service's settings. On the watch, the last scheduled event title and time may remain in local app storage until replaced, cleared, or the app is removed.</p>

    <h2>Sharing</h2>
    <p>Calendar data may be processed by the hosting provider for <code>${safePublicOrigin}</code> and by your calendar provider when the public endpoint fetches the ICS feed. Data may also be disclosed if required by law or to protect the app, service, users, or others.</p>
    <p>Data submitted to the ${safeAppName} public endpoint is submitted to the app developer, not to Garmin. Garmin is not responsible for that data.</p>

    <h2>Location data</h2>
    <p>${safeAppName} does not collect location data by default. If you enable sunrise alerts, the latitude and longitude you enter are used on the watch for sunrise calculation and are not sent to the public endpoint.</p>

    <h2>Your choices</h2>
    <p>You can stop sending calendar data to the public endpoint by disabling RiseCue alerts, removing the Calendar ICS URL, changing the calendar endpoint URL away from <code>${safePublicEndpointUrl}</code>, or uninstalling the app. You can disable sunrise alerts or remove sunrise coordinates in app settings. You may use the contact method below to request deletion of user data under the developer's control.</p>

    <h2>Security</h2>
    <p>Keep your private Calendar ICS URL private. The public endpoint uses HTTPS and a developer-managed token to reduce unauthenticated traffic, but the token is not user-specific. No internet-connected service can be guaranteed completely secure.</p>

    <h2>Changes</h2>
    <p>This policy may be updated when the app or public endpoint changes how data is collected, used, stored, or disclosed.</p>

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

async function faviconResponse(res) {
  try {
    const body = await readFile(APP_ICON_URL);
    res.writeHead(200, {
      'Content-Type': 'image/png',
      'Content-Length': body.length,
      'Cache-Control': 'public, max-age=86400'
    });
    res.end(body);
  } catch {
    res.writeHead(404, {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-store'
    });
    res.end('favicon not found');
  }
}

export function createServer({
  icsUrl = process.env.CALENDAR_ICS_URL,
  defaultTimeZone = process.env.CALENDAR_TIME_ZONE || DEFAULT_TIME_ZONE,
  endpointToken = process.env.ENDPOINT_TOKEN || '',
  allowRequestCalendarUrl = process.env.ALLOW_REQUEST_CALENDAR_URL,
  nextMorningEventHandler = nextMorningEvent,
  privacyPolicyOptions,
  howToOptions
} = {}) {
  const requestCalendarUrlsAllowed = parseBooleanFlag(allowRequestCalendarUrl);

  return http.createServer(async (req, res) => {
    const requestUrl = new URL(req.url, 'http://localhost');

    if (requestUrl.pathname === '/health') {
      jsonResponse(res, 200, { ok: true });
      return;
    }

    if (requestUrl.pathname === FAVICON_PATH) {
      await faviconResponse(res);
      return;
    }

    if (requestUrl.pathname === '/privacy' || requestUrl.pathname === '/privacy/') {
      htmlResponse(res, 200, renderPrivacyPolicyHtml(privacyPolicyOptions));
      return;
    }

    if (requestUrl.pathname === '/how-to' || requestUrl.pathname === '/how-to/') {
      htmlResponse(res, 200, renderHowToHtml(howToOptions));
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
        now: parseNowQueryParameter(requestUrl.searchParams),
        timeZone: resolveTimeZoneQueryParameter(
          requestUrl.searchParams.get('timeZone'),
          defaultTimeZone
        ),
        windowStart: requestUrl.searchParams.get('windowStart') || DEFAULT_WINDOW_START,
        windowEnd: requestUrl.searchParams.get('windowEnd') || DEFAULT_WINDOW_END
      });

      jsonResponse(res, 200, payload);
    } catch (error) {
      if (error instanceof CalendarUrlError || error instanceof RequestParameterError) {
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
    console.log(`RiseCue endpoint listening on http://${host}:${port}`);
  });
}
