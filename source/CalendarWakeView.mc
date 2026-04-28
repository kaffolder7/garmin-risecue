using Toybox.Application.Storage;
using Toybox.Background;
using Toybox.Graphics;
using Toybox.Time;
using Toybox.WatchUi;

class CalendarWakeView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, (height * 15) / 100, Graphics.FONT_LARGE, "Calendar Wake", Graphics.TEXT_JUSTIFY_CENTER);

        var enabled = CalendarWakeConfig.isEnabled();
        var endpoint = CalendarWakeConfig.getEndpointUrl();
        var configured = endpoint != null && !endpoint.equals("");
        var sunriseEnabled = CalendarWakeConfig.isSunriseEnabled();
        var sunriseConfigured = CalendarWakeConfig.getSunriseLatitude() != null
            && CalendarWakeConfig.getSunriseLongitude() != null;
        var manualTime = CalendarWakeConfig.getManualWorkflowTime();
        var manualDisplay = CalendarWakeScheduler.getManualWorkflowTimeDisplay();
        var manualConfigured = manualDisplay != null;
        var manualStatus = manualConfigured
            ? manualDisplay
            : ((manualTime != null && !manualTime.equals("")) ? "Invalid" : "Off");
        var status = Storage.getValue(CalendarWakeConfig.STORAGE_STATUS);
        var eventTitle = Storage.getValue(CalendarWakeConfig.STORAGE_LAST_EVENT_TITLE);
        var eventStart = Storage.getValue(CalendarWakeConfig.STORAGE_LAST_EVENT_START);
        var alertEpoch = Storage.getValue(CalendarWakeConfig.STORAGE_LAST_ALERT_EPOCH);

        drawRow(dc, "Enabled", enabled ? "Yes" : "No", (height * 30) / 100);
        drawRow(dc, "Endpoint", configured ? "Set" : "Missing", (height * 38) / 100);
        drawRow(dc, "Sunrise", sunriseEnabled ? (sunriseConfigured ? "On" : "Setup") : "Off", (height * 46) / 100);
        drawRow(dc, "Manual run", manualStatus, (height * 54) / 100);
        drawRow(dc, "Trigger", manualConfigured ? "Manual" : (Background.getSleepEventRegistered() ? "Sleep" : "Not set"), (height * 62) / 100);

        if (eventTitle != null && eventStart != null) {
            drawCentered(dc, "Next: " + eventTitle, (height * 72) / 100, Graphics.FONT_XTINY);
            drawCentered(dc, eventStart, (height * 79) / 100, Graphics.FONT_XTINY);
        } else if (status != null) {
            drawCentered(dc, status, (height * 74) / 100, Graphics.FONT_SMALL);
        } else {
            drawCentered(dc, "Waiting for trigger", (height * 74) / 100, Graphics.FONT_SMALL);
        }

        if (alertEpoch != null) {
            drawCentered(dc, "Alert epoch: " + alertEpoch, (height * 90) / 100, Graphics.FONT_XTINY);
        }
    }

    function drawRow(dc, label, value, y) {
        var width = dc.getWidth();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText((width * 22) / 100, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText((width * 78) / 100, y, Graphics.FONT_SMALL, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    function drawCentered(dc, text, y, font) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
