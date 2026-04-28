using Toybox.Application;
using Toybox.Background;
using Toybox.Notifications;
using Toybox.WatchUi;

(:background)
class CalendarWakeApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        CalendarWakeScheduler.registerWorkflowTriggers();
        registerNotificationMessages();
    }

    function onSettingsChanged() {
        CalendarWakeScheduler.registerWorkflowTriggers();
        WatchUi.requestUpdate();
    }

    function getInitialView() {
        return [ new CalendarWakeView(), new CalendarWakeDelegate() ];
    }

    function getServiceDelegate() {
        return [ new CalendarWakeServiceDelegate() ];
    }

    function onBackgroundData(data) {
        WatchUi.requestUpdate();
    }

    function onNotificationMessage(message as Notifications.NotificationMessage) as Void {
        if (message.type == Notifications.NOTIFICATION_MESSAGE_TYPE_SELECTED) {
            if (message.action == CalendarWakeConfig.ACTION_SNOOZE) {
                if (CalendarWakeScheduler.scheduleSnooze()) {
                    CalendarWakeScheduler.showStatusNotification("Snoozed", "Wake alert moved by " + CalendarWakeConfig.getSnoozeMinutes() + " minutes.");
                }
            } else if (message.action == CalendarWakeConfig.ACTION_DISMISS) {
                CalendarWakeScheduler.deletePendingAlert();
                CalendarWakeScheduler.registerWorkflowTriggers();
                CalendarWakeScheduler.storeStatus("Wake alert dismissed");
            }
        }

        WatchUi.requestUpdate();
    }

    function registerNotificationMessages() {
        if (Notifications has :registerForNotificationMessages) {
            try {
                Notifications.registerForNotificationMessages(method(:onNotificationMessage));
            } catch (ex) {
                CalendarWakeScheduler.storeStatus("Could not register notification actions");
            }
        }
    }
}
