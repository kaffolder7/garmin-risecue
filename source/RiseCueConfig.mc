using Toybox.Application.Properties;

module RiseCueConfig {
    const PROP_ENABLED = "enabled";
    const PROP_ENDPOINT_URL = "endpointUrl";
    const DEFAULT_ENDPOINT_URL = "https://risecue.affolder.dev/next-morning-event";
    const PROP_CALENDAR_ICS_URL = "calendarIcsUrl";
    const PROP_ENDPOINT_TOKEN = "endpointToken";
    const PROP_NOTIFICATION_BODY = "notificationBody";
    const PROP_TIME_ZONE = "timeZone";
    const PROP_MANUAL_WORKFLOW_TIME = "manualWorkflowTime";
    const PROP_SUNRISE_ENABLED = "sunriseEnabled";
    const PROP_SUNRISE_LATITUDE = "sunriseLatitude";
    const PROP_SUNRISE_LONGITUDE = "sunriseLongitude";
    const PROP_LEAD_MINUTES = "leadMinutes";
    const PROP_BUFFER_MINUTES = "bufferMinutes";
    const PROP_MORNING_START = "morningStart";
    const PROP_MORNING_END = "morningEnd";
    const PROP_SNOOZE_MINUTES = "snoozeMinutes";
    const PROP_ALERT_MODE = "alertMode";
    const PROP_TONE_STYLE = "toneStyle";
    const PROP_CUSTOM_TONE_PATTERN = "customTonePattern";
    const PROP_TONE_REPEAT_COUNT = "toneRepeatCount";
    const PROP_VIBRATION_STYLE = "vibrationStyle";
    const PROP_CUSTOM_VIBRATION_PATTERN = "customVibrationPattern";

    const ALERT_MODE_VIBRATE = 0;
    const ALERT_MODE_TONE_VIBRATE = 1;
    const ALERT_MODE_NOTIFICATION_ONLY = 2;
    const ALERT_MODE_TONE_ONLY = 3;

    const TONE_STYLE_ALARM = 0;
    const TONE_STYLE_LOUD_BEEP = 1;
    const TONE_STYLE_ALERT_HIGH = 2;
    const TONE_STYLE_ALERT_LOW = 3;
    const TONE_STYLE_TIME_ALERT = 4;
    const TONE_STYLE_CANARY = 5;
    const TONE_STYLE_CUSTOM = 6;

    const VIBRATION_STYLE_DOUBLE_PULSE = 0;
    const VIBRATION_STYLE_LONG_BUZZ = 1;
    const VIBRATION_STYLE_PROGRESSIVE_RAMP = 2;
    const VIBRATION_STYLE_URGENT_PULSE = 3;
    const VIBRATION_STYLE_CUSTOM = 4;

    const TIME_ZONE_ENDPOINT_DEFAULT = 0;
    const TIME_ZONE_UTC = 1;
    const TIME_ZONE_AMERICA_NEW_YORK = 2;
    const TIME_ZONE_AMERICA_CHICAGO = 3;
    const TIME_ZONE_AMERICA_DENVER = 4;
    const TIME_ZONE_AMERICA_PHOENIX = 5;
    const TIME_ZONE_AMERICA_LOS_ANGELES = 6;
    const TIME_ZONE_AMERICA_ANCHORAGE = 7;
    const TIME_ZONE_PACIFIC_HONOLULU = 8;
    const TIME_ZONE_EUROPE_LONDON = 9;
    const TIME_ZONE_EUROPE_PARIS = 10;
    const TIME_ZONE_ASIA_TOKYO = 11;
    const TIME_ZONE_ASIA_SINGAPORE = 12;
    const TIME_ZONE_AUSTRALIA_SYDNEY = 13;

    const ACTION_SNOOZE = "snooze";
    const ACTION_DISMISS = "dismiss";

    const STORAGE_STATUS = "status";
    const STORAGE_STATUS_AT = "statusAt";
    const STORAGE_LAST_EVENT_TITLE = "lastEventTitle";
    const STORAGE_LAST_EVENT_START = "lastEventStart";
    const STORAGE_LAST_ALERT_EPOCH = "lastAlertEpoch";
    const STORAGE_WORKFLOW_TRIGGER_EPOCH = "workflowTriggerEpoch";
    const STORAGE_TEMPORAL_EVENT_PURPOSE = "temporalEventPurpose";

    const TEMPORAL_PURPOSE_ALERT = "alert";
    const TEMPORAL_PURPOSE_WORKFLOW = "workflow";

    const MIN_SNOOZE_MINUTES = 6;
    const MAX_SNOOZE_MINUTES = 60;

    function getBoolean(key, defaultValue) {
        try {
            var value = Properties.getValue(key);
            return value == null ? defaultValue : value;
        } catch (ex) {
            return defaultValue;
        }
    }

    function getNumber(key, defaultValue) {
        try {
            var value = Properties.getValue(key);
            return value == null ? defaultValue : value;
        } catch (ex) {
            return defaultValue;
        }
    }

    function getString(key, defaultValue) {
        try {
            var value = Properties.getValue(key);
            return value == null ? defaultValue : value;
        } catch (ex) {
            return defaultValue;
        }
    }

    function isEnabled() {
        return getBoolean(PROP_ENABLED, true);
    }

    function getEndpointUrl() {
        // return getString(PROP_ENDPOINT_URL, "");
        var value = getString(PROP_ENDPOINT_URL, DEFAULT_ENDPOINT_URL);
        return value == null || value.equals("") ? DEFAULT_ENDPOINT_URL : value;
    }

