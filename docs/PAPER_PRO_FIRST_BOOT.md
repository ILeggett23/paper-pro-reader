# Paper Pro RC5 exclusive Write Mode retest

Run this focused test before resuming the longer qualification. Do not mark
live ink PASS unless it is visible before pen lift on the physical panel.

| Step | Action | PASS | Record on FAIL |
| --- | --- | --- | --- |
| 1 | Enable Write Mode and rest a palm on the page | No page turn, selection, or highlight | Exact accidental action/video |
| 2 | Write `testing palm rejection` normally | Live ink tracks Marker without per-letter flashing | Latency, gaps, ghosting |
| 3 | Swipe one finger in Write Mode | Page remains locked | Page/action triggered |
| 4 | Tap Navigate, turn a page, and return | Deliberate navigation works | Missed gesture or trapped mode |
| 5 | Return to Write, then Undo | One stroke disappears immediately | Residual/delayed ink |
| 6 | Erase across several strokes | Continuous deletion; one Undo group | Missed strokes or repeated Undo entries |
| 7 | Open Tools and another modal | No ink contamination | Photos |
| 8 | Exit/relaunch | Retained ink persists; undone/erased ink stays absent | Persistence discrepancy |
| 9 | Tap Done and use Read Mode | Normal selection and page turns work | Read Mode regression |

If RC5 passes, continue with `PAPER_PRO_AB_TESTS.md`. Dictionary remains
inconclusive until an English StarDict dictionary is installed and verified.
