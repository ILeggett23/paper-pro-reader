# Paper Pro RC2 first boot

Complete this before the longer qualification. Record every failure and stop
if the stock UI cannot be restored.

| Step | Action | PASS | Record on FAIL |
| --- | --- | --- | --- |
| 1 | Launch KOReader from AppLoad | Reader/Quickstart appears within 30 seconds | Photo, blank/error screen, elapsed time |
| 2 | Tap the visible Quickstart `next` link once | Quickstart advances from page 1/8 | Exact tap location, whether anything refreshed |
| 3 | Swipe once, then tap another visible control | Both gestures respond normally | Which gesture failed, photo/video |
| 4 | Open a known EPUB | Text renders and touch responds | File name, screen/photo |
| 5 | Turn two pages | Each turn completes without freeze | Missed taps, ghosting, timing |
| 6 | Exit through KOReader menu | Stock reMarkable UI returns | Exact last screen and whether reboot was needed |
| 7 | Relaunch and reopen EPUB | Prior position restores | Actual vs expected position |
| 8 | Select one word and choose Define | Contextual actions and local definition respond | Selection/placement/photo |
| 9 | Add a short Note | Note saves and marker appears | Text, marker, persistence symptom |
| 10 | Enable Ink Mode, draw, then tap a menu control | Marker input and finger touch both operate | Missing segments, touch failure, latency |
| 11 | Undo and redraw | Stroke disappears/reappears correctly | Unexpected persistence/refresh |
| 12 | Ask one typed and one written AI question | Each produces one completed answer | Backend error, recognition, elapsed time |

After step 12, exit and relaunch once more. The reading position, note, ink,
and AI history should remain. Then proceed to `PAPER_PRO_AB_TESTS.md`.
