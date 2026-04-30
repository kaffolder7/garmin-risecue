import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import {
  createServer,
  formatLocalDisplay,
  parseBooleanFlag,
  resolveCalendarIcsUrl,
  nextMorningEventFromIcsText,
  parseClockMinutes,
  REQUEST_CALENDAR_URL_HEADER,
  validateRequestCalendarUrl,
  renderHowToHtml,
  renderPrivacyPolicyHtml,
  tomorrowWindow
} from './server.mjs';

function calendarWith(body) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//RiseCue Tests//EN',
    body.trim(),
    'END:VCALENDAR'
  ].join('\r\n');
}

test('parseClockMinutes accepts HH:mm and falls back for invalid values', () => {
  assert.equal(parseClockMinutes('04:30', 0), 270);
  assert.equal(parseClockMinutes('24:00', 123), 123);
  assert.equal(parseClockMinutes('nope', 123), 123);
});

test('tomorrowWindow creates the configured morning window in the target time zone', () => {
  const window = tomorrowWindow(new Date('2026-04-27T22:00:00Z'), {
    timeZone: 'UTC',
    windowStart: '04:00',
    windowEnd: '12:00'
  });

  assert.equal(window.start.toISOString(), '2026-04-28T04:00:00.000Z');
  assert.equal(window.end.toISOString(), '2026-04-28T12:00:00.000Z');
});

test('tomorrowWindow defaults to the endpoint time zone', () => {
  const window = tomorrowWindow(new Date('2026-04-27T22:00:00Z'));

  assert.equal(window.timeZone, 'America/New_York');
  assert.equal(window.start.toISOString(), '2026-04-28T08:00:00.000Z');
  assert.equal(window.end.toISOString(), '2026-04-28T16:00:00.000Z');
});

test('formatLocalDisplay renders a human time in America/New_York', () => {
  const display = formatLocalDisplay(
    new Date('2026-04-28T12:00:00Z'),
    'America/New_York'
  );

  assert.equal(display, 'Tue, Apr 28 at 8:00 AM EDT');
});

test('returns the first timed event tomorrow morning', () => {
  const ics = calendarWith(`
BEGIN:VEVENT
UID:event-one
SUMMARY:Work meeting
DTSTART:20260428T080000Z
DTEND:20260428T083000Z
END:VEVENT
`);

  const result = nextMorningEventFromIcsText({
    icsText: ics,
    now: new Date('2026-04-27T22:00:00Z'),
    timeZone: 'UTC'
  });

  assert.equal(result.hasEvent, true);
  assert.equal(result.eventTitle, 'Work meeting');
  assert.equal(result.eventStartEpochSec, 1777363200);
  assert.equal(result.eventStartLocal, '2026-04-28T08:00:00');
  assert.equal(result.eventStartDisplay, 'Tue, Apr 28 at 8:00 AM UTC');
  assert.equal(result.eventEndEpochSec, Math.floor(Date.parse('2026-04-28T08:30:00Z') / 1000));
  assert.equal(result.eventEndLocal, '2026-04-28T08:30:00');
  assert.equal(result.eventTargetEpochSec, result.eventStartEpochSec);
  assert.equal(result.eventTargetLocal, result.eventStartLocal);
  assert.equal(result.eventTargetDisplay, result.eventStartDisplay);
  assert.equal(result.eventTargetBasis, 'start');
});

