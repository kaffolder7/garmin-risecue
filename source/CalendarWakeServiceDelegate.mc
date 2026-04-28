using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.System;

(:background)
class CalendarWakeServiceDelegate extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onSleepTime() {
        CalendarWakeScheduler.registerSleepEvent();

        if (!CalendarWakeConfig.isEnabled()) {
            CalendarWakeScheduler.storeStatus("Wake alerts disabled");
            Background.exit({ "status" => "disabled" });
            return;
        }

        var endpoint = CalendarWakeConfig.getEndpointUrl();
        if (endpoint == null || endpoint.equals("")) {
            CalendarWakeScheduler.storeStatus("Calendar endpoint is not configured");
            CalendarWakeScheduler.showStatusNotification("Calendar Wake", "Calendar endpoint is not configured.");
            Background.exit({ "status" => "missing_endpoint" });
            return;
        }

        var params = {
            "windowStart" => CalendarWakeConfig.getMorningStart(),
            "windowEnd" => CalendarWakeConfig.getMorningEnd(),
            "timeZone" => CalendarWakeConfig.getTimeZone()
        };

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
            CalendarWakeScheduler.storeStatus("Calendar request failed");
            CalendarWakeScheduler.showStatusNotification("Calendar Wake", "Could not start calendar request.");
            Background.exit({ "status" => "request_start_failed" });
        }
    }

    function onTemporalEvent() {
        CalendarWakeScheduler.showWakeNotification();
        Background.exit({ "status" => "alert_fired" });
    }

    function onCalendarResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void {
        if (responseCode != 200 || data == null) {
            CalendarWakeScheduler.storeStatus("Calendar request returned " + responseCode);
            CalendarWakeScheduler.showStatusNotification("Calendar Wake", "Calendar check failed.");
            Background.exit({ "status" => "request_failed", "responseCode" => responseCode });
            return;
        }

        var response = data as Lang.Dictionary;
        if (response.get("hasEvent") != true) {
            CalendarWakeScheduler.storeStatus("No morning events found");
            Background.exit({ "status" => "no_event" });
            return;
        }

        var eventStartEpoch = response.get("eventStartEpochSec");
        if (eventStartEpoch == null) {
            CalendarWakeScheduler.storeStatus("Calendar response missing event time");
            CalendarWakeScheduler.showStatusNotification("Calendar Wake", "Calendar response missing event time.");
            Background.exit({ "status" => "invalid_response" });
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

        var scheduled = CalendarWakeScheduler.scheduleAlert(eventTitle, eventStartEpoch, eventStartLocal);
        if (!scheduled) {
            CalendarWakeScheduler.showStatusNotification("Calendar Wake", "Could not schedule wake alert.");
            Background.exit({ "status" => "schedule_failed" });
            return;
        }

        Background.exit({ "status" => "scheduled" });
    }
}
