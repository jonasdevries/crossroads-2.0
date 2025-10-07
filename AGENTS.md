# Repository Guidelines

## Project Structure & Module Organization
The repo prioritises backend development. Focus work inside `backend/`, which hosts the Node.js entry point (`index.js`), Supabase CLI assets under `supabase/`, and dependencies. Add a `src/` subdirectory for Express route handlers and services as the API expands. Keep integration or contract tests in `backend/tests/` so operational scripts remain separate from application code.

## Build, Test, and Development Commands
- `npx supabase start` — spins up the local Supabase stack (Postgres, Studio, Auth, Storage). Requires Docker.
- `npm run start` — launches the Node.js server for API routes.
- `npm run dev` — hot-reloads the server using `node --watch index.js`.
- `npm test` — reserved for the automated test suite; update the script once testing is configured.

## Coding Style & Naming Conventions
Use two-space indentation across JavaScript. Organise Express routers by domain (`portfolio/positions.routes.js`) and name services or repositories with descriptive camelCase (`portfolioService`, `allocationRepository`). Document non-obvious helpers with concise comments. When adopting formatting or linting (e.g., `prettier --write .`, `eslint --fix`), record the exact commands and pinned versions in `package.json`.

## Testing Guidelines
Automated tests are not yet wired up. Plan to introduce integration tests with Jest or Vitest plus Supertest once the API stabilises. Store specs under `backend/tests/` and name them `resource-name.spec.ts` (or `.js`). Ensure `npm test` runs the suite once configured and document any temporary coverage gaps in PR descriptions.

## Commit & Pull Request Guidelines
Follow Conventional Commits (`feat:`, `fix:`, `chore:`) to make the changelog readable. Keep commits focused and include relevant context in the body when behaviour changes. Pull requests should describe the problem, the solution, manual/automated test evidence, and screenshots for visual tweaks. Link related issues with `Closes #id` so maintenance stays traceable. Request review when the branch is linted, tested, and ready to ship.
