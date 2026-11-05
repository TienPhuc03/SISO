# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

(Vietnamese version: `CLAUDE.vi.md`. Keep both in sync when editing.)

## Overview

SISO (Step In Step Out) is a gamified running / turf-capture app for students of 5 universities in Binh Thanh, HCMC. Monorepo with two apps: a **Flutter client** (repo root: `lib/`, `test/`, `pubspec.yaml`) and a **NestJS backend** (`backend/`). Docs (Vietnamese) are in `README.md`, `docs/DEVELOPER_HANDBOOK.md` and `docs/SISO_Timeline_v2.md` (task plan by day).

## Commands

Backend (run in `backend/`):
- `npm install`, `npm run start:dev` (watch mode; Swagger at `/docs`, Socket.io at `/turf-ws`), `npm run build`
- `npm test`; single file: `npx jest anti-gigo.service.spec`; single test: `npx jest -t "<test name>"` (jest `rootDir` is `src`, matches `*.spec.ts`)
- `docker-compose up -d` runs Postgres/PostGIS + Redis + API locally (loads `src/database/init_schema.sql` on init)

Client (repo root):
- `flutter pub get`, `flutter run -d chrome` (or a device), `flutter test`, `flutter test test/gigo_filter_test.dart`, `flutter analyze`
- Env comes from root `.env` (copy `.env.example`): `API_BASE_URL`, `SOCKET_URL` (Android emulator needs `http://10.0.2.2:3000`, real device needs the LAN IP).

Backend env comes from `backend/.env` (copy `backend/.env.example`): either `DATABASE_URL` or `DB_*` vars, `DB_SSL`, `REDIS_*`, `JWT_SECRET`.

## Architecture

**Server is the single source of truth.** The client only sends raw telemetry (GPS + 50 Hz IMU samples) and H3 boundary indexes. Whether a run is valid (anti-GIGO) and whether land is captured (flood fill) is decided only by the backend. The client never talks to the DB; it uses REST (`ApiClient`, Dio) and WebSocket (`SocketManager`).

Backend (`backend/src/`): feature modules under `modules/` — `auth` (edu-email + OTP → JWT, `JwtAuthGuard`), `telemetry` (`AntiGigoService`: kinematic checks, then IMU cadence/FFT check to reject motorbikes and mock GPS), `turf` (`H3Service` flood-fills a closed loop into enclosed hexes; `TurfService` claims them), `realtime` (`TurfGateway` broadcasts hex ownership changes), `leaderboard` (parallel % land and % km counters). TypeORM entities are in `entities/` and must be listed explicitly in `app.module.ts`. `synchronize` is **false**: the schema lives in `src/database/init_schema.sql` (PostGIS, `pg_cron`; run manually in Supabase or via docker init), so entity changes need matching SQL changes.

Cross-cutting: global `ValidationPipe` (whitelist + forbidNonWhitelisted, so every request field needs a DTO decorator) and `AllExceptionsFilter` (`common/filters`). Errors are thrown as `BadRequestException({ code: 'ERR_xxx', message })` using the shared code table (ERR_201 mock GPS, ERR_202 vehicle speed/cadence mismatch, ERR_301 loop over 150 hexes; client mirror in `lib/src/core/errors/siso_exceptions.dart`).

Invariants: H3 resolution is 10 everywhere (client and server); a claimed loop may not exceed 150 hexes.

Client (`lib/src/`): feature-first under `features/{auth,map,tracking,leaderboard}`, each split into `data/` (repositories), `domain/` (pure Dart such as `KalmanFilter`, `AccelBuffer`), `presentation/`, `providers/` (Riverpod notifiers). Shared code is in `core/`.

CI: `.github/workflows/build_ios.yml` builds an unsigned iOS IPA (for Sideloadly) on macOS on pushes to `develop`/`main`.

## Notes

- `.claude/skills/` and `.agents/skills/` hold vendored Supabase skills (tracked via `skills-lock.json`); not project code.
- Demo login: any supported edu email with OTP `123456`.

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
