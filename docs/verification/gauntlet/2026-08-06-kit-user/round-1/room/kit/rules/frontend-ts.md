---
paths:
  - "**/src/**"
  - "**/app/**"
  - "**/components/**"
  - "**/pages/**"
  - "**/lib/**"
---

TypeScript frontend conventions for this project.

## Style

- Strict TypeScript: no `any`, no `@ts-ignore` without a comment explaining why.
- Prefer `interface` over `type` for object shapes. Use `type` for unions and intersections.
- Named exports over default exports (easier to refactor, better IDE support).
- Destructure props in function signature: `function Button({ label, onClick }: ButtonProps)`

## React (if applicable)

- Functional components only. No class components.
- Custom hooks for shared logic. Prefix with `use`.
- Colocate: component + styles + tests + types in the same directory.
- Avoid prop drilling past 2 levels. Use context or composition instead.

## State management

- Local state first (`useState`). Lift only when a sibling needs it.
- Server state: use react-query/SWR, not Redux, for API data.
- Form state: controlled components with validation at submit time.

## Error handling

- Wrap API calls in try/catch. Show user-facing error messages, not stack traces.
- Use error boundaries for render errors. Don't let a broken component crash the page.
- Log errors with context: `console.error('Failed to fetch user', { userId, error })`.

## Testing

- Test behavior, not implementation. Click the button, check the result.
- Mock API calls, not internal functions.
- Use `data-testid` for test selectors, not CSS classes.
