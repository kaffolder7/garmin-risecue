using Toybox.WatchUi;

class RiseCueDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        RiseCueScheduler.registerWorkflowTriggers();
        WatchUi.requestUpdate();
        return true;
    }
}
