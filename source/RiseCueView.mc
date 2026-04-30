using Toybox.Application.Storage;
using Toybox.Background;
using Toybox.Graphics;
using Toybox.Time;
using Toybox.Time.Gregorian;
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
        var previewTitle = Storage.getValue(RiseCueConfig.STORAGE_PREVIEW_EVENT_TITLE);
        var previewStart = Storage.getValue(RiseCueConfig.STORAGE_PREVIEW_EVENT_START);
        var previewAlertEpoch = Storage.getValue(RiseCueConfig.STORAGE_PREVIEW_ALERT_EPOCH);
        var sleepRegistered = Background.getSleepEventRegistered();
        var leadMinutes = RiseCueConfig.getLeadMinutes();
        var bufferMinutes = RiseCueConfig.getBufferMinutes();

        drawBrandHeader(dc, centerX, top, size);

        var workflow = getWorkflowStatus(manualConfigured, manualTime, manualDisplay, sleepRegistered);
        var sunriseStatus = sunriseEnabled ? (sunriseConfigured ? "On" : "Setup") : "Off";
        var leadStatus = getLeadStatus(leadMinutes, bufferMinutes);
        var summarizedStatus = status == null ? null : summarizeStatus(status.toString());
        var isChecking = summarizedStatus != null && summarizedStatus.equals("Checking calendar");
        var hasQueuedAlert = alertEpoch != null && eventTitle != null;
        var hasPreview = previewAlertEpoch != null && previewTitle != null;
        var stateLabel = getStateLabel(enabled, configured, hasQueuedAlert, hasPreview, isChecking);
        var stateColor = getStateColor(enabled, configured, hasQueuedAlert, hasPreview, isChecking);
        drawPill(
            dc,
            centerX - ((size * 30) / 200),
            top + ((size * 26) / 100),
            (size * 30) / 100,
            pillHeight(size),
            stateColor,
            COLOR_TEXT,
            stateLabel
        );

        if (hasQueuedAlert) {
            drawSectionLabel(dc, "ALERT QUEUED", top + ((size * 36) / 100), safeWidth(size, 72));
            drawCenteredWithin(dc, formatEpochTime(alertEpoch), top + ((size * 43) / 100), Graphics.FONT_SMALL, safeWidth(size, 76), COLOR_TEXT);
            drawSectionLabel(dc, "TARGET", top + ((size * 60) / 100), safeWidth(size, 62));
            drawCenteredWithin(dc, eventTitle.toString(), top + ((size * 66) / 100), Graphics.FONT_XTINY, safeWidth(size, 76), COLOR_TEXT);
            drawCenteredWithin(dc, compactTargetDisplay(eventStart), top + ((size * 72) / 100), Graphics.FONT_XTINY, safeWidth(size, 70), COLOR_MUTED);
            drawCenteredWithin(dc, getQueuedNote(manualConfigured), top + ((size * 82) / 100), Graphics.FONT_XTINY, safeWidth(size, 66), COLOR_MUTED);
        } else if (hasPreview) {
            drawSectionLabel(dc, "PREVIEW", top + ((size * 36) / 100), safeWidth(size, 72));
            drawCenteredWithin(dc, "Would alert " + formatEpochTime(previewAlertEpoch), top + ((size * 43) / 100), Graphics.FONT_TINY, safeWidth(size, 84), COLOR_ACCENT);
            drawSectionLabel(dc, "TARGET", top + ((size * 60) / 100), safeWidth(size, 62));
            drawCenteredWithin(dc, previewTitle.toString(), top + ((size * 66) / 100), Graphics.FONT_XTINY, safeWidth(size, 76), COLOR_TEXT);
            drawCenteredWithin(dc, compactTargetDisplay(previewStart), top + ((size * 72) / 100), Graphics.FONT_XTINY, safeWidth(size, 70), COLOR_MUTED);
            drawCenteredWithin(dc, getPreviewQueueNote(manualConfigured, manualDisplay), top + ((size * 82) / 100), Graphics.FONT_XTINY, safeWidth(size, 66), COLOR_MUTED);
        } else if (isChecking) {
            drawSectionLabel(dc, "CHECKING", top + ((size * 38) / 100), safeWidth(size, 72));
            drawCenteredWithin(dc, "Calendar", top + ((size * 48) / 100), Graphics.FONT_SMALL, safeWidth(size, 76), COLOR_TEXT);
            drawCenteredWithin(dc, "Please wait", top + ((size * 64) / 100), Graphics.FONT_XTINY, safeWidth(size, 70), COLOR_MUTED);
        } else {
            drawSectionLabel(dc, "NO ALERT QUEUED", top + ((size * 38) / 100), safeWidth(size, 72));
            drawCenteredWithin(dc, getEmptyStateMain(enabled, configured, summarizedStatus), top + ((size * 48) / 100), Graphics.FONT_TINY, safeWidth(size, 80), COLOR_TEXT);
            drawCenteredWithin(dc, getNextCheckLine(workflow), top + ((size * 63) / 100), Graphics.FONT_XTINY, safeWidth(size, 76), COLOR_MUTED);
            drawCenteredWithin(dc, "START checks now", top + ((size * 72) / 100), Graphics.FONT_XTINY, safeWidth(size, 70), COLOR_ACCENT);
        }

        if (!hasQueuedAlert && !hasPreview) {
            drawCenteredWithin(dc, getHealthLine(sunriseStatus, leadStatus), top + ((size * 82) / 100), Graphics.FONT_XTINY, safeWidth(size, 66), COLOR_DIM);
        }

        drawBuildVersion(dc, centerX, top, size);
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
            var iconY = top + ((size * 4) / 100);

            if (sourceWidth == iconSize && sourceHeight == iconSize) {
                dc.drawBitmap(iconX, iconY, _launcherIcon);
            } else {
                dc.drawScaledBitmap(iconX, iconY, iconSize, iconSize, _launcherIcon);
            }
        }

        drawCenteredWithin(dc, "RiseCue", top + ((size * 16) / 100), titleFont, safeWidth(size, 70), COLOR_TEXT);
    }

    function drawBuildVersion(dc, centerX, top, size) {
        if (!RiseCueBuildConfig.shouldShowBuildVersion()) {
            return;
        }

        var version = RiseCueBuildConfig.getAppBuildVersion();
        if (version == null || version.equals("")) {
            return;
        }

        drawTinyText(dc, centerX, top + ((size * 90) / 100), version, safeWidth(size, 44), COLOR_DIM);
    }

    function drawTinyText(dc, centerX, y, text, maxWidth, color) {
        var pixelSize = 2;
        var value = text.toString();
        var textWidth = tinyTextWidth(value, pixelSize);
        var x = centerX - (textWidth / 2);
        var minX = centerX - (maxWidth / 2);
        var maxX = centerX + (maxWidth / 2);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        for (var index = 0; index < value.length(); index++) {
            var glyph = tinyGlyphPattern(value.substring(index, index + 1));
            for (var columnIndex = 0; columnIndex < 3; columnIndex++) {
                var column = (glyph >> (columnIndex * 5)) & 31;
                for (var rowIndex = 0; rowIndex < 5; rowIndex++) {
                    var pixelX = x + (columnIndex * pixelSize);
                    if (pixelX >= minX && pixelX + pixelSize <= maxX && (column & (1 << rowIndex)) != 0) {
                        dc.fillRectangle(pixelX, y + (rowIndex * pixelSize), pixelSize, pixelSize);
                    }
                }
            }

            x += (4 * pixelSize);
        }
    }

    function tinyTextWidth(text, pixelSize) {
        if (text == null || text.length() == 0) {
            return 0;
        }

        return (text.length() * 4 * pixelSize) - pixelSize;
    }

    function tinyPattern(column0, column1, column2) {
        return column0 | (column1 << 5) | (column2 << 10);
    }

    function tinyGlyphPattern(character) {
        if (character == null || character.equals(" ")) {
            return tinyPattern(0, 0, 0);
        } else if (character.equals(".") || character.equals(",")) {
            return tinyPattern(0, 16, 0);
        } else if (character.equals("-") || character.equals("_")) {
            return tinyPattern(4, 4, 4);
        } else if (character.equals("+")) {
            return tinyPattern(4, 14, 4);
        } else if (character.equals("0") || character.equals("O") || character.equals("o")) {
            return tinyPattern(31, 17, 31);
        } else if (character.equals("1")) {
            return tinyPattern(18, 31, 16);
        } else if (character.equals("2")) {
            return tinyPattern(29, 21, 23);
        } else if (character.equals("3")) {
            return tinyPattern(21, 21, 31);
        } else if (character.equals("4")) {
            return tinyPattern(7, 4, 31);
        } else if (character.equals("5") || character.equals("S") || character.equals("s")) {
            return tinyPattern(23, 21, 29);
        } else if (character.equals("6")) {
            return tinyPattern(31, 21, 29);
        } else if (character.equals("7")) {
            return tinyPattern(1, 29, 3);
        } else if (character.equals("8")) {
            return tinyPattern(31, 21, 31);
        } else if (character.equals("9")) {
            return tinyPattern(23, 21, 31);
        } else if (character.equals("A") || character.equals("a")) {
            return tinyPattern(30, 5, 30);
        } else if (character.equals("B") || character.equals("b")) {
            return tinyPattern(31, 21, 10);
        } else if (character.equals("C") || character.equals("c")) {
            return tinyPattern(31, 17, 17);
        } else if (character.equals("D") || character.equals("d")) {
            return tinyPattern(31, 17, 14);
        } else if (character.equals("E") || character.equals("e")) {
            return tinyPattern(31, 21, 17);
        } else if (character.equals("F") || character.equals("f")) {
            return tinyPattern(31, 5, 1);
        } else if (character.equals("G") || character.equals("g")) {
            return tinyPattern(31, 21, 29);
        } else if (character.equals("H") || character.equals("h")) {
            return tinyPattern(31, 4, 31);
        } else if (character.equals("I") || character.equals("i")) {
            return tinyPattern(17, 31, 17);
        } else if (character.equals("J") || character.equals("j")) {
            return tinyPattern(24, 16, 15);
        } else if (character.equals("K") || character.equals("k")) {
            return tinyPattern(31, 4, 27);
        } else if (character.equals("L") || character.equals("l")) {
            return tinyPattern(31, 16, 16);
        } else if (character.equals("M") || character.equals("m")) {
            return tinyPattern(31, 6, 31);
        } else if (character.equals("N") || character.equals("n")) {
            return tinyPattern(31, 14, 31);
        } else if (character.equals("P") || character.equals("p")) {
            return tinyPattern(31, 5, 7);
        } else if (character.equals("Q") || character.equals("q")) {
            return tinyPattern(15, 21, 31);
        } else if (character.equals("R") || character.equals("r")) {
            return tinyPattern(31, 5, 26);
        } else if (character.equals("T") || character.equals("t")) {
            return tinyPattern(1, 31, 1);
        } else if (character.equals("U") || character.equals("u")) {
            return tinyPattern(31, 16, 31);
        } else if (character.equals("V") || character.equals("v")) {
            return tinyPattern(15, 16, 15);
        } else if (character.equals("W") || character.equals("w")) {
            return tinyPattern(31, 12, 31);
        } else if (character.equals("X") || character.equals("x")) {
            return tinyPattern(27, 4, 27);
        } else if (character.equals("Y") || character.equals("y")) {
            return tinyPattern(3, 28, 3);
        } else if (character.equals("Z") || character.equals("z")) {
            return tinyPattern(25, 21, 19);
        }

        return tinyPattern(0, 4, 0);
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
        var iconSize = (size * 11) / 100;
        if (iconSize < 22) {
            return 22;
        } else if (iconSize > 42) {
            return 42;
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

    function getStateLabel(enabled, configured, hasQueuedAlert, hasPreview, isChecking) {
        if (!enabled) {
            return "PAUSED";
        } else if (!configured) {
            return "SETUP";
        } else if (hasQueuedAlert) {
            return "QUEUED";
        } else if (hasPreview) {
            return "PREVIEW";
        } else if (isChecking) {
            return "CHECKING";
        }

        return "READY";
    }

    function getStateColor(enabled, configured, hasQueuedAlert, hasPreview, isChecking) {
        if (!enabled) {
            return COLOR_DIM;
        } else if (!configured) {
            return COLOR_WARN;
        } else if (hasQueuedAlert) {
            return COLOR_GOOD;
        } else if (hasPreview || isChecking) {
            return COLOR_ACCENT;
        }

        return COLOR_DIM;
    }

    function getEmptyStateMain(enabled, configured, summarizedStatus) {
        if (!enabled) {
            return "Alerts paused";
        } else if (!configured) {
            return "Endpoint missing";
        } else if (summarizedStatus != null
            && (summarizedStatus.equals("Manual time needs HH:MM")
                || summarizedStatus.equals("Manual trigger failed")
                || summarizedStatus.equals("Sleep trigger failed"))) {
            return summarizedStatus;
        }

        return "Ready to check";
    }

    function getNextCheckLine(workflow) {
        if (workflow.equals("Invalid time")) {
            return "Fix manual time";
        } else if (workflow.equals("Not set")) {
            return "Trigger not set";
        }

        return "Checks at " + workflow;
    }

    function getQueuedNote(manualConfigured) {
        return manualConfigured ? "Manual check resumes after alert" : "Rechecks at Sleep Time";
    }

    function getPreviewQueueNote(manualConfigured, manualDisplay) {
        if (manualConfigured && manualDisplay != null) {
            return "Will queue at " + manualDisplay;
        }

        return "Will queue at Sleep Time";
    }

    function getHealthLine(sunriseStatus, leadStatus) {
        return "Sun " + sunriseStatus + " | Lead " + leadStatus;
    }

    function formatEpochTime(epoch) {
        if (epoch == null) {
            return "";
        }

        try {
            var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
            var hour = info.hour;
            var minute = info.min;
            var suffix = hour >= 12 ? "PM" : "AM";
            var displayHour = hour % 12;
            if (displayHour == 0) {
                displayHour = 12;
            }

            return displayHour + ":" + minute.format("%02d") + " " + suffix;
        } catch (ex) {
            return "";
        }
    }

    function compactTargetDisplay(value) {
        if (value == null) {
            return "";
        }

        var text = value.toString();
        var sunrisePrefix = "Sunrise at ";
        if (text.find(sunrisePrefix) == 0) {
            return text.substring(sunrisePrefix.length(), null);
        }

        var atOffset = text.find(" at ");
        if (atOffset != null) {
            return text.substring(atOffset + 4, null);
        }

        return text;
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
        } else if (status.equals("Wake target previewed")) {
            return "Preview ready";
        } else if (status.equals("Could not store wake preview")) {
            return "Preview failed";
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
