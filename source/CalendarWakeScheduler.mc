using Toybox.Application.Storage;
using Toybox.Attention;
using Toybox.Background;
using Toybox.Lang;
using Toybox.Notifications;
using Toybox.Time;

module CalendarWakeScheduler {
    const MIN_TEMPORAL_DELAY_SECONDS = 300;
    const MAX_PATTERN_STEPS = 8;
    const MIN_TONE_FREQUENCY = 100;
    const MAX_TONE_FREQUENCY = 10000;
    const MIN_PATTERN_DURATION = 50;
    const MAX_TONE_DURATION = 2000;
    const MIN_VIBE_STRENGTH = 0;
    const MAX_VIBE_STRENGTH = 100;
    const MAX_VIBE_DURATION = 3000;

    function registerSleepEvent() {
        try {
            if (!Background.getSleepEventRegistered()) {
                Background.registerForSleepEvent();
            }
            storeStatus("Sleep Time trigger registered");
        } catch (ex) {
            storeStatus("Could not register Sleep Time trigger");
        }
    }

    function storeStatus(message) {
        try {
            Storage.setValue(CalendarWakeConfig.STORAGE_STATUS, message);
            Storage.setValue(CalendarWakeConfig.STORAGE_STATUS_AT, Time.now().value());
        } catch (ex) {
        }
    }

    function calculateAlertEpoch(eventStartEpoch) {
        var leadSeconds = CalendarWakeConfig.getLeadMinutes() * 60;
        var bufferSeconds = CalendarWakeConfig.getBufferMinutes() * 60;
        return eventStartEpoch - leadSeconds - bufferSeconds;
    }

    function scheduleAlert(eventTitle, eventStartEpoch, eventStartLocal) {
        var alertEpoch = calculateAlertEpoch(eventStartEpoch);
        var scheduled = registerTemporalEvent(alertEpoch);

        if (scheduled) {
            try {
                Storage.setValue(CalendarWakeConfig.STORAGE_LAST_EVENT_TITLE, eventTitle);
                Storage.setValue(CalendarWakeConfig.STORAGE_LAST_EVENT_START, eventStartLocal);
                Storage.setValue(CalendarWakeConfig.STORAGE_LAST_ALERT_EPOCH, alertEpoch);
            } catch (ex) {
            }
            storeStatus("Wake alert scheduled");
        }

        return scheduled;
    }

    function scheduleSnooze() {
        var snoozeEpoch = Time.now().value() + (CalendarWakeConfig.getSnoozeMinutes() * 60);
        var scheduled = registerTemporalEvent(snoozeEpoch);
        if (scheduled) {
            storeStatus("Snoozed wake alert");
        }
        return scheduled;
    }

    function registerTemporalEvent(epochSeconds) {
        var nowEpoch = Time.now().value();
        if (epochSeconds <= nowEpoch + MIN_TEMPORAL_DELAY_SECONDS) {
            storeStatus("Alert time is too soon or has passed");
            return false;
        }

        try {
            Background.registerForTemporalEvent(new Time.Moment(epochSeconds));
            return true;
        } catch (ex) {
            storeStatus("Could not schedule wake alert");
            return false;
        }
    }

    function showWakeNotification() {
        var storedTitle = Storage.getValue(CalendarWakeConfig.STORAGE_LAST_EVENT_TITLE);
        var storedStart = Storage.getValue(CalendarWakeConfig.STORAGE_LAST_EVENT_START);
        var eventTitle = storedTitle == null ? "Calendar event" : storedTitle.toString();
        var eventStartLocal = storedStart == null ? "" : storedStart.toString();

        var subtitle = eventStartLocal.equals("") ? eventTitle : eventStartLocal;
        var body = renderNotificationBody(eventTitle, eventStartLocal);

        if (Notifications has :showNotification) {
            Notifications.showNotification("Wake up", subtitle, {
                :body => body,
                :data => {
                    "eventTitle" => eventTitle,
                    "eventStartLocal" => eventStartLocal
                },
                :actions => [
                    { :label => "Snooze", :data => CalendarWakeConfig.ACTION_SNOOZE },
                    { :label => "Dismiss", :data => CalendarWakeConfig.ACTION_DISMISS }
                ],
                :dismissPrevious => true
            });
        }

        runAttentionPattern();
        storeStatus("Wake alert fired");
    }

