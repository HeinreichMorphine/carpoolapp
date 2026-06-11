# JomRide (Self-Hosted Stack)

Welcome to the JomRide repository! This is a self-hosted carpooling and ride-hailing application tailored for Malaysia bounds. It features a cross-platform Flutter mobile app (supporting both Passenger and Driver modes), a Deno-based Supabase edge functions backend, a containerized PostgreSQL/PostGIS database, an OSRM routing engine, and a React Admin Dashboard.

---

## 🚀 Getting Started

1. Clone the repository.
2. Ask your team lead for the **`SECRETS_AND_SETUP.md`** file — it contains all private API keys, credential files, and step-by-step setup instructions.
3. Follow the guide to configure your `.env`, compile OSRM data, start Docker, and run the app.

> ⚠️ **`SECRETS_AND_SETUP.md`** is git-ignored and must be shared privately (WhatsApp/Telegram). Never commit secrets.

---

## 🛠 Prerequisites

- **Docker Desktop** (Engine running in WSL 2 mode)
- **Flutter SDK** (Channel stable)
- **Node.js** (v18 or higher)
- **Git**

---

## 📂 Repository Structure

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
├── server/              # Server-side utilities
├── docker-compose.yml   # Multi-container service orchestrator
└── .env.example         # Environment template file
```

---

## 🔒 Security & Git Best Practices

The following files are **strictly ignored** in `.gitignore` to prevent leaking private credentials:
- `SECRETS_AND_SETUP.md` — full team setup guide with real API keys.
- All `.env` environment secret files.
- All credential JSON files (Firebase Admin SDK, Google Client Secrets) in the root directory.
- Large OpenStreetMap binary files (`.osm.pbf` and `.osrm` outputs), too heavy for version control.

**Always remember**: Never commit API keys, bot tokens, or private service accounts. If you add new variables, document them in `.env.example` instead.
