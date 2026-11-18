# Flight Deck — Garmin Venu 4 watch face

A flight-deck style digital face in Qatar Airways burgundy with a "Depth" look (shadows, shaded bars, glass dome centre).
For the Venu 4 41 mm (`venu441mm`) and 45 mm (`venu445mm`).

## Layout

| Where | What |
|---|---|
| Top bar | Steps toward your goal, with the count under it. Magenta **pace bug** = where you should be by now (moves 06:00 → 22:00 local). Bar past the bug = ahead. |
| Right bar | Seconds, fills bottom (01) → top (60), number at the middle |
| Bottom bar | Watch battery, % above it (amber ≤ 20 %, red ≤ 10 %) |
| Left bar | Body Battery, fills bottom → top, number at the middle |
| Centre | Date, local time (pearl → burgundy gradient, top to bottom), UTC line |
| Away from Doha | When the watch is on any UTC offset other than +3, the UTC line becomes `UTC 21:38Z  DOH 00:38` |
| Glass panel | Heart rate, plus the EICAS column |

### EICAS column (blank when all normal)
- **Warnings**, red boxed: `BATT LOW` (≤ 10 %), `SPO2 LOW` (latest Pulse Ox < 88 %, last 2 h)
- **Cautions**, amber: `BATT LOW` (≤ 20 %, boxed), `LINK LOST`, `HR HIGH` (10-min average > 100 bpm, outside an activity), `STRESS HIGH` (10-min average ≥ 76)
- **Memos**, white: `COMM` (unread notifications), `CAB 6800` (barometric altitude above 3,000 ft), `CHARGING`, `ALARM SET`, `DND`

Up to three lines, most important first. Thresholds are constants at the top of `source/FlightDeckView.mc`.

### Always-on (AOD)
Dim time + Zulu time (+ Doha time when away) only. It shifts a few pixels every minute and blanks alternate pixel rows (switching each minute), so no pixel stays lit for two minutes in a row. No bars, panel or background, so it stays well inside the AMOLED burn-in limits and uses very little power.

### Settings (Connect IQ app → watch face → Settings)
- **Colour theme:** QR Burgundy (default) or EICAS (white/cyan/green)
- **Show seconds when awake:** on/off (turns off the right bar and number)

### Battery notes
Everything except the seconds bar/number and heart rate is drawn once a minute into an off-screen buffer. Each second, only those small parts are redrawn on top.

## Build

1. Install **VS Code**, the **Monkey C** extension, and the **Connect IQ SDK** (8.x) via the SDK Manager.
2. SDK Manager → Devices: download **Venu 4 41mm** and **Venu 4 45mm**.
3. VS Code → `Monkey C: Generate a Developer Key` (one time).
4. Open this folder → `Monkey C: Run` to try it in the simulator.
   - Simulator → Settings → *Low Power Mode* shows the AOD view.
   - Simulator → Settings → *Time Zone* (or set a different zone) to see the Doha line appear.
5. `Monkey C: Build for Device` → choose `venu445mm` (or `venu441mm`) → you get a `.prg` file.

## Install on the watch (sideload)

- Connect the Venu 4 by USB. It shows up as an MTP device, so on a Mac use **OpenMTP** or Android File Transfer.
- Copy the `.prg` into `GARMIN/APPS/`, disconnect, then pick **Flight Deck** under Watch Faces.
- If it doesn't show as a drive, unlock the watch (PIN) first. You can also upload it to the Connect IQ Store as a private **beta app**.

## Tweaking

All in `source/FlightDeckView.mc`, at the top:
- `HOME_OFFSET_SEC` / `HOME_LABEL`: home base (Doha, +3, `DOH`)
- `PACE_START_MIN` / `PACE_END_MIN`: pace-bug window (06:00–22:00)
- `GLYPH_FRAC`: how much of the font height the gradient spans (adjust if the gradient looks squashed or stretched)
- Bar positions and angles: the `*_START` and `BAR_SPAN` constants
- Colours: the `QR_*` and `C_*` constants
