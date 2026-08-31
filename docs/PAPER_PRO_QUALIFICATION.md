# Paper Pro Reader qualification matrix

RC: `0.6.0-rc4`. RC1–RC3 evidence is retained; RC4 has no physical PASS result.
Update it only from the user's returned physical report.

| Area | Automated/CI | Emulator/runtime | Physical Paper Pro |
| --- | --- | --- | --- |
| Package architecture/contents | AUTOMATED RC CI ONLY | NOT APPLICABLE | NOT TESTED |
| Installation via AppLoad | source-verified | NOT APPLICABLE | RC1–RC3 PASS |
| Launch / exit to stock UI | package scripts inspected | macOS runtime only | RC2 and RC3 PASS |
| Quickstart render/refresh | PASS | PASS | RC2 and RC3 PASS |
| Finger tap/swipe/link routing | RC4 regression | simulated UIManager stack | RC2 PASS; RC3 REGRESSED under refresh load |
| EPUB open/render/navigation | PASS | PASS | RC2 PASS; RC3 page-turn responsiveness REGRESSED |
| PDF open/render/navigation | PASS | PASS | NOT TESTED |
| Position restore | PASS | PASS | RC2 PASS |
| Selection/highlight/bookmark | PASS | PASS | RC2 selection PASS; highlight/bookmark NOT TESTED |
| StarDict/Define | PASS | PASS | INCONCLUSIVE — local dictionary not verified |
| Vocabulary/Notes | PASS | PASS | RC2 note create/persistence PASS; vocabulary NOT TESTED |
| Marker capture | mocked PASS | emulator fixture PASS | RC2 PASS |
| Live active-stroke rendering | RC4 coalescing regression | framebuffer simulation only | RC3 slow line PASS; normal-speed FAIL/HIGH latency |
| Pressure field | automated PASS | mocked only | NOT TESTED |
| Eraser/Undo/Redo | PASS | mocked PASS | RC3 undo PASS; eraser FAIL visually; persistence unchanged |
| Touch + Marker concurrency | RC2 regression | simulated only | RC2 touch and Marker separately PASS; simultaneous NOT TESTED |
| Ink persistence EPUB/PDF | PASS | PASS | RC2 EPUB ink persistence PASS; PDF NOT TESTED |
| Ink over menus/modals | RC4 visibility regression | stack simulation only | RC3 FAIL — contamination/residual ink visible |
| Gallery 3 refresh/ghosting | NOT TESTED | NOT PROVABLE | RC3 SEVERE during live GL16 updates |
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
| Firmware/QTFB compatibility | source-verified assumptions | NOT PROVABLE | OS 3.27.3.0; RC3 GL16 live strategy failed |

Overall physical state: **BLOCKED — RC3 LIVE REFRESH, LAYER CONTAMINATION, AND RESPONSIVENESS FAILURES; RC4 RETEST REQUIRED**.
