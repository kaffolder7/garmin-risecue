using Toybox.Application.Storage;
using Toybox.Background;
using Toybox.Graphics;
using Toybox.Time;
using Toybox.WatchUi;

class RiseCueView extends WatchUi.View {
    const COLOR_SURFACE = Graphics.COLOR_BLACK;
    const COLOR_TEXT = Graphics.COLOR_WHITE;
    const COLOR_MUTED = Graphics.COLOR_LT_GRAY;
    const COLOR_DIM = Graphics.COLOR_DK_GRAY;
    const COLOR_GOOD = Graphics.COLOR_GREEN;
    const COLOR_WARN = Graphics.COLOR_ORANGE;
    const COLOR_ACCENT = Graphics.COLOR_BLUE;

    var _launcherIcon;

    function initialize() {
        View.initialize();
        _launcherIcon = WatchUi.loadResource($.Rez.Drawables.LauncherIcon);
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;
        var centerY = height / 2;
        var size = width < height ? width : height;
        var top = (height - size) / 2;

        dc.setColor(COLOR_SURFACE, COLOR_SURFACE);
        dc.clear();

        drawFrame(dc, centerX, centerY, size);

        var enabled = RiseCueConfig.isEnabled();
        var endpoint = RiseCueConfig.getEndpointUrl();
        var configured = endpoint != null && !endpoint.equals("");
        var sunriseEnabled = RiseCueConfig.isSunriseEnabled();
        var sunriseConfigured = RiseCueConfig.getSunriseLatitude() != null
            && RiseCueConfig.getSunriseLongitude() != null;
        var manualTime = RiseCueConfig.getManualWorkflowTime();
        var manualDisplay = RiseCueScheduler.getManualWorkflowTimeDisplay();
        var manualConfigured = manualDisplay != null;
        var status = Storage.getValue(RiseCueConfig.STORAGE_STATUS);
        var eventTitle = Storage.getValue(RiseCueConfig.STORAGE_LAST_EVENT_TITLE);
        var eventStart = Storage.getValue(RiseCueConfig.STORAGE_LAST_EVENT_START);
        var alertEpoch = Storage.getValue(RiseCueConfig.STORAGE_LAST_ALERT_EPOCH);
        var sleepRegistered = Background.getSleepEventRegistered();
        var leadMinutes = RiseCueConfig.getLeadMinutes();
        var bufferMinutes = RiseCueConfig.getBufferMinutes();

        drawBrandHeader(dc, centerX, top, size);

        var stateLabel = enabled ? (configured ? "ACTIVE" : "SETUP") : "PAUSED";
        var stateColor = enabled ? (configured ? COLOR_GOOD : COLOR_WARN) : COLOR_DIM;
        drawPill(
            dc,
            centerX - ((size * 30) / 200),
            top + ((size * 25) / 100),
            (size * 30) / 100,
            pillHeight(size),
            stateColor,
            COLOR_TEXT,
            stateLabel
        );

        var workflow = getWorkflowStatus(manualConfigured, manualTime, manualDisplay, sleepRegistered);
        var sunriseStatus = sunriseEnabled ? (sunriseConfigured ? "On" : "Setup") : "Off";
        var leadStatus = getLeadStatus(leadMinutes, bufferMinutes);

        var rowWidth = safeWidth(size, 80);
        var rowStart = top + ((size * 37) / 100);
        var rowGap = (size * 8) / 100;
        drawRow(dc, "Endpoint", configured ? "Ready" : "Missing", rowStart, rowWidth, configured ? COLOR_GOOD : COLOR_WARN);
        drawRow(dc, "Workflow", workflow, rowStart + rowGap, rowWidth, workflow.equals("Not set") || workflow.equals("Invalid time") ? COLOR_WARN : COLOR_TEXT);
        drawRow(dc, "Sunrise", sunriseStatus, rowStart + (rowGap * 2), rowWidth, sunriseStatus.equals("Setup") ? COLOR_WARN : COLOR_TEXT);
        drawRow(dc, "Lead", leadStatus, rowStart + (rowGap * 3), rowWidth, COLOR_TEXT);

        if (eventTitle != null && eventStart != null) {
            drawSectionLabel(dc, "NEXT TARGET", top + ((size * 69) / 100), safeWidth(size, 66));
            drawCenteredWithin(dc, eventTitle.toString(), top + ((size * 75) / 100), Graphics.FONT_XTINY, safeWidth(size, 76), COLOR_TEXT);
            drawCenteredWithin(dc, eventStart.toString(), top + ((size * 81) / 100), Graphics.FONT_XTINY, safeWidth(size, 70), COLOR_MUTED);
        } else if (status != null) {
            drawSectionLabel(dc, "STATUS", top + ((size * 70) / 100), safeWidth(size, 66));
            drawCenteredWithin(dc, summarizeStatus(status.toString()), top + ((size * 76) / 100), Graphics.FONT_XTINY, safeWidth(size, 76), COLOR_TEXT);
        } else {
            drawSectionLabel(dc, "STATUS", top + ((size * 70) / 100), safeWidth(size, 66));
            drawCenteredWithin(dc, "Waiting for trigger", top + ((size * 76) / 100), Graphics.FONT_XTINY, safeWidth(size, 76), COLOR_TEXT);
        }

        if (alertEpoch != null) {
            drawPill(
                dc,
                centerX - ((size * 42) / 200),
                top + ((size * 88) / 100),
                (size * 42) / 100,
                pillHeight(size),
                COLOR_DIM,
                COLOR_TEXT,
                "ALERT QUEUED"
            );
        }
    }

