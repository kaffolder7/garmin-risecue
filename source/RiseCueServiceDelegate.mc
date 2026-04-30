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
        RiseCueScheduler.clearPreviewState();

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

        try {
            RiseCueScheduler.storeStatus("Checking calendar");
            Communications.makeWebRequest(
                endpoint,
                RiseCueWorkflow.buildCalendarParams(),
                RiseCueWorkflow.buildCalendarOptions(endpoint),
                method(:onCalendarResponse)
            );
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
        if (!RiseCueWorkflow.hasCalendarEvent(response)) {
            finishWithTarget(null, "No morning events found", "no_event", false);
            return;
        }

        var calendarTarget = RiseCueWorkflow.makeCalendarTarget(response);
        if (calendarTarget == null) {
            finishWithTarget(null, "Calendar response missing event time", "invalid_response", true);
            return;
        }
        finishWithTarget(calendarTarget, "No wake target found", "no_target", false);
    }

    function finishWithTarget(calendarTarget, noTargetStatus, noTargetExitStatus, notifyWhenNoTarget) {
        var target = RiseCueScheduler.chooseEarlierWakeTarget(calendarTarget, _sunriseTarget);
        if (target == null) {
            var status = RiseCueWorkflow.mergeStatus(noTargetStatus, _sunriseStatus);
            RiseCueScheduler.storeStatus(status);
            if (notifyWhenNoTarget) {
                RiseCueScheduler.showStatusNotification("RiseCue", status + ".");
            }
            Background.exit({ "status" => noTargetExitStatus });
            return;
        }

        var scheduled = RiseCueScheduler.scheduleWakeTarget(target);
        if (!scheduled) {
            RiseCueScheduler.showStatusNotification("RiseCue", "Could not schedule wake alert.");
            Background.exit({ "status" => "schedule_failed" });
            return;
        }

        Background.exit({ "status" => "scheduled" });
    }
}
