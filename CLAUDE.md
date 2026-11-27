# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

(Vietnamese version: `CLAUDE.vi.md`. Keep both in sync when editing.)

## Overview

SISO (Step In Step Out) is a gamified running / turf-capture app for HCMC university students, ranked in 4 clusters (Thủ Đức, Central, Bình Thạnh-Phú Nhuận-Gò Vấp, South). Monorepo with two apps: a **Flutter client** (repo root: `lib/`, `test/`, `pubspec.yaml`) and a **NestJS backend** (`backend/`). Docs (Vietnamese) are in `README.md`, `docs/DEVELOPER_HANDBOOK.md` and `docs/SISO_Timeline_v2.md` (task plan by day).

## Commands

Backend (run in `backend/`):
- `npm install`, `npm run start:dev` (watch mode; Swagger at `/docs`, Socket.io at `/turf-ws`), `npm run build`
- `npm test`; single file: `npx jest anti-gigo.service.spec`; single test: `npx jest -t "<test name>"` (jest `rootDir` is `src`, matches `*.spec.ts`)
- `docker-compose up -d` runs Postgres/PostGIS + Redis + API locally (loads `src/database/init_schema.sql` on init)
- `npm run seed:hexagons` prints the H3 res 10 cells per arena from `src/database/arenas.geojson` (dry-run); add `-- --apply` to upsert arenas and insert `h3_hexagons` into the DB in `backend/.env` (idempotent, keeps owners/HP); each feature's `properties.cluster` sets the arena's cluster (default `NORTH`), boundaries come from OpenStreetMap
- `src/database/season_automation.sql` holds the `pg_cron` jobs (season close, 24h/48h decay) in the unexposed `private` schema; run it alone in the Supabase SQL Editor (idempotent), not via `init_schema.sql`

Client (repo root):
- `flutter pub get`, `flutter run -d chrome` (or a device), `flutter test`, `flutter test test/gigo_filter_test.dart`, `flutter analyze`
- Env comes from root `.env` (copy `.env.example`): `API_BASE_URL`, `SOCKET_URL` (Android emulator needs `http://10.0.2.2:3000`, real device needs the LAN IP).