    function drawFrame(dc, centerX, centerY, size) {
        var radius = (size / 2) - 5;
        dc.setPenWidth(1);
        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(centerX, centerY, radius);

        var tickWidth = size / 12;
        var topY = centerY - radius + 7;
        var bottomY = centerY + radius - 7;
        dc.setColor(COLOR_ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(centerX - tickWidth, topY, centerX + tickWidth, topY);
        dc.drawLine(centerX - tickWidth, bottomY, centerX + tickWidth, bottomY);
        dc.setPenWidth(1);
    }

    function drawBrandHeader(dc, centerX, top, size) {
        var iconSize = iconDisplaySize(size);
        var titleFont = size < 280 ? Graphics.FONT_XTINY : Graphics.FONT_TINY;

        if (_launcherIcon != null) {
            var sourceWidth = _launcherIcon.getWidth();
            var sourceHeight = _launcherIcon.getHeight();
            var iconX = centerX - (iconSize / 2);
            var iconY = top + ((size * 6) / 100);

            if (sourceWidth == iconSize && sourceHeight == iconSize) {
                dc.drawBitmap(iconX, iconY, _launcherIcon);
            } else {
                dc.drawScaledBitmap(iconX, iconY, iconSize, iconSize, _launcherIcon);
            }
        }

        drawCenteredWithin(dc, "RiseCue", top + ((size * 16) / 100), titleFont, safeWidth(size, 70), COLOR_TEXT);
    }

    function drawRow(dc, label, value, y, maxWidth, valueColor) {
        var width = dc.getWidth();
        var left = (width - maxWidth) / 2;
        var right = left + maxWidth;
        var labelWidth = (maxWidth * 48) / 100;
        var valueWidth = (maxWidth * 48) / 100;

        drawTextWithin(dc, left, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT, labelWidth, COLOR_MUTED);
        drawTextWithin(dc, right, y, Graphics.FONT_TINY, value, Graphics.TEXT_JUSTIFY_RIGHT, valueWidth, valueColor);
    }

    function drawSectionLabel(dc, text, y, maxWidth) {
        var centerX = dc.getWidth() / 2;
        var textGap = dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) + 10;
        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(centerX - (maxWidth / 2), y + 8, centerX - (textGap / 2), y + 8);
        dc.drawLine(centerX + (textGap / 2), y + 8, centerX + (maxWidth / 2), y + 8);
        drawCenteredWithin(dc, text, y, Graphics.FONT_XTINY, maxWidth, COLOR_MUTED);
    }

    function drawPill(dc, x, y, width, height, fillColor, textColor, text) {
        if (width < height) {
            width = height;
        }

        var radius = height / 2;
        dc.setColor(fillColor, fillColor);
        dc.fillRectangle(x + radius, y, width - height, height);
        dc.fillCircle(x + radius, y + radius, radius);
        dc.fillCircle(x + width - radius, y + radius, radius);

        drawTextWithin(
            dc,
            x + (width / 2),
            y + (height / 2),
            Graphics.FONT_XTINY,
            text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER,
            width - (height / 2),
            textColor
        );
    }

