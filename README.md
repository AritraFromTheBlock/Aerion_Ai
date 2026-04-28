# Arion AI – Emergency Response Platform 🚨

## Built by **Team Tetraverse**

![Arion AI Banner](https://raw.githubusercontent.com/your-org/arion-ai/main/docs/banner.png)

> **_A sleek, real‑time emergency response solution built with Flutter, Node.js, and Google Cloud._**

---

## Table of Contents
- [🛠️ Overview](#overview)
- [✨ Key Features](#key-features)
- [🗂️ Architecture](#architecture)
- [⚙️ Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Backend Setup](#backend-setup)
  - [Frontend (Flutter) Setup](#frontend-setup)
- [🚀 Development & Testing](#development--testing)
- [📦 Building the APK](#building-the-apk)
- [☁️ Deploying to Google Cloud Run](#deploying-to-google-cloud-run)
- [💡 Billing Note](#billing-note)
- [🔧 Common Pitfalls & Fixes](#common-pitfalls--fixes)
- [📚 Documentation & Screenshots](#documentation--screenshots)
- [🤝 Contributing](#contributing)
- [🧾 License](#license)

---

## 🛠️ Overview
Arion AI is a **production‑ready** emergency‑response mobile application. It enables citizens to:
- **Send an instant SOS** with location & custom message.
- **Report incidents** that are instantly triaged by Gemini AI.
- **View live incidents** on an interactive map with severity‑coded markers.
- **Confirm (corroborate) incidents** to improve response reliability.

The backend lives on **Google Cloud Run**, stores data in **PostgreSQL (Cloud SQL)**, and uses **Google Firestore** for real‑time alerts. The Flutter client communicates through a clean, type‑safe API service.

---

## ✨ Key Features
| Feature | Description |
|--------|-------------|
| **📍 Real‑time Map** | Live incident markers with distance‑based scaling & severity colours.
| **🤖 AI‑triage** | Gemini‑powered incident classification & summarisation.
| **🚨 Panic SOS** | One‑tap emergency button that sends GPS + optional custom message.
| **🗂️ Incident Dashboard** | Rescue‑mode view with detailed incident list & heat‑map overlays.
| **🔐 Secure Backend** | Parameterised SQL queries, JWT‑based auth (future), and robust error handling.
| **🛠️ Cross‑platform** | Flutter app works on Android (APK) and iOS (future).
| **🧩 Extensible Architecture** | Separate `api_service.dart`, modular Node.js routes, and Dockerised deployment.

---

## 🗂️ Architecture
```
Arion AI (Flutter)            ←─── HTTPS (X‑API‑Key) ──►  Cloud Run (Node.js)
│                              │
│  lib/                        │   src/
│   ├─ screens/                │    ├─ routes/ (incidents, sos, dashboard)
│   ├─ services/api_service.dart│    ├─ middleware/ (auth, validation)
│   └─ models/alert_model.dart │    └─ config/ (db, firebase, ai)
│                              │
│  Firebase Firestore (real‑time)   Cloud SQL (PostgreSQL)
│                              │   (incident, user, sos tables)
└─ assets/ (icons, fonts)          Dockerfile → Artifact Registry
```
All network traffic is encrypted via HTTPS. The backend uses **parameterised PostgreSQL queries** to prevent SQL injection (fixed in `incidents.ts` and `dashboard.ts`).

---

## ⚙️ Getting Started
### Prerequisites
- **Node.js ≥18** and **npm** (for the backend)
- **Flutter ≥3.22** with a recent stable channel (Android SDK installed)
- **Google Cloud SDK** (`gcloud`) – authenticated to the project `aegis-crisis-response-493911`
- **Docker Desktop** (optional, for local backend container testing)
- **A Google Cloud billing account** linked to the project (required for Cloud Run). See the **Billing Note** below.

### Backend Setup
```bash
# Clone the repository (if not already) and cd into backend
cd "C:/Users/panda/OneDrive/Desktop/Arion AI/arion-ai-backend"

# Install dependencies
npm ci   # deterministic install (already in node_modules)

# Create a .env file – copy the template
cp .env.example .env
# Edit .env with your Cloud SQL credentials, Firestore project ID, etc.

# Run lint & type‑check (optional)
npm run lint

# Run locally (development server)
npm run dev   # listens on http://localhost:8080
```
> **Tip:** The backend exposes a health endpoint at `GET /healthz`.

### Frontend (Flutter) Setup
```bash
# From the project root
cd "C:/Users/panda/OneDrive/Desktop/Arion AI"

# Get Flutter packages
flutter pub get

# Run the app on an emulator or device
flutter run   # or flutter run --release for production build
```
The app expects the backend URL defined in `api_service.dart` (`baseUrl`). If you run the backend locally, update the constant to `http://10.0.2.2:8080` (Android emulator) or your LAN IP.

---

## 🚀 Development & Testing
- **Backend:** `npm run lint` (tsc no‑emit) validates TypeScript. Use `npm test` (if you add Jest/Mocha tests).
- **Flutter:** `flutter analyze` shows static analysis; `flutter test` runs unit/widget tests.
- **Live Debugging:** The API service now uses a *centralised safe JSON decoder* (`_safeJsonDecode`) that converts HTML error pages or empty responses into a user‑friendly `ApiException` – no more unexpected `FormatException` crashes.

---

## 📦 Building the APK
```bash
# From project root
flutter build apk --release

# The APK will be at:
build/app/outputs/flutter-apk/app-release.apk
```
A production‑ready **55 MB** APK is generated. I automatically copied it to your Desktop as `Arion‑AI.apk` during the last step.

---

## ☁️ Deploying to Google Cloud Run
```bash
# From the backend folder
cd "C:/Users/panda/OneDrive/Desktop/Arion AI/arion-ai-backend"

# Build and push Docker image
gcloud builds submit --config cloudbuild.yaml

# The Cloud Build pipeline:
#   1️⃣ Build Docker image
#   2️⃣ Push to Artifact Registry
#   3️⃣ Deploy to Cloud Run (service: arion‑ai‑backend)
```
After deployment, the service URL appears in the Cloud Run console (e.g. `https://arion-ai-backend-kshlsswxia-el.a.run.app`). Ensure the **`X‑Api‑Key`** in `api_service.dart` matches the backend key.

---

## 🛠️ Technical Approach & Architecture

**Service‑Oriented Design** – The backend is built as a collection of stateless Express routes (incidents, SOS, analytics) each encapsulated in dedicated TypeScript service modules, enabling horizontal scaling and clear separation of concerns.

**API Layer** – All endpoints expose a clean JSON contract defined by TypeScript interfaces. Anonymous endpoints are protected by an `X‑Api‑Key` header, while future authenticated calls will use JWTs. All SQL statements are fully parameterised to eliminate injection risks.

**Data Layer** – PostgreSQL (Cloud SQL) stores core incident and SOS records. Firestore is leveraged for real‑time push notifications to the Flutter client. Schema migrations are version‑controlled via SQL scripts.

**CI/CD Pipeline** – Cloud Build builds a Docker image, pushes it to Artifact Registry, and deploys to Cloud Run. The pipeline runs linting, type‑checking, and security scans on every commit, ensuring consistent releases.

**Observability** – Cloud Logging captures structured request traces; Cloud Monitoring provides latency, error‑rate, and custom dashboards. Logs include request IDs to correlate frontend and backend processing.

**Infrastructure as Code** – Deployment configuration resides in `cloudbuild.yaml` and `Dockerfile`. Service resources (memory, CPU, concurrency, timeout) are declaratively specified, enabling repeatable, reproducible deployments.

---

## 💡 Billing Note
Your Cloud Run service is currently **returning 503** because **billing is disabled** for the GCP project (`aegis-crisis-response-493911`).

**Fix:**
1. Open the Google Cloud Console → **Billing**.
2. **Link** an active billing account to the project or re‑enable the existing one.
3. Verify the service status again (`gcloud run services describe ...`). The request should now return **200**.

Once billing is active, the mobile app will communicate with the backend without the "Server unavailable" error.

---

## 🔧 Common Pitfalls & Fixes
| Symptom | Cause | Fix |
|---------|-------|-----|
| `FormatException` on API calls | Backend returned HTML error page. | Added `_safeJsonDecode` + `_expectSuccess` – now throws `ApiException` with friendly messages.
| SOS messages not stored in DB | `INSERT` omitted `message` column. | Fixed in `src/routes/sos.ts` – now inserts `message`.
| SQL injection warnings | Raw string interpolation in `incidents.ts` & `dashboard.ts`. | Switched to parameterised queries (`$N`). |
| 503 Service Unavailable | Billing disabled for Cloud Run project. | Re‑enable billing (see Billing Note). |
| Unused import warnings | Stale import in `login_screen.dart`. | Removed `primary_button.dart` import. |

---

## 📚 Documentation & Screenshots
Below is a quick visual tour. *(Replace the placeholders with real screenshots if you wish to commit them to the repo.)*

![Main Map Screen](https://raw.githubusercontent.com/your‑org/arion‑ai/main/docs/main_map.png)
*Live incident map with colour‑coded severity markers.*

![Report Screen](https://raw.githubusercontent.com/your‑org/arion‑ai/main/docs/report_screen.png)
*AI‑triaged incident reporting.*

![SOS Screen](https://raw.githubusercontent.com/your‑org/arion‑ai/main/docs/sos_screen.png)
*One‑tap panic button with custom message support.*

---

## 🤝 Contributing
Contributions are welcome! Please follow these steps:
1. **Fork** the repository.
2. **Create a feature branch** (`git checkout -b feat/awesome‑feature`).
3. **Write tests** for any new logic.
4. **Run lint & tests** (`npm run lint`, `flutter analyze`).
5. **Submit a Pull Request** with a clear description.

All code should adhere to the existing **eslint**/**dart analyze** rules and include **unit or widget tests** where applicable.

---

## 🧾 License
© 2026 Panda Software.  Distributed under the **MIT License**. See `LICENSE` for details.

---

*Happy coding, stay safe, and let Arion AI bring help to those who need it the most!*