Backend env comes from `backend/.env` (copy `backend/.env.example`): either `DATABASE_URL` or `DB_*` vars, `DB_SSL`, `REDIS_*`, `JWT_SECRET`, optional `GOOGLE_APPLICATION_CREDENTIALS` (Firebase service account file, enables FCM push and Google login), `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (forum image upload; without them posts are text-only, ERR_114) and `TELEMETRY_ALLOW_FAST_REPLAY` (dev only: accept telemetry windows faster than real time, otherwise dropped with ERR_207).

## Architecture

**Server is the single source of truth.** The client only sends raw telemetry (GPS + 50 Hz IMU samples) and H3 boundary indexes. Whether a run is valid (anti-GIGO) and whether land is captured (flood fill) is decided only by the backend. The client never talks to the DB; it uses REST (`ApiClient`, Dio) and WebSocket (`SocketManager`).

Backend (`backend/src/`): feature modules under `modules/` — `auth` (any email + OTP, or Google via Firebase ID token → JWT, `JwtAuthGuard`), `telemetry` (`AntiGigoService`: kinematic checks, then IMU cadence/FFT check to reject motorbikes and mock GPS), `turf` (`H3Service` flood-fills a closed loop into enclosed hexes; `TurfService` claims them), `realtime` (`TurfGateway` broadcasts hex ownership changes), `leaderboard` (parallel % land and % km counters, per cluster via `v_campus_live_scores.cluster_code`), `forum` (posts with up to 4 images in the public Supabase Storage bucket `forum` via `ForumImageStore`, optional attached valid run, likes, flat comments, reports; reads need JWT, writes need `NotBannedGuard`; admin moderation in `admin/forum-moderation.service.ts`), `universities` (`GET /universities` catalog, `PUT /universities/mine` choose/add a university under the per-season lock in `university-lock.ts`), `notifications` (FCM push: hourly patrol reminder to each university's topic `university_<id>`; disabled without `GOOGLE_APPLICATION_CREDENTIALS`; client side is `lib/src/core/push/push_notifier.dart`). TypeORM entities are in `entities/` and must be listed explicitly in `app.module.ts`. `synchronize` is **false**: the schema lives in `src/database/init_schema.sql` (PostGIS, `pg_cron`; run manually in Supabase or via docker init), so entity changes need matching SQL changes.

Cross-cutting: global `ValidationPipe` (whitelist + forbidNonWhitelisted, so every request field needs a DTO decorator) and `AllExceptionsFilter` (`common/filters`). Errors are thrown as `BadRequestException({ code: 'ERR_xxx', message })` using the shared code table (ERR_201 mock GPS, ERR_202 vehicle speed/cadence mismatch, ERR_301 loop over 150 hexes, ERR_106 account banned, ERR_109 no university chosen yet, ERR_110/111 Google login disabled/invalid token, ERR_112 university locked for this season, ERR_113 unknown district, ERR_114 forum image storage off, ERR_115 empty post / too many images, ERR_116 attached run not own+valid, ERR_117 not the author, ERR_306 arena in another cluster; admin-only: ERR_107 not admin, ERR_108 conflicting admin operation; client mirror in `lib/src/core/errors/siso_exceptions.dart`).

Invariants: H3 resolution is 10 everywhere (client and server); a claimed loop may not exceed 150 hexes.

Client (`lib/src/`): feature-first under `features/{auth,map,tracking,leaderboard}`, each split into `data/` (repositories), `domain/` (pure Dart such as `KalmanFilter`, `AccelBuffer`), `presentation/`, `providers/` (Riverpod notifiers). Shared code is in `core/`.

Admin web (`admin/`, Vite + React + TS, shadcn/ui, TanStack Query/Table, Recharts, MapLibre + h3-js): `npm install`, `npm run dev` (port 5173, `VITE_API_BASE_URL` in `admin/.env`, default `http://localhost:3000`), `npm run build`, `npm test` (territory self-check). Backend side is `modules/admin` (`api/v1/admin/*`, every route behind `JwtAuthGuard` + `AdminGuard` via the `@AdminController()` decorator). The JWT carries no role: `AdminGuard` and `NotBannedGuard` (`common/guards/account.guards.ts`) read `users.role` / `users.banned_until` from the DB on each request. Banned students get ERR_106 (and students with no university ERR_109) on `telemetry/verify`, `telemetry/finish` and `turf/claim-loop`; banning also rejects their ACTIVE runs (otherwise `finish_stale_sessions` would credit them). Every admin mutation writes `admin_actions` in the same transaction. Grant admin by SQL (see `admin/README.md`); admins have no university. Login accepts any email (`auth/email-login` + `verify-otp`) or Google (`auth/google`: the app signs in with Firebase Auth and sends the Firebase ID token; `GoogleIdTokenVerifier` checks it with the same service account as FCM, so Google login is off without `GOOGLE_APPLICATION_CREDENTIALS`). Same normalized email = same account. New accounts have no university (`AuthGate` shows `UniversityPickerScreen`, admins skip it); the email-domain trigger `assign_university_id` was dropped. Each `universities` row is one campus; `districts` maps district -> `clusters` (edit the mapping in `init_schema.sql` §6C). Student-added universities have `is_verified = false` (admin can verify / merge / delete). See `docs/adr/0002-xep-hang-theo-cum-va-co-so.md`.

CI: `.github/workflows/build_ios.yml` builds an unsigned iOS IPA (for Sideloadly) on macOS on pushes to `develop`/`main`.

## Notes

- `.claude/skills/` and `.agents/skills/` hold vendored Supabase skills (tracked via `skills-lock.json`); not project code.
- Demo login: any email with OTP `123456` (when `OTP_DEV_MODE` is on).

## Git Rules

- NEVER run git commit, push, merge, rebase, or reset.
- After finishing edits, list the changed files so the user can review and commit them personally.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues (`TienPhuc03/SISO`) via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
