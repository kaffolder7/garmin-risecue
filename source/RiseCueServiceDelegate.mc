using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.System;

(:background)
class RiseCueServiceDelegate extends System.ServiceDelegate {
    var _sunriseTarget;
    var _sunriseStatus;

    function initialize() {
        ServiceDelegate.initialize();
        _sunriseTarget = null;
        _sunriseStatus = null;
    }

    function onSleepTime() {
        RiseCueScheduler.registerWorkflowTriggers();
        if (RiseCueScheduler.isManualWorkflowTimeValid()) {
            RiseCueScheduler.storeStatus("Sleep Time skipped; manual workflow time is set");
            Background.exit({ "status" => "manual_override" });
            return;
        }

        runWakeWorkflow();
    }

    function onTemporalEvent() {
        if (RiseCueScheduler.isManualWorkflowTemporalEvent()) {
            RiseCueScheduler.clearTemporalEventPurpose();
            runWakeWorkflow();
            return;
        }

        RiseCueScheduler.clearTemporalEventPurpose();
        RiseCueScheduler.registerWorkflowTriggers();
        RiseCueScheduler.showWakeNotification();
        Background.exit({ "status" => "alert_fired" });
    }

    function runWakeWorkflow() {
        RiseCueScheduler.registerWorkflowTriggers();

        if (!RiseCueConfig.isEnabled()) {
            RiseCueScheduler.storeStatus("Wake alerts disabled");
            Background.exit({ "status" => "disabled" });
            return;
        }

        var sunriseResult = RiseCueScheduler.createSunriseTargetResult();
        _sunriseTarget = RiseCueScheduler.getSunriseResultTarget(sunriseResult);
        _sunriseStatus = RiseCueScheduler.getSunriseResultStatus(sunriseResult);

        var endpoint = RiseCueConfig.getEndpointUrl();
        if (endpoint == null || endpoint.equals("")) {
            finishWithTarget(null, "Calendar endpoint is not configured", "missing_endpoint", true);
            return;
        }

        var params = {
            "windowStart" => RiseCueConfig.getMorningStart(),
            "windowEnd" => RiseCueConfig.getMorningEnd()
        };
        var timeZone = RiseCueConfig.getTimeZone();
        if (timeZone != null && !timeZone.equals("")) {
            params["timeZone"] = timeZone;
        }

        var headers = {
            "Accept" => "application/json"
        };
        var calendarIcsUrl = RiseCueConfig.getCalendarIcsUrl();
        if (calendarIcsUrl != null && !calendarIcsUrl.equals("")) {
            headers["X-RiseCue-Calendar-Url"] = calendarIcsUrl;
        }

        var endpointToken = RiseCueConfig.getEndpointToken();
        if (endpointToken != null && !endpointToken.equals("")) {
            headers["X-RiseCue-Token"] = endpointToken;
        }

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        try {
            RiseCueScheduler.storeStatus("Checking calendar");
            Communications.makeWebRequest(endpoint, params, options, method(:onCalendarResponse));
        } catch (ex) {
            finishWithTarget(null, "Calendar request failed", "request_start_failed", true);
        }
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

        var eventTargetEpoch = response.get("eventTargetEpochSec");
        if (eventTargetEpoch == null) {
            eventTargetEpoch = response.get("eventStartEpochSec");
        }

        if (eventTargetEpoch == null) {
            finishWithTarget(null, "Calendar response missing event time", "invalid_response", true);
            return;
        }

        var eventTitle = "Calendar event";
        var eventStartLocal = "";
        var responseTitle = response.get("eventTitle");
        var responseTargetLocal = response.get("eventTargetLocal");
        var responseTargetDisplay = response.get("eventTargetDisplay");
        var responseStartLocal = response.get("eventStartLocal");
        var responseStartDisplay = response.get("eventStartDisplay");

        if (responseTitle != null) {
            eventTitle = responseTitle.toString();
        }

        if (responseTargetDisplay != null) {
            eventStartLocal = responseTargetDisplay.toString();
        } else if (responseTargetLocal != null) {
            eventStartLocal = responseTargetLocal.toString();
        } else if (responseStartDisplay != null) {
            eventStartLocal = responseStartDisplay.toString();
        } else if (responseStartLocal != null) {
            eventStartLocal = responseStartLocal.toString();
        }

        var calendarTarget = RiseCueScheduler.makeWakeTarget(eventTitle, eventTargetEpoch, eventStartLocal);
        finishWithTarget(calendarTarget, "No wake target found", "no_target", false);
    }

    function finishWithTarget(calendarTarget, noTargetStatus, noTargetExitStatus, notifyWhenNoTarget) {
        var target = RiseCueScheduler.chooseEarlierWakeTarget(calendarTarget, _sunriseTarget);
        if (target == null) {
            var status = mergeSunriseStatus(noTargetStatus);
            RiseCueScheduler.storeStatus(status);
            if (notifyWhenNoTarget) {
                RiseCueScheduler.showStatusNotification("Calendar Wake", status + ".");
            }
            Background.exit({ "status" => noTargetExitStatus });
            return;
        }

        var scheduled = RiseCueScheduler.scheduleWakeTarget(target);
        if (!scheduled) {
            RiseCueScheduler.showStatusNotification("Calendar Wake", "Could not schedule wake alert.");
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
