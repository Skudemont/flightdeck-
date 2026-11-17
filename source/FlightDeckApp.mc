import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class FlightDeckApp extends Application.AppBase {

    private var _view as FlightDeckView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new FlightDeckView();
        _view = view;
        return [view];
    }

    // Called when the user changes settings in Garmin Connect / Connect IQ app
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