    function renderNotificationBody(eventTitle, eventStartLocal) {
        var template = CalendarWakeConfig.getNotificationBody();
        if (template == null || template.equals("")) {
            template = "Upcoming: {eventTitle} at {eventStartLocal}";
        }

        var body = replaceToken(template, "{eventTitle}", eventTitle);
        body = replaceToken(body, "{eventStartLocal}", eventStartLocal);
        return body;
    }

    function replaceToken(text, token, value) {
        var result = "";
        var cursor = 0;
        var tokenLength = token.length();
        var textLength = text.length();

        while (cursor < textLength) {
            var tail = text.substring(cursor, null);
            var offset = tail.find(token);

            if (offset == null) {
                result += tail;
                return result;
            }

            var nextIndex = cursor + offset;
            var prefix = text.substring(cursor, nextIndex);
            if (prefix != null) {
                result += prefix;
            }

            result += value;
            cursor = nextIndex + tokenLength;
        }

        return result;
    }

    function showStatusNotification(title, body) {
        if (Notifications has :showNotification) {
            Notifications.showNotification(title, "", {
                :body => body,
                :dismissPrevious => true
            });
        }
    }

    function runAttentionPattern() {
        var mode = CalendarWakeConfig.getAlertMode();
        if (mode == CalendarWakeConfig.ALERT_MODE_NOTIFICATION_ONLY) {
            return;
        }

        runVibrationPattern();

        if (mode == CalendarWakeConfig.ALERT_MODE_TONE_VIBRATE) {
            runTonePattern();
        }
    }

    function runVibrationPattern() {
        if (!(Attention has :vibrate) || !(Attention has :VibeProfile)) {
            return;
        }

        try {
            Attention.vibrate(getVibrationProfiles());
        } catch (ex) {
            storeStatus("Could not run vibration pattern");
        }
    }

    function runTonePattern() {
        if (!(Attention has :playTone)) {
            return;
        }

        var style = CalendarWakeConfig.getToneStyle();

        try {
            if (style == CalendarWakeConfig.TONE_STYLE_CUSTOM) {
                if (Attention has :ToneProfile) {
                    var customPairs = parsePatternPairs(
                        CalendarWakeConfig.getCustomTonePattern(),
                        MIN_TONE_FREQUENCY,
                        MAX_TONE_FREQUENCY,
                        MIN_PATTERN_DURATION,
                        MAX_TONE_DURATION
                    );

                    if (customPairs != null) {
                        Attention.playTone({
                            :toneProfile => getToneProfiles(customPairs),
                            :repeatCount => clamp(CalendarWakeConfig.getToneRepeatCount(), 1, 5)
                        });
                        return;
                    }
                }

                storeStatus("Invalid custom tone pattern");
            }

            Attention.playTone(getPredefinedTone(style));
        } catch (ex) {
            storeStatus("Could not play tone");
        }
    }

    function getPredefinedTone(style) {
        if (style == CalendarWakeConfig.TONE_STYLE_LOUD_BEEP) {
            return Attention.TONE_LOUD_BEEP;
        } else if (style == CalendarWakeConfig.TONE_STYLE_ALERT_HIGH) {
            return Attention.TONE_ALERT_HI;
        } else if (style == CalendarWakeConfig.TONE_STYLE_ALERT_LOW) {
            return Attention.TONE_ALERT_LO;
        } else if (style == CalendarWakeConfig.TONE_STYLE_TIME_ALERT) {
            return Attention.TONE_TIME_ALERT;
        } else if (style == CalendarWakeConfig.TONE_STYLE_CANARY) {
            return Attention.TONE_CANARY;
        }

        return Attention.TONE_ALARM;
    }

