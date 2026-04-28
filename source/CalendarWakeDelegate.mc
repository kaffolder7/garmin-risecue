using Toybox.WatchUi;

class CalendarWakeDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        CalendarWakeScheduler.registerWorkflowTriggers();
        WatchUi.requestUpdate();
        return true;
    }
}
