# Frontend design-engineering rules

Distills Emil Kowalski's design-engineering philosophy (Vercel/Linear, creator of Sonner/Vaul). If the companion Claude Code skills (`emil-design-eng`, `apple-design`, `review-animations`, `find-animation-opportunities`, `improve-animations`, `animation-vocabulary`, `pick-ui-library`, `prototype`) are installed, invoke those directly for a live review, audit, or component pick; this file is the always-loaded checklist version so the core rules apply even without an explicit skill call.

## Should this even animate
- 100+ times/day (keyboard shortcuts, command palette toggle): no animation, ever.
- Tens of times/day (hover effects, list navigation): remove or drastically reduce.
- Occasional (modals, drawers, toasts): standard animation.
- Rare/first-time (onboarding, celebrations): delight is fine.
- Never animate a keyboard-initiated action; it is repeated too often for animation to feel like anything but delay.

## Easing and duration
- Entering/exiting: `ease-out`. On-screen movement: `ease-in-out`. Hover/color change: `ease`. Constant motion (marquee, progress bar): `linear`. Never `ease-in` on a UI element, it delays exactly the moment the user is watching most closely.
- Keep UI animations under 300ms (button press 100-160ms, tooltips/popovers 125-200ms, modals/drawers 200-500ms). Exit should be faster than enter.

## Component defaults
- Never animate from `scale(0)`; start from `scale(0.9-0.95)` plus opacity, nothing in the real world appears from nothing.
- Popovers scale from their trigger (`transform-origin`), not center; modals are the exception and stay centered.
- `:active` gets `scale(0.95-0.98)` for press feedback on every pressable element.
- CSS transitions over keyframes for anything rapidly re-triggered (toasts, toggles); transitions retarget mid-flight, keyframes restart from zero.

## Performance
- Animate only `transform` and `opacity`, they skip layout and paint. Never animate `padding`/`margin`/`width`/`height`.
- Motion's (formerly Framer Motion; `motion/react` import, motion.dev) `x`/`y`/`scale` shorthand is not hardware-accelerated; use the full `transform` string under load.
- Gate hover animations behind `@media (hover: hover) and (pointer: fine)` so a touch tap does not fire a false hover state.

## Accessibility
- `prefers-reduced-motion` means fewer and gentler, not zero: keep opacity/color transitions that aid comprehension, drop movement/position animation.

## Review format
- A UI-code review reports Before/After/Why as a markdown table, one row per issue, never a prose list. This is the actual output contract of the installed `review-animations` skill.

## Sources
- [emilkowalski/skills](https://github.com/emilkowalski/skills)
- [Agents with Taste (Emil Kowalski)](https://emilkowal.ski/ui/agents-with-taste)

Verified: 2026-08-03.