test('uses the event end time for an overnight event ending in the morning window', () => {
  const ics = calendarWith(`
BEGIN:VEVENT
UID:event-overnight
SUMMARY:Night shift
DTSTART:20260427T200000Z
DTEND:20260428T063000Z
END:VEVENT
`);

  const result = nextMorningEventFromIcsText({
    icsText: ics,
    now: new Date('2026-04-27T22:00:00Z'),
    timeZone: 'UTC',
    windowStart: '04:00',
    windowEnd: '12:00'
  });

  assert.equal(result.hasEvent, true);
  assert.equal(result.eventTitle, 'Night shift');
  assert.equal(result.eventStartLocal, '2026-04-27T20:00:00');
  assert.equal(result.eventEndEpochSec, Math.floor(Date.parse('2026-04-28T06:30:00Z') / 1000));
  assert.equal(result.eventEndLocal, '2026-04-28T06:30:00');
  assert.equal(result.eventEndDisplay, 'Tue, Apr 28 at 6:30 AM UTC');
  assert.equal(result.eventTargetEpochSec, result.eventEndEpochSec);
  assert.equal(result.eventTargetLocal, result.eventEndLocal);
  assert.equal(result.eventTargetDisplay, result.eventEndDisplay);
  assert.equal(result.eventTargetBasis, 'end');
});

test('chooses an overnight event ending before a later morning event starts', () => {
  const ics = calendarWith(`
BEGIN:VEVENT
UID:event-morning
SUMMARY:Work meeting
DTSTART:20260428T080000Z
DTEND:20260428T083000Z
END:VEVENT
BEGIN:VEVENT
UID:event-overnight
SUMMARY:Night shift
DTSTART:20260427T200000Z
DTEND:20260428T063000Z
END:VEVENT
`);

  const result = nextMorningEventFromIcsText({
    icsText: ics,
    now: new Date('2026-04-27T22:00:00Z'),
    timeZone: 'UTC',
    windowStart: '04:00',
    windowEnd: '12:00'
  });

  assert.equal(result.hasEvent, true);
  assert.equal(result.eventTitle, 'Night shift');
  assert.equal(result.eventTargetLocal, '2026-04-28T06:30:00');
  assert.equal(result.eventTargetBasis, 'end');
});

test('expands recurring overnight events by end time in the morning window', () => {
  const ics = calendarWith(`
BEGIN:VEVENT
UID:event-recurring-overnight
SUMMARY:Recurring night shift
DTSTART:20260420T200000Z
DTEND:20260421T063000Z
RRULE:FREQ=WEEKLY;COUNT=4
END:VEVENT
`);

  const result = nextMorningEventFromIcsText({
    icsText: ics,
    now: new Date('2026-04-27T22:00:00Z'),
    timeZone: 'UTC',
    windowStart: '04:00',
    windowEnd: '12:00'
  });

  assert.equal(result.hasEvent, true);
  assert.equal(result.eventTitle, 'Recurring night shift');
  assert.equal(result.eventStartLocal, '2026-04-27T20:00:00');
  assert.equal(result.eventTargetLocal, '2026-04-28T06:30:00');
  assert.equal(result.eventTargetBasis, 'end');
});

test('ignores overnight events ending outside the configured morning window', () => {
  const ics = calendarWith(`
BEGIN:VEVENT
UID:event-too-late
SUMMARY:Long night shift
DTSTART:20260427T200000Z
DTEND:20260428T120000Z
END:VEVENT
`);

  const result = nextMorningEventFromIcsText({
    icsText: ics,
    now: new Date('2026-04-27T22:00:00Z'),
    timeZone: 'UTC',
    windowStart: '04:00',
    windowEnd: '12:00'
  });

  assert.deepEqual(result, { hasEvent: false });
});

test('ignores all-day events', () => {
  const ics = calendarWith(`
BEGIN:VEVENT
UID:event-all-day
SUMMARY:All day hold
DTSTART;VALUE=DATE:20260428
DTEND;VALUE=DATE:20260429
END:VEVENT
`);

  const result = nextMorningEventFromIcsText({
    icsText: ics,
    now: new Date('2026-04-27T22:00:00Z'),
    timeZone: 'UTC'
  });

  assert.deepEqual(result, { hasEvent: false });
});

