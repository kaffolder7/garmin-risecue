using Toybox.Application.Properties;

module CalendarWakeConfig {
    const PROP_ENABLED = "enabled";
    const PROP_ENDPOINT_URL = "endpointUrl";
    const PROP_ENDPOINT_TOKEN = "endpointToken";
    const PROP_NOTIFICATION_BODY = "notificationBody";
    const PROP_TIME_ZONE = "timeZone";
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

    const ACTION_SNOOZE = "snooze";
    const ACTION_DISMISS = "dismiss";

    const STORAGE_STATUS = "status";
    const STORAGE_STATUS_AT = "statusAt";
    const STORAGE_LAST_EVENT_TITLE = "lastEventTitle";
    const STORAGE_LAST_EVENT_START = "lastEventStart";
    const STORAGE_LAST_ALERT_EPOCH = "lastAlertEpoch";

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
        return getString(PROP_ENDPOINT_URL, "");
    }

    function getEndpointToken() {
        return getString(PROP_ENDPOINT_TOKEN, "");
    }

    function getNotificationBody() {
        return getString(PROP_NOTIFICATION_BODY, "Upcoming: {eventTitle} at {eventStartLocal}");
    }

    function getTimeZone() {
        return getString(PROP_TIME_ZONE, "America/Indiana/Indianapolis");
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
        return getNumber(PROP_SNOOZE_MINUTES, 10);
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
