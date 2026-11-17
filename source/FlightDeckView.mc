import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const HOME_OFFSET_SEC = 10800;      // Doha, UTC+3, no daylight saving
const HOME_LABEL      = "DOH";
const PACE_START_MIN  = 360;        // pace bug runs 06:00 ...
const PACE_END_MIN    = 1320;       // ... to 22:00 local
const GLYPH_FRAC      = 0.70;       // share of font height covered by digits (gradient span)

// Bars: 70 degrees each, 20 degree gaps. 0 deg = 3 o'clock, counter-clockwise positive.
const BAR_SPAN     = 70;
const TOP_START    = 125;   // steps, fills left -> right (clockwise)
const RIGHT_START  = 325;   // seconds, fills bottom -> top (counter-clockwise)
const BOTTOM_START = 235;   // battery, fills left -> right (counter-clockwise)
const LEFT_START   = 215;   // body battery, fills bottom -> top (clockwise)

// ---------------------------------------------------------------------------
// Colours
// ---------------------------------------------------------------------------
const C_WHITE   = 0xFFFFFF;
const C_CYAN    = 0x00E5FF;
const C_GREEN   = 0x3DFF6E;
const C_AMBER   = 0xFFB000;
const C_RED     = 0xFF3B30;
const C_MAGENTA = 0xFF40FF;

// Qatar Airways burgundy (#5C0632, PMS 7421 C) and lifted tints for AMOLED
const QR_BURGUNDY = 0x5C0632;
const QR_DEEP     = 0x7A0C40;
const QR_RASP     = 0xA3195B;
const QR_ROSE     = 0xD4588C;
const QR_BLUSH    = 0xF2A9C6;
const QR_PEARL    = 0xF7E4EC;

// Depth shading
const C_SHADOW      = 0x060003;
const C_SHADOW_SOFT = 0x14030B;
const C_TRACK_INNER = 0x080205;
const C_TUBE_HI     = 0xFFDCEB;
const C_TUBE_LO     = 0x280012;
const C_PANEL       = 0x1C1218;
const C_PANEL_EDGE  = 0x5A3246;
const C_PANEL_HI    = 0x965A73;
const C_SEPARATOR   = 0x46283A;

const THEME_QR    = 0;
const THEME_EICAS = 1;

// ---------------------------------------------------------------------------
// Flight Deck watch face ("Depth" style)
//
//   Top bar     steps toward goal, magenta pace bug
//   Right bar   seconds (bottom -> top), number at the middle
//   Bottom bar  watch battery, % above it
//   Left bar    Body Battery (bottom -> top), number at the middle
//   Centre      date, local time, UTC line (+ Doha time when away from UTC+3)
//   Panel       heart rate | EICAS messages (warnings, cautions, advisories, memos)
//
// Everything except the seconds bar/number and heart rate is drawn into an
// off-screen bitmap once a minute; each second only the dynamic parts are
// drawn on top of it.
// ---------------------------------------------------------------------------
class FlightDeckView extends WatchUi.WatchFace {

    private var _w as Number = 0;
    private var _h as Number = 0;
    private var _cx as Number = 0;
    private var _cy as Number = 0;
    private var _s as Float = 1.0;          // scale relative to a 454 px screen
    private var _pen as Number = 10;        // bar thickness
    private var _r as Number = 0;           // bar centre-line radius

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _showSeconds as Boolean = true;

    private var _cache as Graphics.BufferedBitmapReference? = null;
    private var _cacheFailed as Boolean = false;
    private var _cacheMinute as Number = -1;
    private var _cacheDirty as Boolean = true;

    // ---- Theme colours (set in applyTheme) ----
    private var _timeGrad as Array<Number> = [C_WHITE];
    private var _smallGrad as Array<Number> = [C_CYAN];
    private var _stepsGrad as Array<Number> = [C_GREEN];
    private var _secGrad as Array<Number> = [C_CYAN];
    private var _batGrad as Array<Number> = [C_WHITE];
    private var _bbGrad as Array<Number> = [C_CYAN];
    private var _accent as Number = C_CYAN;
    private var _dateColor as Number = C_WHITE;
    private var _valueColor as Number = C_WHITE;
    private var _stepsColor as Number = C_GREEN;
    private var _bbColor as Number = C_CYAN;
    private var _labelColor as Number = 0x7A7A7A;
    private var _trackColor as Number = 0x1A1A1A;
    private var _vignette as Number = 0x0A1418;
    private var _aodColor as Number = 0x9A9A9A;
    private var _aodDimColor as Number = 0x3F7F88;

