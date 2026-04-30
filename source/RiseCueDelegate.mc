using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.WatchUi;

module RiseCueActionMenu {
    const ACTION_START_SYNC = :startSync;
    const ACTION_CLEAR_ALERTS = :clearAlerts;
}

class RiseCueDelegate extends WatchUi.BehaviorDelegate {
    var _sunriseTarget;
    var _sunriseStatus;
    var _refreshingQueuedAlert;
    var _actionMenuDelegate;

    function initialize() {
        BehaviorDelegate.initialize();
        _sunriseTarget = null;
        _sunriseStatus = null;
        _refreshingQueuedAlert = false;
        _actionMenuDelegate = null;
    }

    function onSelect() {
        var menu = new WatchUi.ActionMenu(null);
        menu.addItem(new WatchUi.ActionMenuItem({ :label => "Check" }, RiseCueActionMenu.ACTION_START_SYNC));
        if (RiseCueScheduler.hasQueuedAlert()) {
            menu.addItem(new WatchUi.ActionMenuItem({ :label => "Clear" }, RiseCueActionMenu.ACTION_CLEAR_ALERTS));
        }

        _actionMenuDelegate = new RiseCueActionMenuDelegate(self);
        WatchUi.showActionMenu(menu, _actionMenuDelegate);
        return true;
    }

    function clearActionMenuDelegate() {
        _actionMenuDelegate = null;
    }

    function startSync() {
        _refreshingQueuedAlert = RiseCueScheduler.hasQueuedAlert();
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
        var refreshingQueuedAlert = _refreshingQueuedAlert;
        _refreshingQueuedAlert = false;
        var status = RiseCueWorkflow.mergeStatus(noTargetStatus, _sunriseStatus);
        var target = RiseCueScheduler.chooseEarlierWakeTarget(calendarTarget, _sunriseTarget);
        if (refreshingQueuedAlert && notifyWhenNoTarget) {
            RiseCueScheduler.clearPreviewState();
            RiseCueScheduler.storeStatus(status);
            RiseCueScheduler.showStatusNotification("RiseCue", status + ".");
            WatchUi.requestUpdate();
            return;
        }

        if (target == null) {
            RiseCueScheduler.clearPreviewState();
            if (refreshingQueuedAlert && !notifyWhenNoTarget) {
                if (RiseCueScheduler.clearQueuedAlertAndResumeWorkflow()) {
                    RiseCueScheduler.storeStatus(status);
                }
            } else {
                RiseCueScheduler.storeStatus(status);
            }
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

class RiseCueActionMenuDelegate extends WatchUi.ActionMenuDelegate {
    var _delegate;

    function initialize(delegate) {
        ActionMenuDelegate.initialize();
        _delegate = delegate;
    }

    function onSelect(item) {
        var itemId = item.getId();
        if (itemId == RiseCueActionMenu.ACTION_START_SYNC) {
            _delegate.startSync();
        } else if (itemId == RiseCueActionMenu.ACTION_CLEAR_ALERTS) {
            if (RiseCueScheduler.clearQueuedAlertAndResumeWorkflow()) {
                RiseCueScheduler.storeStatus("Wake alert cleared");
            }
            WatchUi.requestUpdate();
        } else {
            RiseCueScheduler.storeStatus("Action menu selection failed");
            WatchUi.requestUpdate();
        }
        _delegate.clearActionMenuDelegate();
    }

    function onBack() {
        _delegate.clearActionMenuDelegate();
    }
}
