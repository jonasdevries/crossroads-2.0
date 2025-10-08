# Crossroads 2.0

## Overview
Crossroads 2.0 is a fresh take on my multi-asset portfolio management platform. It rebuilds the original [Crossroads](https://github.com/jonasdevries/crossroads) learnings from scratch while keeping the core focus: tracking positions, analysing diversification, and monitoring personalised strategies across asset classes.

## Project Goals
- Recreate the essential insights from the first Crossroads while modernising the stack.
- Deliver a reliable Supabase-backed API that can serve future UI clients.
- Grow from a simple dashboard into a collaborative workspace for portfolio experiments.

## Project Structure
- `backend/` — Node.js server and Supabase CLI configuration (`supabase/config.toml`) for local development.
- `AGENTS.md` — contributor guide detailing structure, coding style, and workflow expectations.

## Getting Started
1. Clone the repo: `git clone https://github.com/jonasdevries/crossroads-2.0.git && cd crossroads-2.0`.
2. Install backend dependencies: `cd backend && npm install`.
3. Start the Supabase stack: `npx supabase start`.
4. Run the backend server: `npm run start`.

Supabase services are available at `http://127.0.0.1:54321` (API) and `http://127.0.0.1:54323` (Studio) once the stack is up.

## Development Workflow
- Focus on API endpoints and data modelling before introducing a front end.
- Capture schema changes with Supabase migrations in `backend/supabase/migrations/`.
- Mirror successful patterns from the original Crossroads repo while keeping the codebase lean and documented.

## Testing
- Duplicate `backend/.env.test.example` to `backend/.env.test` and adjust credentials if your local Supabase stack differs.
- Start Supabase locally before running tests: `cd backend && npx supabase start`.
- Execute the integration suite with `npm test`. Set `SKIP_DB_TESTS=1` or `SKIP_HTTP_TESTS=1` if you temporarily want to bypass database or network-bound specs.

## Roadmap Snapshot
- Model core portfolio entities (accounts, holdings, transactions) in Supabase.
- Build interactive charts for asset allocation and performance.
- Add authenticated sessions to persist user-specific views and experiments.
