# Paper Pro Reader agent policy

This repository is an upstream-maintained KOReader derivative. Before changing
source code, read `docs/ARCHITECTURE.md`, `docs/ENGINE_BOUNDARIES.md`, and
`docs/UPSTREAM.md`.

## Mandatory boundaries

- Treat `base/`, document engines/providers, BlitBuffer, framebuffer/QTFB,
  `frontend/ui/uimanager.lua`, pagination, location mapping, and device input
  infrastructure as protected engine code.
- Do not edit an A-class engine file unless a demonstrated requirement cannot
  be met above the engine. Document the reason and add focused regression tests.
- Make the smallest possible change to B-class adapters. Keep hooks generic and
  upstreamable; keep product policy out of adapter files.
- Put new product-owned work under `frontend/apps/paperpro/` unless the boundary
  document identifies a narrower existing extension point.
- Reuse ReaderAnnotation, DocSettings, ReaderDictionary/StarDict, Vocabulary
  Builder, DocumentRegistry, and ReaderView location/coordinate APIs. Do not
  duplicate their storage or rendering responsibilities.
- Never embed permanent AI-provider secrets in device code. Core reading,
  annotation, dictionary, vocabulary, and queued work must remain offline-safe.
- Preserve `COPYING`, existing copyright notices, attribution, submodule URLs,
  and source history.

## Verification

For source changes, run the relevant focused specs plus `./kodev test front`.
For engine or dependency changes, also run `./kodev test base`. Test reflowable
and fixed-layout documents separately, and report emulator, CI, package-build,
and physical-device results as independent gates. Never imply that emulator
behavior proves Paper Pro refresh, color, touch, or Marker behavior.
