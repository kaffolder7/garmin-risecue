using Toybox.Communications;

(:background)
module RiseCueWorkflow {
    function buildCalendarParams() {
        var params = {
            "windowStart" => RiseCueConfig.getMorningStart(),
            "windowEnd" => RiseCueConfig.getMorningEnd()
        };
        var timeZone = RiseCueConfig.getTimeZone();
        if (timeZone != null && !timeZone.equals("")) {
            params["timeZone"] = timeZone;
        }

        return params;
    }

    function buildCalendarHeaders(endpoint) {
        var headers = {
            "Accept" => "application/json"
        };
        var calendarIcsUrl = RiseCueConfig.getCalendarIcsUrl();
        if (calendarIcsUrl != null && !calendarIcsUrl.equals("")) {
            headers["X-RiseCue-Calendar-Url"] = calendarIcsUrl;
        }

        var endpointToken = RiseCueConfig.getEndpointTokenForEndpoint(endpoint);
        if (endpointToken != null && !endpointToken.equals("")) {
            headers["X-RiseCue-Token"] = endpointToken;
        }

        return headers;
    }

    function buildCalendarOptions(endpoint) {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => buildCalendarHeaders(endpoint),
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    function hasCalendarEvent(response) {
        return response != null && response.get("hasEvent") == true;
    }

    function makeCalendarTarget(response) {
        if (!hasCalendarEvent(response)) {
            return null;
        }

        var eventTargetEpoch = response.get("eventTargetEpochSec");
        if (eventTargetEpoch == null) {
            eventTargetEpoch = response.get("eventStartEpochSec");
        }

        if (eventTargetEpoch == null) {
            return null;
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

        return RiseCueScheduler.makeWakeTarget(eventTitle, eventTargetEpoch, eventStartLocal);
    }

    function mergeStatus(status, extraStatus) {
        if (extraStatus == null) {
            return status;
        }

        var extra = extraStatus.toString();
        if (extra.equals("")) {
            return status;
        }

        return status + "; " + extra;
    }
}
