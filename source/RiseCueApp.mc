using Toybox.Application;
using Toybox.Background;
using Toybox.Notifications;
using Toybox.WatchUi;

(:background)
class RiseCueApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        RiseCueScheduler.registerWorkflowTriggers();
        registerNotificationMessages();
    }

    function onSettingsChanged() {
        RiseCueScheduler.clearPreviewState();
        RiseCueScheduler.registerWorkflowTriggers();
        WatchUi.requestUpdate();
    }

    function getInitialView() {
        return [ new RiseCueView(), new RiseCueDelegate() ];
    }

    function getServiceDelegate() {
        return [ new RiseCueServiceDelegate() ];
    }

    function onBackgroundData(data) {
        WatchUi.requestUpdate();
    }

    function onNotificationMessage(message as Notifications.NotificationMessage) as Void {
        if (message.type == Notifications.NOTIFICATION_MESSAGE_TYPE_SELECTED) {
            if (message.action == RiseCueConfig.ACTION_SNOOZE) {
                if (RiseCueScheduler.scheduleSnooze()) {
                    RiseCueScheduler.showStatusNotification("Snoozed", "Wake alert moved by " + RiseCueConfig.getSnoozeMinutes() + " minutes.");
                }
            } else if (message.action == RiseCueConfig.ACTION_DISMISS) {
                RiseCueScheduler.deletePendingAlert();
                RiseCueScheduler.registerWorkflowTriggers();
                RiseCueScheduler.storeStatus("Wake alert dismissed");
            }
        }

        WatchUi.requestUpdate();
    }

    function registerNotificationMessages() {
        if (Notifications has :registerForNotificationMessages) {
            try {
                Notifications.registerForNotificationMessages(method(:onNotificationMessage));
            } catch (ex) {
                RiseCueScheduler.storeStatus("Could not register notification actions");
            }
        }
    }
}