    function getCalendarIcsUrl() {
        return getString(PROP_CALENDAR_ICS_URL, "");
    }

    function getEndpointToken() {
        return getString(PROP_ENDPOINT_TOKEN, "");
    }

    function isDefaultEndpointUrl(endpoint) {
        return endpoint != null && endpoint.equals(DEFAULT_ENDPOINT_URL);
    }

    function getEndpointTokenForEndpoint(endpoint) {
        if (isDefaultEndpointUrl(endpoint)) {
            return RiseCueBuildConfig.getPublicEndpointToken();
        }

        return getEndpointToken();
    }

    function getNotificationBody() {
        return getString(PROP_NOTIFICATION_BODY, "Upcoming: {eventTitle} at {eventStartLocal}");
    }

    function getTimeZone() {
        var value = getNumber(PROP_TIME_ZONE, TIME_ZONE_ENDPOINT_DEFAULT);
        if (value == TIME_ZONE_UTC) {
            return "UTC";
        } else if (value == TIME_ZONE_AMERICA_NEW_YORK) {
            return "America/New_York";
        } else if (value == TIME_ZONE_AMERICA_CHICAGO) {
            return "America/Chicago";
        } else if (value == TIME_ZONE_AMERICA_DENVER) {
            return "America/Denver";
        } else if (value == TIME_ZONE_AMERICA_PHOENIX) {
            return "America/Phoenix";
        } else if (value == TIME_ZONE_AMERICA_LOS_ANGELES) {
            return "America/Los_Angeles";
        } else if (value == TIME_ZONE_AMERICA_ANCHORAGE) {
            return "America/Anchorage";
        } else if (value == TIME_ZONE_PACIFIC_HONOLULU) {
            return "Pacific/Honolulu";
        } else if (value == TIME_ZONE_EUROPE_LONDON) {
            return "Europe/London";
        } else if (value == TIME_ZONE_EUROPE_PARIS) {
            return "Europe/Paris";
        } else if (value == TIME_ZONE_ASIA_TOKYO) {
            return "Asia/Tokyo";
        } else if (value == TIME_ZONE_ASIA_SINGAPORE) {
            return "Asia/Singapore";
        } else if (value == TIME_ZONE_AUSTRALIA_SYDNEY) {
            return "Australia/Sydney";
        }

        return "";
    }

    function getManualWorkflowTime() {
        return getString(PROP_MANUAL_WORKFLOW_TIME, "");
    }

    function isSunriseEnabled() {
        return getBoolean(PROP_SUNRISE_ENABLED, false);
    }

    function getSunriseLatitude() {
        return getCoordinate(PROP_SUNRISE_LATITUDE, -90.0, 90.0);
    }

    function getSunriseLongitude() {
        return getCoordinate(PROP_SUNRISE_LONGITUDE, -180.0, 180.0);
    }

    function getCoordinate(key, minimum, maximum) {
        var value = getString(key, "");
        if (!isDecimalString(value)) {
            return null;
        }

        var coordinate = value.toDouble();
        if (coordinate == null || coordinate < minimum || coordinate > maximum) {
            return null;
        }

        return coordinate;
    }

    function isDecimalString(value) {
        if (value == null || value.equals("")) {
            return false;
        }

        var decimalCount = 0;
        var digitCount = 0;

        for (var index = 0; index < value.length(); index++) {
            var character = value.substring(index, index + 1);
            if (character == null) {
                return false;
            }

            if (character.equals("-") || character.equals("+")) {
                if (index != 0) {
                    return false;
                }
            } else if (character.equals(".")) {
                decimalCount++;
                if (decimalCount > 1) {
                    return false;
                }
            } else if (!isDigitCharacter(character)) {
                return false;
            } else {
                digitCount++;
            }
        }

        return digitCount > 0;
    }

    function isDigitCharacter(character) {
        return "0123456789".find(character) != null;
    }

    function getLeadMinutes() {
        return getNumber(PROP_LEAD_MINUTES, 60);
    }

    function getBufferMinutes() {
        return getNumber(PROP_BUFFER_MINUTES, 0);
    }

    function getMorningStart() {
        return getString(PROP_MORNING_START, "04:00");
    }

    function getMorningEnd() {
        return getString(PROP_MORNING_END, "12:00");
    }

    function getSnoozeMinutes() {
        var minutes = getNumber(PROP_SNOOZE_MINUTES, 10);
        if (minutes < MIN_SNOOZE_MINUTES) {
            return MIN_SNOOZE_MINUTES;
        } else if (minutes > MAX_SNOOZE_MINUTES) {
            return MAX_SNOOZE_MINUTES;
        }

        return minutes;
    }

    function getAlertMode() {
        return getNumber(PROP_ALERT_MODE, ALERT_MODE_VIBRATE);
    }

    function getToneStyle() {
        return getNumber(PROP_TONE_STYLE, TONE_STYLE_ALARM);
    }

    function getCustomTonePattern() {
        return getString(PROP_CUSTOM_TONE_PATTERN, "");
    }

    function getToneRepeatCount() {
        return getNumber(PROP_TONE_REPEAT_COUNT, 1);
    }

    function getVibrationStyle() {
        return getNumber(PROP_VIBRATION_STYLE, VIBRATION_STYLE_DOUBLE_PULSE);
    }

    function getCustomVibrationPattern() {
        return getString(PROP_CUSTOM_VIBRATION_PATTERN, "");
    }
}
