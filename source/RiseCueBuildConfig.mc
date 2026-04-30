(:background)
module RiseCueBuildConfig {
    const APP_BUILD_VERSION = "0.1.0";
    const SHOW_BUILD_VERSION = true;

    (:defaultBuildConfig)
    function getAppBuildVersion() {
        return APP_BUILD_VERSION;
    }

    (:defaultBuildConfig)
    function shouldShowBuildVersion() {
        return SHOW_BUILD_VERSION;
    }

    (:defaultBuildConfig)
    function getPublicEndpointToken() {
        return "";
    }
}
