(:background)
module RiseCueBuildConfig {
    const APP_BUILD_VERSION = "0.1.0";

    function getAppBuildVersion() {
        return APP_BUILD_VERSION;
    }

    (:defaultPublicEndpointToken)
    function getPublicEndpointToken() {
        return "";
    }
}
