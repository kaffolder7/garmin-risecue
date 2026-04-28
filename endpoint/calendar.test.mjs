import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createServer,
  formatLocalDisplay,
  nextMorningEventFromIcsText,
  parseClockMinutes,
  renderPrivacyPolicyHtml,
  tomorrowWindow
} from './server.mjs';

function calendarWith(body) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Calendar Wake Tests//EN',
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
    effectiveDate: '2026-04-28'
  });

  assert.match(html, /RiseCue Privacy Policy/);
  assert.match(html, /mailto:privacy%40example.com/);
  assert.match(html, /Data submitted to RiseCue or its endpoint is submitted to the app developer or endpoint operator, not to Garmin/);
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
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