    private var _days as Array<String> = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    private var _months as Array<String> = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                                            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

    function initialize() {
        WatchFace.initialize();
        var ds = System.getDeviceSettings();
        if (ds has :requiresBurnInProtection) {
            _burnIn = ds.requiresBurnInProtection;
        }
        loadSettings();
    }

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
        _s = _w / 454.0;
        _pen = (10 * _s).toNumber();
        if (_pen < 6) {
            _pen = 6;
        }
        _r = _cx - _pen / 2 - (5 * _s).toNumber();
        _cache = null;
        _cacheFailed = false;
        _cacheDirty = true;
    }

    // -----------------------------------------------------------------------
    // Settings & themes
    // -----------------------------------------------------------------------
    function loadSettings() as Void {
        var theme = THEME_QR;
        var v = getProp("Theme");
        if (v instanceof Number) {
            theme = v;
        }
        applyTheme(theme);

        var sec = getProp("ShowSeconds");
        _showSeconds = (sec instanceof Boolean) ? sec : true;
        _cacheDirty = true;
    }

    private function applyTheme(theme as Number) as Void {
        if (theme == THEME_EICAS) {
            _timeGrad    = [C_WHITE];
            _smallGrad   = [C_CYAN];
            _stepsGrad   = [C_GREEN];
            _secGrad     = [C_CYAN];
            _batGrad     = [C_WHITE];
            _bbGrad      = [C_CYAN];
            _accent      = C_CYAN;
            _dateColor   = C_WHITE;
            _valueColor  = C_WHITE;
            _stepsColor  = C_GREEN;
            _bbColor     = C_CYAN;
            _labelColor  = 0x7A7A7A;
            _trackColor  = 0x1A1A1A;
            _vignette    = 0x0A1418;
            _aodColor    = 0x9A9A9A;
            _aodDimColor = 0x3F7F88;
        } else {
            // QR Burgundy: pearl at the top fading to burgundy at the bottom
            _timeGrad    = [QR_PEARL, QR_ROSE, QR_RASP];
            _smallGrad   = [QR_PEARL, QR_BLUSH, QR_ROSE];
            // Bars run from deep burgundy at their start to blush at full
            _stepsGrad   = [QR_DEEP, QR_RASP, QR_ROSE, QR_BLUSH];
            _secGrad     = _stepsGrad;
            _batGrad     = _stepsGrad;
            _bbGrad      = _stepsGrad;
            _accent      = QR_ROSE;
            _dateColor   = QR_PEARL;
            _valueColor  = QR_PEARL;
            _stepsColor  = QR_BLUSH;
            _bbColor     = QR_BLUSH;
            _labelColor  = 0x8C7380;
            _trackColor  = 0x18060E;
            _vignette    = 0x2E081A;
            _aodColor    = 0x8F6A7B;
            _aodDimColor = 0x6B2D4C;
        }
    }

    private function getProp(key as String) {
        try {
            return Application.Properties.getValue(key);
        } catch (e) {
            return null;
        }
    }

    // -----------------------------------------------------------------------
    // Sleep / wake (AMOLED always-on handling)
    // -----------------------------------------------------------------------
    function onExitSleep() as Void {
        _awake = true;
        _cacheDirty = true;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    // -----------------------------------------------------------------------
    // Main update
    // -----------------------------------------------------------------------
    function onUpdate(dc as Dc) as Void {
        if (_w == 0) {
            onLayout(dc);
        }
        var clock = System.getClockTime();
        dc.clearClip();

        if (!_awake && _burnIn) {
            antiAlias(dc);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            drawAlwaysOn(dc, clock);
            return;
        }

        // Static layer: rebuilt once a minute (or when something changed)
        var cacheDc = getCacheDc();
        var cache = _cache;
        if (cacheDc != null && cache != null) {
            if (_cacheDirty || clock.min != _cacheMinute) {
                drawStatic(cacheDc, clock);
                _cacheMinute = clock.min;
                _cacheDirty = false;
            }
            dc.drawBitmap(0, 0, cache);
        } else {
            drawStatic(dc, clock);
        }

        antiAlias(dc);
        drawDynamic(dc, clock);
    }

    private function getCacheDc() as Dc? {
        if (_cache == null && !_cacheFailed) {
            if (Graphics has :createBufferedBitmap) {
                try {
                    _cache = Graphics.createBufferedBitmap({:width => _w, :height => _h});
                } catch (e) {
                    _cache = null;
                }
            }
            if (_cache == null) {
                _cacheFailed = true;   // fall back to drawing everything every time
            }
            _cacheDirty = true;
        }
        var ref = _cache;
        if (ref == null) {
            return null;
        }
        var bmp = ref.get();
        if (bmp == null) {
            // graphics pool reclaimed the bitmap: recreate on the next update
            _cache = null;
            return null;
        }
        return (bmp as Graphics.BufferedBitmap).getDc();
    }

    // -----------------------------------------------------------------------
    // Static layer (once a minute)
    // -----------------------------------------------------------------------
    private function drawStatic(dc as Dc, clock as System.ClockTime) as Void {
        antiAlias(dc);
        dc.clearClip();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        drawVignette(dc);

        var ds = System.getDeviceSettings();
        var stats = System.getSystemStats();
        var am = ActivityMonitor.getInfo();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // ---- Bar tracks ----------------------------------------------------
        drawTrack(dc, TOP_START, true);
        drawTrack(dc, RIGHT_START, false);
        drawTrack(dc, BOTTOM_START, false);
        drawTrack(dc, LEFT_START, true);

        // ---- Top: steps + pace bug -----------------------------------------
        var steps = am.steps;
        var goal = am.stepGoal;
        var stepFrac = 0.0;
        if (steps != null && goal != null && goal > 0) {
            stepFrac = steps.toFloat() / goal;
        }
        drawFill(dc, TOP_START, true, stepFrac, _stepsGrad);
        drawPaceBug(dc, paceFraction(clock));
        shadowText(dc, _cx, _h * 0.105, Graphics.FONT_TINY,
                   steps == null ? "--" : steps.toString(), _stepsColor, center);

        // ---- Bottom: battery -----------------------------------------------
        var battery = stats.battery;
        var batGrad = _batGrad;
        var batColor = _valueColor;
        if (battery <= 10.0) {
            batGrad = [C_RED];
            batColor = C_RED;
        } else if (battery <= 20.0) {
            batGrad = [C_AMBER];
            batColor = C_AMBER;
        }
        drawFill(dc, BOTTOM_START, false, battery / 100.0, batGrad);
        shadowText(dc, _cx, _h * 0.885, Graphics.FONT_TINY,
                   battery.toNumber().toString() + "%", batColor, center);

        // ---- Left: Body Battery --------------------------------------------
        var bb = readBodyBattery();
        var bbFrac = 0.0;
        if (bb != null) {
            bbFrac = bb / 100.0;
        }
        drawFill(dc, LEFT_START, true, bbFrac, _bbGrad);
        var inner = _cx - _pen - (5 * _s).toNumber();
        var sideX = inner - (9 * _s).toNumber();
        shadowText(dc, _cx - sideX, _cy, Graphics.FONT_TINY,
                   bb == null ? "--" : bb.toString(), _bbColor,
                   Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // ---- Date ------------------------------------------------------------
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dateStr = _days[(now.day_of_week as Number) - 1] + " "
                    + now.day.toString() + " "
                    + _months[(now.month as Number) - 1];
        shadowText(dc, _cx, _h * 0.205, Graphics.FONT_SMALL, dateStr, _dateColor, center);

        // ---- Local time --------------------------------------------------------
        drawTime(dc, clock, ds.is24Hour);

        // ---- UTC (+ Doha when away) -------------------------------------------
        drawZoneLine(dc, clock);

        // ---- Glass panel: HR label | EICAS ------------------------------------
        drawPanel(dc);
        var hx = _cx - (_w * 0.15).toNumber();
        dc.setColor(_labelColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(hx, _h * 0.70, Graphics.FONT_XTINY, "HR", center);
        drawEicas(dc, ds, am, battery);
    }

    // -----------------------------------------------------------------------
    // Dynamic layer (every second while awake)
    // -----------------------------------------------------------------------
    private function drawDynamic(dc as Dc, clock as System.ClockTime) as Void {
        if (_showSeconds && _awake) {
            drawFill(dc, RIGHT_START, false, clock.sec / 60.0, _secGrad);
            var inner = _cx - _pen - (5 * _s).toNumber();
            var sideX = inner - (9 * _s).toNumber();
            shadowText(dc, _cx + sideX, _cy, Graphics.FONT_TINY, clock.sec.format("%02d"), _accent,
                       Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var hr = getHeartRate();
        var hx = _cx - (_w * 0.15).toNumber();
        shadowText(dc, hx, _h * 0.77, Graphics.FONT_SMALL, hr == null ? "--" : hr.toString(),
                   _valueColor, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // -----------------------------------------------------------------------
    // Sections
    // -----------------------------------------------------------------------
    private function drawTime(dc as Dc, clock as System.ClockTime, is24 as Boolean) as Void {
        var timeStr = formatTime(clock, is24);
        var timeY = (_h * 0.40).toNumber();

        // Largest number font that clears the side numbers and the date/UTC lines
        var font = Graphics.FONT_NUMBER_THAI_HOT;
        var sideW = dc.getTextWidthInPixels("88", Graphics.FONT_TINY);
        var limit = _cx - (_pen + (20 * _s).toNumber() + sideW + (6 * _s).toNumber());
        if (dc.getFontHeight(font) > _h * 0.36
            || dc.getTextWidthInPixels(timeStr, font) / 2 > limit) {
            font = Graphics.FONT_NUMBER_HOT;
        }

        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var o = (2 * _s).toNumber();
        if (o < 1) {
            o = 1;
        }

        // Soft drop shadow: two passes, far and light then near and dark
        dc.setColor(C_SHADOW_SOFT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + o * 2, timeY + o * 3, font, timeStr, just);
        dc.setColor(C_SHADOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + o, timeY + o * 2, font, timeStr, just);

        // Bevel: a pale copy nudged up leaves a thin highlight on top edges
        dc.setColor(0xE8CCD8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, timeY - o, font, timeStr, just);

        // Top -> bottom gradient digits
        gradientTextV(dc, _cx, timeY, font, timeStr, _timeGrad, 32);

        // AM/PM marker for 12 h mode, at the top right of the digits
        if (!is24) {
            var tw = dc.getTextWidthInPixels(timeStr, font);
            var th = dc.getFontHeight(font);
            dc.setColor(_labelColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx + tw / 2 + (4 * _s).toNumber(), timeY - (th * 0.22).toNumber(),
                        Graphics.FONT_XTINY, clock.hour < 12 ? "AM" : "PM",
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // "UTC 21:38Z" at home; "UTC 21:38Z   DOH 00:38" when the watch is on
    // any other UTC offset.
    private function drawZoneLine(dc as Dc, clock as System.ClockTime) as Void {
        var away = clock.timeZoneOffset != HOME_OFFSET_SEC;
        var lblFont = Graphics.FONT_XTINY;
        var valFont = Graphics.FONT_MEDIUM;
        var gap = (7 * _s).toNumber();
        var pairGap = (22 * _s).toNumber();
        var y = (_h * 0.60).toNumber();

        var labels = ["UTC"];
        var values = [utcString()];
        if (away) {
            labels.add(HOME_LABEL);
            values.add(homeString());
        }

        var total = measurePairs(dc, labels, values, lblFont, valFont, gap, pairGap);
        if (total > _w * 0.80) {
            valFont = Graphics.FONT_SMALL;
            total = measurePairs(dc, labels, values, lblFont, valFont, gap, pairGap);
        }

        var x = _cx - total / 2;
        var leftV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var sx = (1.5 * _s).toNumber();
        var sy = (3 * _s).toNumber();
        for (var i = 0; i < labels.size(); i++) {
            var lw = dc.getTextWidthInPixels(labels[i], lblFont);
            var vw = dc.getTextWidthInPixels(values[i], valFont);
            dc.setColor(_labelColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, lblFont, labels[i], leftV);

            var vx = x + lw + gap + vw / 2;
            dc.setColor(C_SHADOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(vx + sx, y + sy, valFont, values[i],
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            gradientTextV(dc, vx, y, valFont, values[i], _smallGrad, 12);
            x += lw + gap + vw + pairGap;
        }
    }

    private function measurePairs(dc as Dc, labels as Array<String>, values as Array<String>,
                                  lblFont as Graphics.FontDefinition, valFont as Graphics.FontDefinition,
                                  gap as Number, pairGap as Number) as Number {
        var total = 0;
        for (var i = 0; i < labels.size(); i++) {
            total += dc.getTextWidthInPixels(labels[i], lblFont) + gap
                   + dc.getTextWidthInPixels(values[i], valFont);
        }
        return total + pairGap * (labels.size() - 1);
    }

    private function drawPanel(dc as Dc) as Void {
        var x = (_w * 0.22).toNumber();
        var y = (_h * 0.655).toNumber();
        var pw = (_w * 0.56).toNumber();
        var ph = (_h * 0.18).toNumber();
        var rad = (14 * _s).toNumber();

        // shadow below, then frosted fill, edge and top highlight
        dc.setColor(C_SHADOW, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y + (4 * _s).toNumber(), pw, ph, rad);
        dc.setColor(C_PANEL, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, pw, ph, rad);
        dc.setPenWidth(1);
        dc.setColor(C_PANEL_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, pw, ph, rad);
        dc.setColor(C_PANEL_HI, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x + rad, y, x + pw - rad, y);

        // separator between HR and the EICAS column
        var sep = _cx - (_w * 0.05).toNumber();
        dc.setColor(C_SEPARATOR, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(sep, (_h * 0.675).toNumber(), sep, (_h * 0.815).toNumber());
    }

    // EICAS column: warnings (red), cautions (amber), advisories (amber,
    // indented), memos (white). Blank when everything is normal.
    private function drawEicas(dc as Dc, ds as System.DeviceSettings,
                               am as ActivityMonitor.Info, battery as Float) as Void {
        var texts = [] as Array<String>;
        var colors = [] as Array<Number>;
        var boxed = [] as Array<Boolean>;
        var indent = [] as Array<Boolean>;

        // Warnings
        if (battery <= 10.0) {
            addMsg(texts, colors, boxed, indent, "BATT LOW", C_RED, true, false);
        }
        // Cautions
        if (battery > 10.0 && battery <= 20.0) {
            addMsg(texts, colors, boxed, indent, "BATT LOW", C_AMBER, true, false);
        }
        if (!ds.phoneConnected) {
            addMsg(texts, colors, boxed, indent, "LINK LOST", C_AMBER, false, false);
        }
        // Advisories
        var move = am.moveBarLevel;
        if (move != null && move > ActivityMonitor.MOVE_BAR_LEVEL_MIN) {
            addMsg(texts, colors, boxed, indent, "MOVE", C_AMBER, false, true);
        }
        // Memos
        var n = ds.notificationCount;
        if (n > 0) {
            addMsg(texts, colors, boxed, indent, n == 1 ? "1 MESSAGE" : n.toString() + " MESSAGES",
                   C_WHITE, false, false);
        }
        if (ds.alarmCount > 0) {
            addMsg(texts, colors, boxed, indent, "ALARM SET", C_WHITE, false, false);
        }
        if ((ds has :doNotDisturb) && ds.doNotDisturb) {
            addMsg(texts, colors, boxed, indent, "DND", C_WHITE, false, false);
        }

        var count = texts.size();
        if (count == 0) {
            return;
        }
        if (count > 3) {
            count = 3;
        }

        var font = Graphics.FONT_XTINY;
        var fh = dc.getFontHeight(font);
        var lineH = (fh * 0.92).toNumber();
        var panelMid = (_h * 0.745).toNumber();
        var y0 = panelMid - (lineH * (count - 1)) / 2;
        var x0 = _cx - (_w * 0.05).toNumber() + (10 * _s).toNumber();
        var leftV = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        for (var i = 0; i < count; i++) {
            var x = indent[i] ? x0 + (12 * _s).toNumber() : x0;
            var y = y0 + i * lineH;
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, texts[i], leftV);
            if (boxed[i]) {
                var tw = dc.getTextWidthInPixels(texts[i], font);
                var bh = (fh * 0.78).toNumber();
                var p = (3 * _s).toNumber();
                dc.setPenWidth(2);
                dc.drawRectangle(x - p, y - bh / 2, tw + 2 * p, bh);
                dc.setPenWidth(1);
            }
        }
    }

    private function addMsg(texts as Array<String>, colors as Array<Number>, boxed as Array<Boolean>,
                            indent as Array<Boolean>, text as String, color as Number,
                            isBoxed as Boolean, isIndented as Boolean) as Void {
        texts.add(text);
        colors.add(color);
        boxed.add(isBoxed);
        indent.add(isIndented);
    }

    // Always-on (low power) mode for AMOLED:
    //  - small, dim time + UTC (+ Doha when away) only
    //  - whole block shifts a few pixels every minute
    //  - every other pixel row is blacked out, alternating each minute, so
    //    no pixel is ever lit for two consecutive minutes
    private function drawAlwaysOn(dc as Dc, clock as System.ClockTime) as Void {
        var ds = System.getDeviceSettings();
        var timeStr = formatTime(clock, ds.is24Hour);
        var zStr = utcString();
        if (clock.timeZoneOffset != HOME_OFFSET_SEC) {
            zStr = zStr + "  " + HOME_LABEL + " " + homeString();
        }

        var step = (4 * _s).toNumber();
        if (step < 3) {
            step = 3;
        }
        var dx = ((clock.min % 5) - 2) * step;
        var dy = (((clock.min / 5) % 5) - 2) * step;

        var font = Graphics.FONT_NUMBER_MEDIUM;
        var th = dc.getFontHeight(font);
        var timeY = (_h * 0.45).toNumber() + dy;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(_aodColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + dx, timeY, font, timeStr, center);

        var zFont = Graphics.FONT_TINY;
        var zh = dc.getFontHeight(zFont);
        var zY = timeY + th / 2 + zh / 2;
        dc.setColor(_aodDimColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + dx, zY, zFont, zStr, center);

        // Scan-line mask
        var top = timeY - th / 2;
        if (top < 0) {
            top = 0;
        }
        var bottom = zY + zh / 2;
        if (bottom >= _h) {
            bottom = _h - 1;
        }
        var parity = clock.min % 2;
        var start = ((top % 2) == parity) ? top : top + 1;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        for (var y = start; y <= bottom; y += 2) {
            dc.fillRectangle(0, y, _w, 1);
        }
    }

    // -----------------------------------------------------------------------
    // Bars
    // -----------------------------------------------------------------------
    private function drawTrack(dc as Dc, startDeg as Number, clockwise as Boolean) as Void {
        var sign = clockwise ? -1 : 1;
        var dir = clockwise ? Graphics.ARC_CLOCKWISE : Graphics.ARC_COUNTER_CLOCKWISE;
        var endDeg = startDeg + sign * BAR_SPAN;

        dc.setPenWidth(_pen);
        dc.setColor(_trackColor, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(_cx, _cy, _r, dir, normDeg(startDeg), normDeg(endDeg));
        capAt(dc, startDeg, _trackColor);
        capAt(dc, endDeg, _trackColor);

        // inset look: dark line along the inner edge of the groove
        dc.setPenWidth(2);
        dc.setColor(C_TRACK_INNER, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(_cx, _cy, _r - _pen / 2 + 1, dir, normDeg(startDeg), normDeg(endDeg));
        dc.setPenWidth(1);
    }

    // Filled part of a bar: gradient along the bar, rounded ends, tube shading.
    private function drawFill(dc as Dc, startDeg as Number, clockwise as Boolean,
                              frac as Float, stops as Array<Number>) as Void {
        if (frac > 1.0) {
            frac = 1.0;
        }
        var fill = (BAR_SPAN * frac).toNumber();
        if (fill < 1) {     // never pass start == end: drawArc would draw a full circle
            return;
        }
        var sign = clockwise ? -1 : 1;
        var dir = clockwise ? Graphics.ARC_CLOCKWISE : Graphics.ARC_COUNTER_CLOCKWISE;
        var endDeg = startDeg + sign * fill;

        dc.setPenWidth(_pen);
        if (stops.size() == 1) {
            dc.setColor(stops[0], Graphics.COLOR_TRANSPARENT);
            dc.drawArc(_cx, _cy, _r, dir, normDeg(startDeg), normDeg(endDeg));
        } else {
            // 4-degree segments overlapping by 1 degree to avoid seams
            for (var k = 0; k < fill; k += 3) {
                var kEnd = k + 4;
                if (kEnd > fill) {
                    kEnd = fill;
                }
                dc.setColor(gradColor(stops, k.toFloat() / BAR_SPAN), Graphics.COLOR_TRANSPARENT);
                dc.drawArc(_cx, _cy, _r, dir,
                           normDeg(startDeg + sign * k), normDeg(startDeg + sign * kEnd));
            }
        }
        capAt(dc, startDeg, gradColor(stops, 0.0));
        capAt(dc, endDeg, gradColor(stops, fill.toFloat() / BAR_SPAN));

        // tube shading: highlight on the outer edge, shade on the inner edge
        dc.setPenWidth(2);
        dc.setColor(C_TUBE_HI, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(_cx, _cy, _r + _pen / 2 - 2, dir, normDeg(startDeg), normDeg(endDeg));
        dc.setColor(C_TUBE_LO, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(_cx, _cy, _r - _pen / 2 + 2, dir, normDeg(startDeg), normDeg(endDeg));
        dc.setPenWidth(1);
    }

    private function capAt(dc as Dc, deg as Number, color as Number) as Void {
        var a = Math.toRadians(deg);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx + _r * Math.cos(a), _cy - _r * Math.sin(a), _pen / 2);
    }

    // Magenta bug pointing at the steps bar: where you should be by now.
    private function drawPaceBug(dc as Dc, frac as Float) as Void {
        var a = Math.toRadians(TOP_START - BAR_SPAN * frac);
        var ux = Math.cos(a);
        var uy = -Math.sin(a);
        var tx = -uy;
        var ty = ux;
        var tipR = _r - _pen / 2 - 1;
        var baseR = tipR - 13 * _s;
        var hw = 8 * _s;

        dc.setColor(C_MAGENTA, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [_cx + ux * tipR, _cy + uy * tipR],
            [_cx + ux * baseR + tx * hw, _cy + uy * baseR + ty * hw],
            [_cx + ux * baseR - tx * hw, _cy + uy * baseR - ty * hw]
        ]);
        var lw = (3 * _s).toNumber();
        if (lw < 2) {
            lw = 2;
        }
        var ro = _r + _pen / 2;
        var ri = _r - _pen / 2;
        dc.setPenWidth(lw);
        dc.drawLine(_cx + ux * ro, _cy + uy * ro, _cx + ux * ri, _cy + uy * ri);
        dc.setPenWidth(1);
    }

    private function paceFraction(clock as System.ClockTime) as Float {
        var m = clock.hour * 60 + clock.min;
        if (m <= PACE_START_MIN) {
            return 0.0;
        }
        if (m >= PACE_END_MIN) {
            return 1.0;
        }
        return (m - PACE_START_MIN).toFloat() / (PACE_END_MIN - PACE_START_MIN);
    }

    // -----------------------------------------------------------------------
    // Text & colour helpers
    // -----------------------------------------------------------------------
    private function shadowText(dc as Dc, x as Numeric, y as Numeric, font as Graphics.FontDefinition,
                                str as String, color as Number, just as Number) as Void {
        var sx = (1.5 * _s).toNumber();
        var sy = (2.5 * _s).toNumber();
        if (sx < 1) {
            sx = 1;
        }
        if (sy < 2) {
            sy = 2;
        }
        dc.setColor(C_SHADOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + sx, y + sy, font, str, just);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, str, just);
    }

    // Centred text with a top-to-bottom gradient, drawn as horizontal clip
    // slices of the same string in successive colours.
    private function gradientTextV(dc as Dc, x as Number, y as Number, font as Graphics.FontDefinition,
                                   str as String, stops as Array<Number>, bands as Number) as Void {
        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        if (stops.size() == 1) {
            dc.setColor(stops[0], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, str, just);
            return;
        }
        var tw = dc.getTextWidthInPixels(str, font);
        var fh = dc.getFontHeight(font);
        var boxTop = y - fh / 2;
        var gh = (fh * GLYPH_FRAC).toNumber();
        var gTop = y - gh / 2;
        var left = x - tw / 2 - 4;
        var width = tw + 8;

        for (var i = 0; i < bands; i++) {
            var y0 = gTop + (gh * i) / bands;
            var y1 = gTop + (gh * (i + 1)) / bands;
            if (i == 0) {
                y0 = boxTop;
            }
            if (i == bands - 1) {
                y1 = boxTop + fh;
            }
            dc.setClip(left, y0, width, y1 - y0);
            dc.setColor(gradColor(stops, i.toFloat() / (bands - 1)), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, str, just);
        }
        dc.clearClip();
    }

    // Concentric discs from black at the edge to a dark tint at the centre.
    private function drawVignette(dc as Dc) as Void {
        var steps = 24;
        for (var i = 0; i < steps; i++) {
            var t = i.toFloat() / steps;
            var rr = (_cx * (1.0 - t)).toNumber();
            if (rr < 1) {
                break;
            }
            var k = Math.pow(t, 1.4).toFloat();
            dc.setColor(lerpColor(0x000000, _vignette, k), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_cx, _cy, rr);
        }
    }

    private function gradColor(stops as Array<Number>, t as Float) as Number {
        var n = stops.size();
        if (n == 1 || t <= 0.0) {
            return stops[0];
        }
        if (t >= 1.0) {
            return stops[n - 1];
        }
        var pos = t * (n - 1);
        var i = pos.toNumber();
        var f = pos - i;
        return lerpColor(stops[i], stops[i + 1], f);
    }

    private function lerpColor(a as Number, b as Number, f as Float) as Number {
        var ar = (a >> 16) & 0xFF;
        var ag = (a >> 8) & 0xFF;
        var ab = a & 0xFF;
        var r = ar + (((b >> 16) & 0xFF) - ar) * f;
        var g = ag + (((b >> 8) & 0xFF) - ag) * f;
        var bl = ab + ((b & 0xFF) - ab) * f;
        return (r.toNumber() << 16) | (g.toNumber() << 8) | bl.toNumber();
    }

    private function antiAlias(dc as Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
    }

    private function normDeg(d as Number) as Number {
        return ((d % 360) + 360) % 360;
    }

    // -----------------------------------------------------------------------
    // Time strings
    // -----------------------------------------------------------------------
    private function formatTime(clock as System.ClockTime, is24 as Boolean) as String {
        var hour = clock.hour;
        var min = clock.min.format("%02d");
        if (is24) {
            return hour.format("%02d") + ":" + min;
        }
        hour = hour % 12;
        if (hour == 0) {
            hour = 12;
        }
        return hour.toString() + ":" + min;
    }

    // Aviation style, e.g. "18:06Z"
    private function utcString() as String {
        var utc = Gregorian.utcInfo(Time.now(), Time.FORMAT_SHORT);
        return (utc.hour as Number).format("%02d") + ":" + (utc.min as Number).format("%02d") + "Z";
    }

    // Home base (Doha) time, e.g. "00:38"
    private function homeString() as String {
        var t = Time.now().add(new Time.Duration(HOME_OFFSET_SEC));
        var h = Gregorian.utcInfo(t, Time.FORMAT_SHORT);
        return (h.hour as Number).format("%02d") + ":" + (h.min as Number).format("%02d");
    }

    // -----------------------------------------------------------------------
    // Sensors
    // -----------------------------------------------------------------------
    private function getHeartRate() as Number? {
        var info = Activity.getActivityInfo();
        if (info != null) {
            var hr = info.currentHeartRate;
            if (hr != null) {
                return hr;
            }
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var iter = ActivityMonitor.getHeartRateHistory(1, true);
            var sample = iter.next();
            if (sample != null) {
                var v = sample.heartRate;
                if (v != null && v != ActivityMonitor.INVALID_HR_SAMPLE) {
                    return v;
                }
            }
        }
        return null;
    }

    // Called from the once-a-minute static layer.
    private function readBodyBattery() as Number? {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var iter = SensorHistory.getBodyBatteryHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
            if (iter != null) {
                var sample = iter.next();
                if (sample != null) {
                    var d = sample.data;
                    if (d != null) {
                        return d.toNumber();
                    }
                }
            }
        }
        return null;
    }
}