    function getToneProfiles(pairs) {
        var typedPairs = pairs as Lang.Array<Lang.Array<Lang.Number>>;
        var profiles = new Lang.Array<Attention.ToneProfile>[typedPairs.size()];

        for (var index = 0; index < typedPairs.size(); index++) {
            profiles[index] = new Attention.ToneProfile(typedPairs[index][0], typedPairs[index][1]);
        }

        return profiles;
    }

    function getVibrationProfiles() {
        var style = CalendarWakeConfig.getVibrationStyle();

        if (style == CalendarWakeConfig.VIBRATION_STYLE_CUSTOM) {
            var customPairs = parsePatternPairs(
                CalendarWakeConfig.getCustomVibrationPattern(),
                MIN_VIBE_STRENGTH,
                MAX_VIBE_STRENGTH,
                MIN_PATTERN_DURATION,
                MAX_VIBE_DURATION
            );

            if (customPairs != null) {
                return getVibeProfiles(customPairs);
            }

            storeStatus("Invalid custom vibration pattern");
        } else if (style == CalendarWakeConfig.VIBRATION_STYLE_LONG_BUZZ) {
            return [
                new Attention.VibeProfile(75, 2500)
            ];
        } else if (style == CalendarWakeConfig.VIBRATION_STYLE_PROGRESSIVE_RAMP) {
            return [
                new Attention.VibeProfile(20, 500),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(35, 500),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(55, 600),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(75, 800),
                new Attention.VibeProfile(90, 1000)
            ];
        } else if (style == CalendarWakeConfig.VIBRATION_STYLE_URGENT_PULSE) {
            return [
                new Attention.VibeProfile(100, 250),
                new Attention.VibeProfile(0, 120),
                new Attention.VibeProfile(100, 250),
                new Attention.VibeProfile(0, 120),
                new Attention.VibeProfile(100, 250),
                new Attention.VibeProfile(0, 120),
                new Attention.VibeProfile(100, 500)
            ];
        }

        return getDefaultVibrationProfiles();
    }

    function getDefaultVibrationProfiles() {
        return [
            new Attention.VibeProfile(80, 900),
            new Attention.VibeProfile(0, 300),
            new Attention.VibeProfile(80, 900)
        ];
    }

    function getVibeProfiles(pairs) {
        var typedPairs = pairs as Lang.Array<Lang.Array<Lang.Number>>;
        var profiles = new Lang.Array<Attention.VibeProfile>[typedPairs.size()];

        for (var index = 0; index < typedPairs.size(); index++) {
            profiles[index] = new Attention.VibeProfile(typedPairs[index][0], typedPairs[index][1]);
        }

        return profiles;
    }

    function parsePatternPairs(pattern, firstMin, firstMax, durationMin, durationMax) {
        if (pattern == null || pattern.equals("")) {
            return null;
        }

        var pairs = [];
        var cursor = 0;
        var length = pattern.length();

        while (cursor < length && pairs.size() < MAX_PATTERN_STEPS) {
            var tail = pattern.substring(cursor, null);
            var commaOffset = tail.find(",");
            var segmentEnd = commaOffset == null ? length : cursor + commaOffset;
            var segment = pattern.substring(cursor, segmentEnd);
            var pair = parsePatternPair(segment, firstMin, firstMax, durationMin, durationMax);

            if (pair == null) {
                return null;
            }

            pairs.add(pair);

            if (commaOffset == null) {
                break;
            }

            cursor = segmentEnd + 1;
        }

        return pairs.size() == 0 ? null : pairs;
    }

    function parsePatternPair(segment, firstMin, firstMax, durationMin, durationMax) {
        if (segment == null || segment.equals("")) {
            return null;
        }

        var colonOffset = segment.find(":");
        if (colonOffset == null) {
            return null;
        }

        var firstValue = segment.substring(0, colonOffset).toNumber();
        var durationValue = segment.substring(colonOffset + 1, null).toNumber();

        if (firstValue == null || durationValue == null) {
            return null;
        }

        return [
            clamp(firstValue, firstMin, firstMax),
            clamp(durationValue, durationMin, durationMax)
        ];
    }

    function clamp(value, minimum, maximum) {
        if (value < minimum) {
            return minimum;
        } else if (value > maximum) {
            return maximum;
        }

        return value;
    }
}
