# Paper Pro RC1 first boot

Complete this before the longer qualification. Record every failure and stop
if the stock UI cannot be restored.

| Step | Action | PASS | Record on FAIL |
| --- | --- | --- | --- |
| 1 | Launch KOReader from AppLoad | Reader/file manager appears within 30 seconds | Photo, blank/error screen, elapsed time |
| 2 | Open a known EPUB | Text renders and touch responds | File name, screen/photo |
| 3 | Turn two pages | Each turn completes without freeze | Missed taps, ghosting, timing |
| 4 | Exit through KOReader menu | Stock reMarkable UI returns | Exact last screen and whether reboot was needed |
| 5 | Relaunch and reopen EPUB | Prior position restores | Actual vs expected position |
| 6 | Select one word | Contextual actions appear near selection | Selection/placement/photo |
| 7 | Choose Define | Local definition appears and dismisses | Dictionary state/error |
| 8 | Add a short Note | Note saves and marker appears | Text, marker, persistence symptom |
| 9 | Enable Ink Mode and draw one line | Marker line follows input; touch still operates | Missing segments, latency, edges |
| 10 | Undo and redraw | Stroke disappears/reappears correctly | Unexpected persistence/refresh |
| 11 | Ask one typed AI question | Static Thinking then one answer | Backend error and elapsed time |
| 12 | Ask “Why does this matter?” in Write mode | Recognition and answer appear | Recognized text, missing strokes, time |

After step 12, exit and relaunch once more. The reading position, note, ink,
and AI history should remain. Then proceed to `PAPER_PRO_AB_TESTS.md`.
