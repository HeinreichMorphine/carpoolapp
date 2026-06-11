# Carpool Malaysia (Self-Hosted Stack)

Welcome to the Carpool Malaysia repository! This is a self-hosted carpooling and ride-hailing application tailored for Malaysia bounds. It features a cross-platform Flutter mobile app (supporting both Passenger and Driver modes), a Deno-based Supabase edge functions backend, a containerized PostgreSQL/PostGIS database, an OSRM routing engine, and a React Admin Dashboard.

---

## 🛠 Prerequisites

Before starting, ensure your local development machine has:
1. **Docker Desktop** (Engine running in WSL 2 mode)
2. **Flutter SDK** (Channel stable)
3. **Node.js** (v18 or higher)
4. **git**

---

## 🚀 Quick Start Guide

### Step 1: Clone the Repo & Configure Environment
1. Clone the repository to your local machine.
2. In the root directory, copy `.env.example` to create your local `.env` file:
   ```bash
   cp .env.example .env
   ```
3. Fill in the placeholder keys in `.env` (ask your teammates for the shared Firebase Service Account JSON, Telegram Bot Token, MapTiler keys, and Stripe test keys).

### Step 2: Download OpenStreetMap Routing Data
1. OSRM uses raw mapping data to calculate distances and route geometry.
2. Download the **Malaysia, Singapore, and Brunei** extract in `.osm.pbf` format from GeoFabrik:
   - [Malaysia-Singapore-Brunei OSM Download Link](https://download.geofabrik.de/asia/malaysia-singapore-brunei-latest.osm.pbf)
3. Save the downloaded `malaysia-singapore-brunei-latest.osm.pbf` file directly inside the `osrm-data/` folder.

### Step 3: Compile OSRM Roadmap (Windows PowerShell)
Before starting the containers, you must compile the roadmap nodes into OSRM format. We have provided a PowerShell script inside `osrm-data/` to automate this:
```powershell
cd osrm-data
.\compile_osrm.ps1
```
*(This downloads the OSRM compiler image and extracts/partitions the roadmap. It takes ~1-2 minutes to finish).*

### Step 4: Spin Up the Docker Compose Stack
Once compilation is complete, start the backend database, authentication gateway, WebSocket server, OSRM engine, and React Admin web server:
```bash
# From the root directory
docker compose up -d
```
Verify all containers are running successfully:
```bash
docker compose ps
```
- **Kong API Gateway**: Runs on `http://localhost:8000` (handles `/auth/v1`, `/rest/v1`, `/realtime/v1`)
- **Vite React Admin Panel**: Runs on `http://localhost:8080` (holds active trip maps and trust whitelists)
- **OSRM Router API**: Runs on `http://localhost:5000`

### Step 5: Launch the Flutter Mobile App
1. Set up a physical device or launch a mobile emulator.
2. Ensure dependencies are resolved:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

---

## 📁 Repository Structure

```text
├── admin_dashboard/     # React Admin dashboard & live tracking page (Vite)
├── android/             # Android native platform configurations
├── ios/                 # iOS native platform configurations
├── lib/                 # Flutter application source files (Main, Screens, Theme)
├── osrm-data/           # OSRM roadmap binary files and compilation scripts
├── supabase/            # Self-hosted database migrations and Edge Functions
│   ├── volumes/api/     # Kong gateway route configurations
│   ├── volumes/db/      # PostgreSQL schemas, PostGIS functions, and RLS policies
│   └── functions/       # Deno serverless edge functions (fare, match, telegram)
├── docker-compose.yml   # Multi-container service orchestrator
└── .env.example         # Environment template file
```

---

## 🔒 Security & Git Best Practices

The following files are **strictly ignored** in `.gitignore` to prevent leaking private credentials:
- All `.env` environment secret files.
- All credential JSON files (such as Google Client Secrets and Firebase Admin SDK private keys) placed in the root directory.
- Large OpenStreetMap binary files (`.osm.pbf` and `.osrm` outputs), which are too heavy for version control.

**Always remember**: Never commit API keys, bot tokens, or private service accounts. If you add new variables, document them in `.env.example` instead.