test('expands simple weekly recurrences', () => {
  const ics = calendarWith(`
BEGIN:VEVENT
UID:event-weekly
SUMMARY:Weekly standup
DTSTART:20260421T080000Z
DTEND:20260421T083000Z
RRULE:FREQ=WEEKLY;COUNT=4
END:VEVENT
`);

  const result = nextMorningEventFromIcsText({
    icsText: ics,
    now: new Date('2026-04-27T22:00:00Z'),
    timeZone: 'UTC'
  });

  assert.equal(result.hasEvent, true);
  assert.equal(result.eventTitle, 'Weekly standup');
  assert.equal(result.eventStartLocal, '2026-04-28T08:00:00');
});

test('events outside the configured morning window do not trigger', () => {
  const ics = calendarWith(`
BEGIN:VEVENT
UID:event-late
SUMMARY:Late meeting
DTSTART:20260428T130000Z
DTEND:20260428T133000Z
END:VEVENT
`);

  const result = nextMorningEventFromIcsText({
    icsText: ics,
    now: new Date('2026-04-27T22:00:00Z'),
    timeZone: 'UTC',
    windowStart: '04:00',
    windowEnd: '12:00'
  });

  assert.deepEqual(result, { hasEvent: false });
});

test('privacy policy renders configured contact and Garmin disclosure', () => {
  const html = renderPrivacyPolicyHtml({
    appName: 'RiseCue',
    contactEmail: 'privacy@example.com',
    effectiveDate: '2026-04-28',
    publicEndpointOrigin: 'https://risecue.affolder.dev'
  });

  assert.match(html, /RiseCue Privacy Policy/);
  assert.match(html, /mailto:privacy%40example.com/);
  assert.match(html, /<link rel="icon" type="image\/png" href="\/favicon\.png">/);
  assert.match(html, /public RiseCue service at/);
  assert.match(html, /https:\/\/risecue\.affolder\.dev\/next-morning-event/);
  assert.match(html, /X-RiseCue-Calendar-Url/);
  assert.match(html, /private HTTPS Calendar ICS URL/);
  assert.match(html, /developer-managed endpoint token in the app package/);
  assert.match(html, /The public endpoint uses HTTPS and a developer-managed token to reduce unauthenticated traffic/);
  assert.match(html, /Data submitted to the RiseCue public endpoint is submitted to the app developer, not to Garmin/);
  assert.doesNotMatch(html, /self-host/i);
  assert.doesNotMatch(html, /endpoint operator/i);
});

test('how-to page renders public setup guidance and placeholders', () => {
  const html = renderHowToHtml({
    appName: 'RiseCue',
    publicEndpointOrigin: 'https://risecue.affolder.dev'
  });

  assert.match(html, /RiseCue Setup Guide/);
  assert.match(html, /Set up RiseCue in Garmin Connect/);
  assert.match(html, /wake notification/);
  assert.match(html, /does not create or change Garmin native alarms/);
  assert.match(html, /https:\/\/risecue\.affolder\.dev\/next-morning-event/);
  assert.match(html, /Calendar ICS URL/);
  assert.match(html, /Leave blank for public builds/);
  assert.match(html, /screenshot-placeholder/);
  assert.match(html, /Placeholder screenshot: Garmin app settings screen/);
  assert.match(html, /Placeholder screenshot: Calendar ICS URL field/);
  assert.match(html, /Custom or self-hosted endpoint/);
  assert.match(html, /CALENDAR_ICS_URL/);
});

