# Paper Pro Reader qualification matrix

RC: `0.6.0-rc2`. RC1 evidence is retained; RC2 has no physical PASS result.
Update it only from the user's returned physical report.

| Area | Automated/CI | Emulator/runtime | Physical Paper Pro |
| --- | --- | --- | --- |
| Package architecture/contents | AUTOMATED RC CI ONLY | NOT APPLICABLE | NOT TESTED |
| Installation via AppLoad | source-verified | NOT APPLICABLE | RC1 PASS |
| Launch / exit to stock UI | package scripts inspected | macOS runtime only | RC1 launch PASS; stock restored with `/home/root/xovi/stock` |
| Quickstart render/refresh | PASS | PASS | RC1 PASS |
| Finger tap/swipe/link routing | RC2 regression | simulated UIManager stack | RC1 FAIL; RC2 RETEST REQUIRED |
| EPUB open/render/navigation | PASS | PASS | NOT TESTED |
| PDF open/render/navigation | PASS | PASS | NOT TESTED |
| Position restore | PASS | PASS | NOT TESTED |
| Selection/highlight/bookmark | PASS | PASS | NOT TESTED |
| StarDict/Define | PASS | PASS | NOT TESTED |
| Vocabulary/Notes | PASS | PASS | NOT TESTED |
| Marker capture | mocked PASS | emulator fixture PASS | NOT TESTED |
| Pressure field | automated PASS | mocked only | NOT TESTED |
| Eraser/Undo/Redo | PASS | mocked PASS | NOT TESTED |
| Touch + Marker concurrency | RC2 regression | simulated only | BLOCKED BY RC1 TOUCH FAILURE |
| Ink persistence EPUB/PDF | PASS | PASS | NOT TESTED |
| Gallery 3 refresh/ghosting | NOT TESTED | NOT PROVABLE | NOT TESTED |
| Typed AI | mocked backend PASS | localhost PASS | NOT TESTED |
| Handwritten AI | mocked multimodal PASS | localhost PASS | NOT TESTED |
| Offline queue/restart | PASS | PASS | NOT TESTED |
| AI History/conversations | PASS | framebuffer visual | NOT TESTED |
| Full Study | PASS | framebuffer visual | NOT TESTED |
| Sleep/wake | NOT TESTED | NOT PROVABLE | NOT TESTED |
| Device restart/reconnect | storage PASS | simulated | NOT TESTED |
| Upgrade preserving data | archive analysis | NOT APPLICABLE | NOT TESTED |
| Rollback/uninstall | documented | NOT APPLICABLE | NOT TESTED |
| Battery/heat/performance | NOT TESTED | NOT PROVABLE | NOT TESTED |
| Firmware/QTFB compatibility | source-verified assumptions | NOT PROVABLE | OS 3.27.3.0 launch/render PASS; input failed in RC1 product routing |

Overall physical state: **BLOCKED — TOUCH INPUT FAILURE; RC2 RETEST REQUIRED**.
