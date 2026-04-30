using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.WatchUi;

class RiseCueDelegate extends WatchUi.BehaviorDelegate {
    var _sunriseTarget;
    var _sunriseStatus;

    function initialize() {
        BehaviorDelegate.initialize();
        _sunriseTarget = null;
        _sunriseStatus = null;
    }

    function onSelect() {
        RiseCueScheduler.clearPreviewState();
        RiseCueScheduler.registerWorkflowTriggers();

        if (RiseCueScheduler.hasInvalidManualWorkflowTime()) {
            WatchUi.requestUpdate();
            return true;
        }

        if (!RiseCueConfig.isEnabled()) {
            RiseCueScheduler.storeStatus("Wake alerts disabled");
            WatchUi.requestUpdate();
            return true;
        }

        var sunriseResult = RiseCueScheduler.createSunriseTargetResult();
        _sunriseTarget = RiseCueScheduler.getSunriseResultTarget(sunriseResult);
        _sunriseStatus = RiseCueScheduler.getSunriseResultStatus(sunriseResult);

        var endpoint = RiseCueConfig.getEndpointUrl();
        if (endpoint == null || endpoint.equals("")) {
            finishManualRefresh(null, "Calendar endpoint is not configured", true);
            return true;
        }

        try {
            RiseCueScheduler.storeStatus("Checking calendar");
            WatchUi.requestUpdate();
            Communications.makeWebRequest(
                endpoint,
                RiseCueWorkflow.buildCalendarParams(),
                RiseCueWorkflow.buildCalendarOptions(endpoint),
                method(:onManualRefreshResponse)
            );
        } catch (ex) {
            finishManualRefresh(null, "Calendar request failed", true);
        }

        return true;
    }

    function onManualRefreshResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void {
        if (responseCode != 200 || data == null) {
            finishManualRefresh(null, "Calendar request returned " + responseCode, true);
            return;
        }

        var response = data as Lang.Dictionary;
        if (!RiseCueWorkflow.hasCalendarEvent(response)) {
            finishManualRefresh(null, "No morning events found", false);
            return;
        }

        var calendarTarget = RiseCueWorkflow.makeCalendarTarget(response);
        if (calendarTarget == null) {
            finishManualRefresh(null, "Calendar response missing event time", true);
            return;
        }

        finishManualRefresh(calendarTarget, "No wake target found", false);
    }

    function finishManualRefresh(calendarTarget, noTargetStatus, notifyWhenNoTarget) {
        var target = RiseCueScheduler.chooseEarlierWakeTarget(calendarTarget, _sunriseTarget);
        if (target == null) {
            var status = RiseCueWorkflow.mergeStatus(noTargetStatus, _sunriseStatus);
            RiseCueScheduler.clearPreviewState();
            RiseCueScheduler.storeStatus(status);
            if (notifyWhenNoTarget) {
                RiseCueScheduler.showStatusNotification("RiseCue", status + ".");
            }
            WatchUi.requestUpdate();
            return;
        }

        if (RiseCueScheduler.shouldQueueManualRefresh(target)) {
            if (!RiseCueScheduler.scheduleWakeTarget(target)) {
                RiseCueScheduler.showStatusNotification("RiseCue", "Could not schedule wake alert.");
            }
        } else {
            RiseCueScheduler.storePreviewWakeTarget(target);
        }

        WatchUi.requestUpdate();
    }
}