test('endpoint token protects next-morning-event when configured', async () => {
  const server = createServer({
    icsUrl: 'https://example.com/calendar.ics',
    endpointToken: 'secret',
    privacyPolicyOptions: {
      contactEmail: 'privacy@example.com'
    }
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    const denied = await fetch(`http://127.0.0.1:${port}/next-morning-event`);
    assert.equal(denied.status, 401);

    const health = await fetch(`http://127.0.0.1:${port}/health`);
    assert.equal(health.status, 200);

    const privacy = await fetch(`http://127.0.0.1:${port}/privacy`);
    assert.equal(privacy.status, 200);
    assert.match(privacy.headers.get('content-type'), /text\/html/);
    assert.match(await privacy.text(), /RiseCue Privacy Policy/);

    const howTo = await fetch(`http://127.0.0.1:${port}/how-to`);
    assert.equal(howTo.status, 200);
    assert.match(howTo.headers.get('content-type'), /text\/html/);
    assert.match(await howTo.text(), /RiseCue Setup Guide/);

    const howToSlash = await fetch(`http://127.0.0.1:${port}/how-to/`);
    assert.equal(howToSlash.status, 200);
    assert.match(howToSlash.headers.get('content-type'), /text\/html/);
    assert.match(await howToSlash.text(), /RiseCue Setup Guide/);

    const favicon = await fetch(`http://127.0.0.1:${port}/favicon.png`);
    assert.equal(favicon.status, 200);
    assert.match(favicon.headers.get('content-type'), /image\/png/);
    assert.ok((await favicon.arrayBuffer()).byteLength > 0);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('parseBooleanFlag accepts only explicit true values', () => {
  assert.equal(parseBooleanFlag(true), true);
  assert.equal(parseBooleanFlag('true'), true);
  assert.equal(parseBooleanFlag(' TRUE '), true);
  assert.equal(parseBooleanFlag(false), false);
  assert.equal(parseBooleanFlag('false'), false);
  assert.equal(parseBooleanFlag('1'), false);
});

test('validates request-supplied calendar URLs', () => {
  assert.equal(
    validateRequestCalendarUrl(' https://calendar.google.com/calendar/ical/example/basic.ics '),
    'https://calendar.google.com/calendar/ical/example/basic.ics'
  );

  for (const value of [
    '',
    'not-a-url',
    'http://calendar.example/basic.ics',
    'https://user:pass@calendar.example/basic.ics',
    'https://localhost/basic.ics',
    'https://localhost.localdomain/basic.ics',
    'https://calendar.local/basic.ics',
    'https://127.0.0.1/basic.ics',
    'https://10.0.0.1/basic.ics',
    'https://172.16.0.1/basic.ics',
    'https://192.168.1.1/basic.ics',
    'https://169.254.1.1/basic.ics',
    'https://[::1]/basic.ics',
    'https://[fc00::1]/basic.ics',
    'https://[fe80::1]/basic.ics'
  ]) {
    assert.throws(
      () => validateRequestCalendarUrl(value),
      { code: 'invalid_calendar_url' },
      `${value} should be rejected`
    );
  }
});

test('resolves request calendar URL only when opt-in is enabled', () => {
  assert.equal(
    resolveCalendarIcsUrl({
      defaultIcsUrl: 'https://env.example/calendar.ics',
      requestIcsUrl: '',
      allowRequestCalendarUrl: true
    }),
    'https://env.example/calendar.ics'
  );

  assert.equal(
    resolveCalendarIcsUrl({
      defaultIcsUrl: 'https://env.example/calendar.ics',
      requestIcsUrl: 'https://request.example/calendar.ics',
      allowRequestCalendarUrl: false
    }),
    'https://env.example/calendar.ics'
  );

  assert.equal(
    resolveCalendarIcsUrl({
      defaultIcsUrl: 'https://env.example/calendar.ics',
      requestIcsUrl: 'https://request.example/calendar.ics',
      allowRequestCalendarUrl: true
    }),
    'https://request.example/calendar.ics'
  );

  assert.throws(
    () => resolveCalendarIcsUrl({
      defaultIcsUrl: '',
      requestIcsUrl: '',
      allowRequestCalendarUrl: true
    }),
    {
      code: 'missing_calendar_url',
      message: 'X-RiseCue-Calendar-Url header is required'
    }
  );
});

async function withTestServer(options, callback) {
  const seenRequests = [];
  const server = createServer({
    ...options,
    nextMorningEventHandler: async (request) => {
      seenRequests.push(request);
      return { hasEvent: false };
    }
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  try {
    await callback({ port, seenRequests });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('endpoint falls back to configured calendar when dynamic header is absent', async () => {
  await withTestServer({
    icsUrl: 'https://env.example/calendar.ics',
    allowRequestCalendarUrl: true
  }, async ({ port, seenRequests }) => {
    const response = await fetch(`http://127.0.0.1:${port}/next-morning-event`);
    assert.equal(response.status, 200);
    assert.equal(seenRequests[0].icsUrl, 'https://env.example/calendar.ics');
  });
});

test('endpoint ignores request calendar header unless dynamic URLs are enabled', async () => {
  await withTestServer({
    icsUrl: 'https://env.example/calendar.ics',
    allowRequestCalendarUrl: false
  }, async ({ port, seenRequests }) => {
    const response = await fetch(`http://127.0.0.1:${port}/next-morning-event`, {
      headers: {
        'X-RiseCue-Calendar-Url': 'https://request.example/calendar.ics'
      }
    });

    assert.equal(response.status, 200);
    assert.equal(seenRequests[0].icsUrl, 'https://env.example/calendar.ics');
  });
});

test('endpoint uses request calendar header when dynamic URLs are enabled', async () => {
  await withTestServer({
    icsUrl: 'https://env.example/calendar.ics',
    allowRequestCalendarUrl: true
  }, async ({ port, seenRequests }) => {
    const response = await fetch(`http://127.0.0.1:${port}/next-morning-event`, {
      headers: {
        'X-RiseCue-Calendar-Url': 'https://request.example/calendar.ics'
      }
    });

    assert.equal(response.status, 200);
    assert.equal(seenRequests[0].icsUrl, 'https://request.example/calendar.ics');
  });
});

test('endpoint forwards valid now and timeZone query parameters', async () => {
  await withTestServer({
    icsUrl: 'https://env.example/calendar.ics',
    defaultTimeZone: 'America/New_York'
  }, async ({ port, seenRequests }) => {
    const query = new URLSearchParams({
      now: '2026-04-27T22:00:00Z',
      timeZone: 'UTC'
    });
    const response = await fetch(`http://127.0.0.1:${port}/next-morning-event?${query}`);

    assert.equal(response.status, 200);
    assert.equal(seenRequests[0].now.toISOString(), '2026-04-27T22:00:00.000Z');
    assert.equal(seenRequests[0].timeZone, 'UTC');
  });
});

test('endpoint rejects invalid now query parameter before fetching', async () => {
  await withTestServer({
    icsUrl: 'https://env.example/calendar.ics'
  }, async ({ port, seenRequests }) => {
    const query = new URLSearchParams({ now: 'not-a-date' });
    const response = await fetch(`http://127.0.0.1:${port}/next-morning-event?${query}`);
    const body = await response.json();

    assert.equal(response.status, 400);
    assert.equal(body.error, 'invalid_now');
    assert.equal(body.message, 'now query parameter must be a valid date/time');
    assert.equal(seenRequests.length, 0);
  });
});

test('endpoint rejects invalid timeZone query parameter before fetching', async () => {
  await withTestServer({
    icsUrl: 'https://env.example/calendar.ics'
  }, async ({ port, seenRequests }) => {
    const query = new URLSearchParams({ timeZone: 'Not/A_Zone' });
    const response = await fetch(`http://127.0.0.1:${port}/next-morning-event?${query}`);
    const body = await response.json();

    assert.equal(response.status, 400);
    assert.equal(body.error, 'invalid_time_zone');
    assert.equal(body.message, 'timeZone query parameter must be a valid IANA time zone');
    assert.equal(seenRequests.length, 0);
  });
});

test('endpoint requires request calendar header when dynamic URLs are enabled without fallback', async () => {
  await withTestServer({
    icsUrl: '',
    allowRequestCalendarUrl: true
  }, async ({ port, seenRequests }) => {
    const response = await fetch(`http://127.0.0.1:${port}/next-morning-event`);
    const body = await response.json();

    assert.equal(response.status, 400);
    assert.equal(body.error, 'missing_calendar_url');
    assert.equal(
      body.message,
      'X-RiseCue-Calendar-Url header is required'
    );
    assert.equal(seenRequests.length, 0);
  });
});

test('endpoint does not accept calendar URLs as query parameters', async () => {
  await withTestServer({
    icsUrl: 'https://env.example/calendar.ics',
    allowRequestCalendarUrl: true
  }, async ({ port, seenRequests }) => {
    const query = new URLSearchParams({
      calendarUrl: 'https://request.example/calendar.ics'
    });
    const response = await fetch(`http://127.0.0.1:${port}/next-morning-event?${query}`);

    assert.equal(response.status, 200);
    assert.equal(seenRequests[0].icsUrl, 'https://env.example/calendar.ics');
  });
});

test('endpoint rejects invalid dynamic calendar header before fetching', async () => {
  await withTestServer({
    icsUrl: 'https://env.example/calendar.ics',
    allowRequestCalendarUrl: true
  }, async ({ port, seenRequests }) => {
    const response = await fetch(`http://127.0.0.1:${port}/next-morning-event`, {
      headers: {
        'X-RiseCue-Calendar-Url': 'http://request.example/calendar.ics'
      }
    });
    const body = await response.json();

    assert.equal(response.status, 400);
    assert.equal(body.error, 'invalid_calendar_url');
    assert.equal(seenRequests.length, 0);
  });
});

test('watch request includes configured calendar URL header only from the new setting', async () => {
  const serviceDelegate = await readFile(new URL('../source/RiseCueServiceDelegate.mc', import.meta.url), 'utf8');
  const workflow = await readFile(new URL('../source/RiseCueWorkflow.mc', import.meta.url), 'utf8');
  const config = await readFile(new URL('../source/RiseCueConfig.mc', import.meta.url), 'utf8');
  const properties = await readFile(new URL('../resources/properties/properties.xml', import.meta.url), 'utf8');
  const settings = await readFile(new URL('../resources/settings/settings.xml', import.meta.url), 'utf8');
  const strings = await readFile(new URL('../resources/strings/strings.xml', import.meta.url), 'utf8');

  assert.match(config, /PROP_CALENDAR_ICS_URL = "calendarIcsUrl"/);
  assert.match(config, /function getCalendarIcsUrl\(\)/);
  assert.match(serviceDelegate, /RiseCueWorkflow\.buildCalendarOptions\(endpoint\)/);
  assert.match(workflow, /RiseCueConfig\.getCalendarIcsUrl\(\)/);
  assert.match(workflow, /headers\["X-RiseCue-Calendar-Url"\] = calendarIcsUrl/);
  assert.match(properties, /<property id="calendarIcsUrl" type="string">/);
  assert.match(settings, /propertyKey="@Properties\.calendarIcsUrl"/);
  assert.match(strings, /<string id="SettingCalendarIcsUrlTitle">Calendar ICS URL<\/string>/);
  assert.equal(workflow.includes('params["calendarUrl"]'), false);
  assert.equal(REQUEST_CALENDAR_URL_HEADER, 'x-risecue-calendar-url');
});

test('watch token selection uses compiled token only for the default public endpoint', async () => {
  const serviceDelegate = await readFile(new URL('../source/RiseCueServiceDelegate.mc', import.meta.url), 'utf8');
  const workflow = await readFile(new URL('../source/RiseCueWorkflow.mc', import.meta.url), 'utf8');
  const config = await readFile(new URL('../source/RiseCueConfig.mc', import.meta.url), 'utf8');
  const buildConfig = await readFile(new URL('../source/RiseCueBuildConfig.mc', import.meta.url), 'utf8');
  const settings = await readFile(new URL('../resources/settings/settings.xml', import.meta.url), 'utf8');
  const packageJson = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));
  const buildWatch = await readFile(new URL('../scripts/build-watch.sh', import.meta.url), 'utf8');
  const buildWatchPublic = await readFile(new URL('../scripts/build-watch-public.mjs', import.meta.url), 'utf8');
  const packageWatch = await readFile(new URL('../scripts/package-watch.sh', import.meta.url), 'utf8');
  const packageWatchPublic = await readFile(new URL('../scripts/package-watch-public.mjs', import.meta.url), 'utf8');

  assert.match(config, /DEFAULT_ENDPOINT_URL = "https:\/\/risecue\.affolder\.dev\/next-morning-event"/);
  assert.match(buildConfig, /module RiseCueBuildConfig/);
  assert.match(buildConfig, /\(:defaultPublicEndpointToken\)/);
  assert.match(buildConfig, /function getPublicEndpointToken\(\)/);
  assert.match(config, /function isDefaultEndpointUrl\(endpoint\)/);
  assert.match(config, /endpoint != null && endpoint\.equals\(DEFAULT_ENDPOINT_URL\)/);
  assert.match(config, /function getEndpointTokenForEndpoint\(endpoint\)/);
  assert.match(config, /RiseCueBuildConfig\.getPublicEndpointToken\(\)/);
  assert.match(config, /return getEndpointToken\(\)/);
  assert.match(serviceDelegate, /RiseCueWorkflow\.buildCalendarOptions\(endpoint\)/);
  assert.match(workflow, /RiseCueConfig\.getEndpointTokenForEndpoint\(endpoint\)/);
  assert.match(workflow, /headers\["X-RiseCue-Token"\] = endpointToken/);
  assert.equal(settings.includes('RISECUE_PUBLIC_ENDPOINT_TOKEN'), false);
  assert.equal(settings.includes('defaultPublicEndpointToken'), false);

  assert.equal(
    packageJson.scripts['build:watch:public'],
    'node --env-file-if-exists=.env scripts/build-watch-public.mjs'
  );
  assert.equal(
    packageJson.scripts['package:watch:public'],
    'node --env-file-if-exists=.env scripts/package-watch-public.mjs'
  );
  assert.match(buildWatchPublic, /RISECUE_EMBED_PUBLIC_ENDPOINT_TOKEN: '1'/);
  assert.match(buildWatch, /RISECUE_PUBLIC_ENDPOINT_TOKEN:-\$\{ENDPOINT_TOKEN:-\}/);
  assert.match(buildWatch, /RiseCueBuildConfigPublic\.mc/);
  assert.match(buildWatch, /base\.excludeAnnotations = defaultPublicEndpointToken/);
  assert.match(packageWatchPublic, /RISECUE_EMBED_PUBLIC_ENDPOINT_TOKEN: '1'/);
  assert.match(packageWatch, /RISECUE_PUBLIC_ENDPOINT_TOKEN:-\$\{ENDPOINT_TOKEN:-\}/);
  assert.match(packageWatch, /RiseCueBuildConfigPublic\.mc/);
  assert.match(packageWatch, /base\.excludeAnnotations = defaultPublicEndpointToken/);
});

test('watch response handling prefers calendar target fields with start fallback', async () => {
  const serviceDelegate = await readFile(new URL('../source/RiseCueServiceDelegate.mc', import.meta.url), 'utf8');
  const workflow = await readFile(new URL('../source/RiseCueWorkflow.mc', import.meta.url), 'utf8');

  assert.match(serviceDelegate, /RiseCueWorkflow\.makeCalendarTarget\(response\)/);
  assert.match(workflow, /response\.get\("eventTargetEpochSec"\)/);
  assert.match(workflow, /eventTargetEpoch = response\.get\("eventStartEpochSec"\)/);
  assert.match(workflow, /response\.get\("eventTargetDisplay"\)/);
  assert.match(workflow, /response\.get\("eventTargetLocal"\)/);
  assert.match(workflow, /RiseCueScheduler\.makeWakeTarget\(eventTitle, eventTargetEpoch, eventStartLocal\)/);
});
