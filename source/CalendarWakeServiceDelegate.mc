using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.System;

(:background)
class CalendarWakeServiceDelegate extends System.ServiceDelegate {
    var _sunriseTarget;
    var _sunriseStatus;

    function initialize() {
        ServiceDelegate.initialize();
        _sunriseTarget = null;
        _sunriseStatus = null;
    }

    function onSleepTime() {
        CalendarWakeScheduler.registerSleepEvent();

        if (!CalendarWakeConfig.isEnabled()) {
            CalendarWakeScheduler.storeStatus("Wake alerts disabled");
            Background.exit({ "status" => "disabled" });
            return;
        }

        var sunriseResult = CalendarWakeScheduler.createSunriseTargetResult();
        _sunriseTarget = CalendarWakeScheduler.getSunriseResultTarget(sunriseResult);
        _sunriseStatus = CalendarWakeScheduler.getSunriseResultStatus(sunriseResult);

        var endpoint = CalendarWakeConfig.getEndpointUrl();
        if (endpoint == null || endpoint.equals("")) {
            finishWithTarget(null, "Calendar endpoint is not configured", "missing_endpoint", true);
            return;
        }

        var params = {
            "windowStart" => CalendarWakeConfig.getMorningStart(),
            "windowEnd" => CalendarWakeConfig.getMorningEnd()
        };
        var timeZone = CalendarWakeConfig.getTimeZone();
        if (timeZone != null && !timeZone.equals("")) {
            params["timeZone"] = timeZone;
        }

        var headers = {
            "Accept" => "application/json"
        };
        var endpointToken = CalendarWakeConfig.getEndpointToken();
        if (endpointToken != null && !endpointToken.equals("")) {
            headers["X-Calendar-Wake-Token"] = endpointToken;
        }

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        try {
            CalendarWakeScheduler.storeStatus("Checking calendar");
            Communications.makeWebRequest(endpoint, params, options, method(:onCalendarResponse));
        } catch (ex) {
            finishWithTarget(null, "Calendar request failed", "request_start_failed", true);
        }
    }

    function onTemporalEvent() {
        CalendarWakeScheduler.showWakeNotification();
        Background.exit({ "status" => "alert_fired" });
    }

    function onCalendarResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void {
        if (responseCode != 200 || data == null) {
            finishWithTarget(null, "Calendar request returned " + responseCode, "request_failed", true);
            return;
        }

        var response = data as Lang.Dictionary;
        if (response.get("hasEvent") != true) {
            finishWithTarget(null, "No morning events found", "no_event", false);
            return;
        }

        var eventStartEpoch = response.get("eventStartEpochSec");
        if (eventStartEpoch == null) {
            finishWithTarget(null, "Calendar response missing event time", "invalid_response", true);
            return;
        }

        var eventTitle = "Calendar event";
        var eventStartLocal = "";
        var responseTitle = response.get("eventTitle");
        var responseStartLocal = response.get("eventStartLocal");
        var responseStartDisplay = response.get("eventStartDisplay");

        if (responseTitle != null) {
            eventTitle = responseTitle.toString();
        }

        if (responseStartDisplay != null) {
            eventStartLocal = responseStartDisplay.toString();
        } else if (responseStartLocal != null) {
            eventStartLocal = responseStartLocal.toString();
        }

        var calendarTarget = CalendarWakeScheduler.makeWakeTarget(eventTitle, eventStartEpoch, eventStartLocal);
        finishWithTarget(calendarTarget, "No wake target found", "no_target", false);
    }

    function finishWithTarget(calendarTarget, noTargetStatus, noTargetExitStatus, notifyWhenNoTarget) {
        var target = CalendarWakeScheduler.chooseEarlierWakeTarget(calendarTarget, _sunriseTarget);
        if (target == null) {
            var status = mergeSunriseStatus(noTargetStatus);
            CalendarWakeScheduler.storeStatus(status);
            if (notifyWhenNoTarget) {
                CalendarWakeScheduler.showStatusNotification("Calendar Wake", status + ".");
            }
            Background.exit({ "status" => noTargetExitStatus });
            return;
        }

        var scheduled = CalendarWakeScheduler.scheduleWakeTarget(target);
        if (!scheduled) {
            CalendarWakeScheduler.showStatusNotification("Calendar Wake", "Could not schedule wake alert.");
            Background.exit({ "status" => "schedule_failed" });
            return;
        }

        Background.exit({ "status" => "scheduled" });
    }

    function mergeSunriseStatus(status) {
        if (_sunriseStatus == null) {
            return status;
        }

        var sunriseStatus = _sunriseStatus.toString();
        if (sunriseStatus.equals("")) {
            return status;
        }

        return status + "; " + sunriseStatus;
    }
}
