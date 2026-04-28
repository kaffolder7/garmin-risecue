using Toybox.WatchUi;

class CalendarWakeDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        CalendarWakeScheduler.registerSleepEvent();
        WatchUi.requestUpdate();
        return true;
    }
}

