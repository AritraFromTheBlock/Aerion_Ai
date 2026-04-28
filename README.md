# Aerion AI – Emergency Response Platform 🚨

## Built by **Team Tetraverse**

> **_An intelligent, real‑time emergency response system powered by Flutter, Node.js, and Google Cloud._**

---

## Table of Contents
- [Overview](#-overview)
- [Key Features](#-key-features)
- [System Architecture](#-system-architecture)
- [Technical Approach](#-technical-approach)
- [Tech Stack](#-tech-stack)
- [Getting Started](#-getting-started)
- [Building the APK](#-building-the-apk)
- [Cloud Deployment](#-cloud-deployment)
- [API Reference](#-api-reference)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🛠️ Overview

Aerion AI is a **production‑grade**, AI‑driven emergency response platform designed to drastically reduce incident detection‑to‑response latency in crisis scenarios. The system enables:

- **One‑tap SOS alerts** with real‑time GPS tracking and custom distress messages.
- **AI‑powered incident triage** — every report is classified and summarised by Google Gemini before it reaches a responder.
- **Live incident mapping** with severity‑coded markers, distance‑based scaling, and heatmap overlays.
- **Crowd corroboration** — citizens confirm reported incidents, improving signal reliability and suppressing false positives.
- **Auto‑escalation engine** — critical incidents with no responder assignment are automatically re‑escalated via FCM push notifications every 2 minutes (up to 3 rounds).

---

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 📍 **Real‑Time Map** | Interactive incident map with live markers, distance scaling, and severity colour coding. |
| 🤖 **Gemini AI Triage** | Automatic incident classification, severity assessment, and natural‑language SITREP generation. |
| 🚨 **Panic SOS** | One‑tap emergency button transmitting GPS coordinates, altitude, accuracy, and optional message. |
| 📊 **Analytics Dashboard** | 7‑day trend analysis, hourly volume sparkline, severity breakdown, and average response‑time metrics. |
| 🔗 **Incident Clustering** | Smart 500m deduplication — overlapping reports are merged and corroboration counts aggregated. |
| 🔔 **Auto‑Escalation** | Unattended CRITICAL incidents trigger periodic FCM re‑alerts to all registered responders. |
| 🗂️ **Rescue Dashboard** | Priority‑sorted incident queue with filtering by severity, type, status, and proximity. |
| 🔐 **Security First** | Parameterised SQL, API key gating, Helmet.js headers, CORS lockdown, and safe JSON decoding. |
| 🌐 **WebSocket Feed** | Real‑time push to connected emergency clients via `ws://` for instant incident propagation. |

---

## 🗂️ System Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         FLUTTER MOBILE APP                           │
│  lib/                                                                │
│   ├── screens/          (SOS, Map, Report, Dashboard, Login)         │
│   ├── services/         (ApiService — centralised HTTP + safe decode)│
│   ├── models/           (CrisisAlert, AlertSeverity)                 │
│   ├── widgets/          (CrisisCard, PrimaryButton)                  │
│   └── theme/            (AppTheme — dark‑mode design system)         │
└────────────────────┬─────────────────────────────────────────────────┘
                     │  HTTPS + X‑Api‑Key / JWT Bearer
                     ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    NODE.JS BACKEND (Cloud Run)                        │
│  src/                                                                │
│   ├── routes/                                                        │
│   │    ├── incidents.ts   (report, nearby, corroborate, CRUD)        │
│   │    ├── sos.ts         (quick SOS, update, cancel)                │
│   │    ├── analytics.ts   (heatmap, trends, response performance)    │
│   │    ├── dashboard.ts   (stats, filtered lists, SOS map)           │
│   │    └── auth.ts        (register, profile, FCM token sync)        │
│   ├── middleware/         (JWT verify, role guard, API key check)     │
│   ├── config/             (PostgreSQL pool, Firebase Admin, Gemini)   │
│   └── index.ts            (Express app, WebSocket server, escalation)│
└────────┬──────────────┬──────────────┬───────────────────────────────┘
         │              │              │
         ▼              ▼              ▼
   ┌──────────┐  ┌────────────┐  ┌──────────────┐
   │ Cloud SQL│  │ Firestore  │  │  Gemini AI   │
   │ Postgres │  │ (realtime) │  │  (triage)    │
   └──────────┘  └────────────┘  └──────────────┘
```

All network traffic is encrypted via HTTPS. The backend enforces **parameterised SQL queries** across every route to eliminate injection vectors.

---

## 🔬 Technical Approach

### Service‑Oriented Design
The backend is architected as a collection of **stateless Express route modules** — each responsible for a single domain (incidents, SOS, analytics, dashboard). Business logic is encapsulated in dedicated service files, enabling independent horizontal scaling and clean separation of concerns.

### Intelligent API Layer
All endpoints expose a strict **JSON contract** defined by TypeScript interfaces. Anonymous endpoints are gated by `X‑Api‑Key` headers; authenticated endpoints verify Firebase JWTs with role‑based access control (`normal`, `emergency`). The Flutter client uses a **centralised `_safeJsonDecode()` helper** that gracefully handles HTML error pages, empty responses, and malformed JSON — converting them into structured `ApiException` objects instead of crashing.

### Multi‑Tier Data Architecture
- **PostgreSQL (Cloud SQL)** — Primary relational store for incidents, SOS alerts, users, and incident update timelines.
- **Google Firestore** — Real‑time document store for push notification orchestration and live state sync.
- **In‑Memory WebSocket Registry** — Server‑side `Set<WSClient>` tracks connected responders by room, enabling instant broadcast of new incidents, escalations, and status changes.

### AI‑Powered Triage Pipeline
Every incident report passes through a **Gemini AI classification pipeline** that:
1. Determines `incident_type` (FIRE, FLOOD, MEDICAL, ACCIDENT, STRUCTURAL, CHEMICAL, OTHER).
2. Assigns a `severity` level (LOW, MODERATE, HIGH, CRITICAL).
3. Generates a concise natural‑language **SITREP summary** for responders.
4. Attempts **500m radius clustering** to merge duplicate reports and aggregate corroboration counts.

### Auto‑Escalation Engine
A background interval (every 2 minutes) scans for **CRITICAL incidents** that remain unassigned beyond 3 minutes. These are automatically re‑escalated:
- Escalation count is incremented (capped at 3).
- FCM high‑priority push is re‑sent to all `emergency` role users.
- WebSocket `INCIDENT_ESCALATED` event is broadcast.
- A timeline entry is appended for audit traceability.

### CI/CD & Infrastructure as Code
- **Cloud Build** (`cloudbuild.yaml`) — Builds Docker image → pushes to Artifact Registry → deploys to Cloud Run.
- **Dockerfile** — Multi‑stage Node.js build with production‑only dependencies.
- Service resources (memory, CPU, concurrency, request timeout) are **declaratively specified**, enabling repeatable, reproducible deployments.

### Observability
- **Cloud Logging** — Structured request traces with Morgan middleware.
- **Cloud Monitoring** — Latency, error‑rate, and custom metric dashboards.
- **Request ID correlation** — Logs include unique identifiers to trace requests across frontend → backend → database layers.

---

## 🧰 Tech Stack

| Layer | Technology |
|-------|-----------|
| **Mobile** | Flutter 3.22+ · Dart · Google Maps SDK · Geolocator |
| **Backend** | Node.js 18+ · Express · TypeScript |
| **AI Engine** | Google Gemini (`@google/genai` SDK) |
| **Database** | PostgreSQL 15 (Cloud SQL) · Firestore |
| **Realtime** | WebSocket (`ws`) · Firebase Cloud Messaging |
| **Infrastructure** | Google Cloud Run · Cloud Build · Artifact Registry · Docker |
| **Security** | Helmet.js · CORS · Parameterised SQL · Firebase Auth |

---

## ⚙️ Getting Started

### Prerequisites
- **Node.js ≥ 18** and **npm**
- **Flutter ≥ 3.22** (stable channel, Android SDK configured)
- **Google Cloud SDK** (`gcloud`) authenticated to your GCP project
- **Docker Desktop** (optional, for local container testing)

### Backend Setup
```bash
cd arion-ai-backend

npm ci                    # Install dependencies
cp .env.example .env      # Configure Cloud SQL, Firestore, Gemini API key
npm run dev               # Start dev server → http://localhost:8080
```

### Frontend Setup
```bash
flutter pub get           # Fetch packages
flutter run               # Launch on connected device/emulator
```

> Update `baseUrl` in `lib/services/api_service.dart` to point to your backend (Cloud Run URL or `http://10.0.2.2:8080` for Android emulator).

---

## 📦 Building the APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk (~55 MB)
```

---

## ☁️ Cloud Deployment

```bash
cd arion-ai-backend
gcloud builds submit --config cloudbuild.yaml

# Pipeline: Build Image → Push to Artifact Registry → Deploy to Cloud Run
```

The production service URL is displayed in the Cloud Run console. Ensure the `X‑Api‑Key` in `api_service.dart` matches the backend's configured key.

---

## 📡 API Reference

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/incidents/quick-report` | API Key | Submit incident with AI triage |
| `GET` | `/incidents/nearby` | — | Nearby incidents for map view |
| `POST` | `/incidents/:id/corroborate` | API Key | Crowd‑verify an incident |
| `GET` | `/incidents/:id` | — | Full incident detail + timeline |
| `POST` | `/sos/quick` | API Key | Anonymous SOS panic alert |
| `POST` | `/sos/quick/update` | API Key | Live location update for active SOS |
| `POST` | `/sos/quick/cancel` | API Key | Cancel an active SOS |
| `GET` | `/analytics/heatmap` | — | Incident density grid for map overlay |
| `GET` | `/analytics/trends` | — | 7‑day type/severity/hourly trends |
| `GET` | `/analytics/response-performance` | JWT | Per‑responder resolution stats |
| `GET` | `/dashboard/stats` | JWT (emergency) | Dashboard overview counters |
| `GET` | `/dashboard/incidents` | JWT (emergency) | Priority‑sorted incident queue |
| `GET` | `/dashboard/sos` | JWT (emergency) | Active SOS alerts for responder map |
| `WS` | `/ws?room=emergency` | — | Real‑time incident/escalation feed |

---

## 🤝 Contributing

1. **Fork** the repository.
2. **Create a feature branch** — `git checkout -b feat/your-feature`
3. **Write tests** for any new logic.
4. **Run lint & tests** — `npm run lint` · `flutter analyze`
5. **Submit a Pull Request** with a clear description.

All code must adhere to the existing **ESLint** / **dart analyze** rules and include unit or widget tests where applicable.

---

## 🧾 License

© 2026 **Team Tetraverse**. Distributed under the **MIT License**. See `LICENSE` for details.

---

*Built with precision. Deployed with purpose. **Aerion AI** — every second counts.* 🚀