    function drawCenteredWithin(dc, text, y, font, maxWidth, color) {
        drawTextWithin(dc, dc.getWidth() / 2, y, font, text, Graphics.TEXT_JUSTIFY_CENTER, maxWidth, color);
    }

    function drawTextWithin(dc, x, y, font, text, justification, maxWidth, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, fitText(dc, text, font, maxWidth), justification);
    }

    function fitText(dc, text, font, maxWidth) {
        if (text == null) {
            return "";
        }

        var value = text.toString();
        if (dc.getTextWidthInPixels(value, font) <= maxWidth) {
            return value;
        }

        var suffix = "...";
        var suffixWidth = dc.getTextWidthInPixels(suffix, font);
        if (suffixWidth >= maxWidth) {
            return "";
        }

        var endIndex = value.length();
        while (endIndex > 0) {
            var candidate = value.substring(0, endIndex);
            if (candidate != null
                && dc.getTextWidthInPixels(candidate, font) + suffixWidth <= maxWidth) {
                return candidate + suffix;
            }
            endIndex--;
        }

        return "";
    }

    function safeWidth(size, percent) {
        return (size * percent) / 100;
    }

    function pillHeight(size) {
        var height = (size * 6) / 100;
        return height < 18 ? 18 : height;
    }

    function iconDisplaySize(size) {
        var iconSize = (size * 8) / 100;
        if (iconSize < 20) {
            return 20;
        } else if (iconSize > 30) {
            return 30;
        }

        return iconSize;
    }

    function getWorkflowStatus(manualConfigured, manualTime, manualDisplay, sleepRegistered) {
        if (manualConfigured) {
            return manualDisplay;
        } else if (manualTime != null && !manualTime.equals("")) {
            return "Invalid time";
        } else if (sleepRegistered) {
            return "Sleep Time";
        }

        return "Not set";
    }

    function getLeadStatus(leadMinutes, bufferMinutes) {
        if (bufferMinutes > 0) {
            return leadMinutes + "m + " + bufferMinutes + "m";
        }

        return leadMinutes + "m";
    }

    function summarizeStatus(status) {
        if (status.equals("Sleep Time trigger registered")) {
            return "Sleep trigger ready";
        } else if (status.equals("Could not register Sleep Time trigger")) {
            return "Sleep trigger failed";
        } else if (status.equals("Manual workflow time must be HH:MM")) {
            return "Manual time needs HH:MM";
        } else if (status.equals("Manual workflow trigger scheduled")) {
            return "Manual trigger ready";
        } else if (status.equals("Manual workflow time is too soon")) {
            return "Manual time too soon";
        } else if (status.equals("Could not schedule manual workflow")) {
            return "Manual trigger failed";
        } else if (status.equals("Wake alert remains scheduled")) {
            return "Wake alert ready";
        } else if (status.equals("Wake alert scheduled")) {
            return "Wake alert ready";
        } else if (status.equals("Alert time is too soon or has passed")) {
            return "Alert time passed";
        } else if (status.equals("Could not schedule wake alert")) {
            return "Alert schedule failed";
        } else if (status.equals("Sunrise is not available on this device")) {
            return "Sunrise unavailable";
        } else if (status.equals("Sunrise location is not configured")) {
            return "Set sunrise location";
        } else if (status.equals("Sunrise time is unavailable")) {
            return "Sunrise unavailable";
        } else if (status.equals("Could not calculate sunrise")) {
            return "Sunrise failed";
        } else if (status.equals("Snoozed wake alert")) {
            return "Wake alert snoozed";
        } else if (status.equals("Could not register notification actions")) {
            return "Notification actions failed";
        } else if (status.equals("Invalid custom tone pattern")) {
            return "Tone pattern invalid";
        } else if (status.equals("Could not play tone")) {
            return "Tone failed";
        } else if (status.equals("Could not run vibration pattern")) {
            return "Vibration failed";
        } else if (status.equals("Invalid custom vibration pattern")) {
            return "Vibe pattern invalid";
        }

        return status;
    }
}
