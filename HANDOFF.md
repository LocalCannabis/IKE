# IKE Project Handoff Documentation

**Last Updated:** December 23, 2025  
**Repository:** https://github.com/LocalCannabis/IKE

---

## Quick Start

### Prerequisites
- Python 3.11+ with pip
- Flutter 3.38+ 
- Git

### Running the Backend
```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
pip install -r requirements.txt
python init_db.py  # Initialize database with seed data
python run.py      # Runs on http://localhost:5000
```

### Running the Flutter App
```bash
cd tablet_app
flutter pub get
flutter run -d chrome --web-port=8080  # Web preview
# OR
flutter run -d <device_id>             # Android device
```

### Test Credentials
| Email | PIN | Role |
|-------|-----|------|
| dev@example.com | (none) | manager |
| admin@example.com | 1111 | admin |
| manager@example.com | 2222 | manager |
| staff@example.com | 3333 | staff |

---

## Project Overview

### What is IKE?
IKE is a tablet app for cannabis retail inventory operations:
1. **Inventory Counting** - Partial, time-windowed inventory counts with variance reconciliation
2. **Upstocking** - Nightly FOH restocking from BOH based on sales data

### LocalCannabis Ecosystem
```
LBJ, RBG  → Earlier POCs
JFK       → Current production system (MK4)
BHO       → Next-gen system (MK5, in development)
AOC       → Data analysis module
IKE       → This app (standalone, integrates with JFK/BHO)
```

---

## Architecture

### High-Level Data Flow
```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   ┌──────────┐         ┌─────────────┐         ┌────────────┐  │
│   │   COVA   │ ──CSV──→│  LOCALBOT   │ ──API──→│    IKE     │  │
│   │   POS    │  Email  │    HUB      │         │   TABLET   │  │
│   └──────────┘         │   (JFK)     │         │    APP     │  │
│                        └─────────────┘         └────────────┘  │
│                              │                       │          │
│                              ▼                       ▼          │
│                        ┌─────────────────────────────────┐     │
│                        │     LOCALBOT DASHBOARD          │     │
│                        │   (Reports, Reconciliation)     │     │
│                        └─────────────────────────────────┘     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Directory Structure
```
IKE/
├── ROADMAP.md              # Detailed feature roadmap
├── INTEGRATION_PROPOSAL.md # JFK integration plan
├── UPSTOCK_API.md          # Upstock API documentation
├── HANDOFF.md              # This file
│
├── backend/                # Flask API server
│   ├── app/
│   │   ├── __init__.py    # App factory, blueprint registration
│   │   ├── api/
│   │   │   ├── auth.py    # JWT authentication
│   │   │   ├── count.py   # Inventory count endpoints
│   │   │   ├── products.py # Product lookup
│   │   │   └── upstock.py # Upstock endpoints
│   │   └── models/
│   │       ├── user.py           # User, Store
│   │       ├── product.py        # Product, InventoryItem
│   │       ├── inventory_count.py # Count sessions/passes/lines
│   │       └── upstock.py        # Upstock runs/lines/baselines
│   ├── instance/
│   │   └── inventory_count.db    # SQLite database
│   ├── requirements.txt
│   └── run.py
│
├── tablet_app/             # Flutter development app
│   ├── lib/
│   │   ├── main.dart      # App entry, navigation
│   │   ├── models/        # Data classes
│   │   ├── providers/     # State management (Provider)
│   │   ├── screens/       # UI screens
│   │   │   ├── login_screen.dart
│   │   │   ├── session_screen.dart
│   │   │   ├── count_pass_screen.dart
│   │   │   ├── upstock_home_screen.dart
│   │   │   └── upstock_run_screen.dart
│   │   └── services/
│   │       └── api_service.dart  # HTTP client
│   └── pubspec.yaml
│
└── android_app/            # Kotlin production app (PLANNED)
```

---

## Current Status

### ✅ Completed (Phase 1-3)

**Backend API:**
- [x] Flask app with SQLAlchemy ORM
- [x] JWT authentication (PIN-based for dev)
- [x] User, Store, Product models
- [x] Inventory Count: sessions, passes, lines, movements
- [x] Upstock: runs, lines, baselines
- [x] All CRUD endpoints working

**Flutter App:**
- [x] Login screen with dev auth
- [x] Count session list and management
- [x] Count pass screen with barcode input
- [x] QR/2D barcode scanning (mobile_scanner)
- [x] Upstock home screen
- [x] Upstock run checklist screen
- [x] Bottom navigation (Count / Upstock tabs)

### 🔄 In Progress

**Testing:**
- [ ] End-to-end upstock flow testing
- [ ] Count pass submission workflow
- [ ] Error handling edge cases

### 📋 Planned (Phase 4+)

**Phase 4: Kotlin Production App**
- Android Studio project setup
- Jetpack Compose UI
- Room database for offline
- ML Kit barcode scanning

**Phase 5: JFK Integration**
- Google OAuth (replace PIN auth)
- Connect to JFK's Postgres DB
- Product sync from JFK catalog
- Cova movement import

**Phase 6: Cova Email Ingestion**
- Parse Cova CSV email attachments
- Import into inventory_movements table
- Auto-compute upstock suggestions

---

## Key Concepts

### Inventory Counting Model
Counts are **NOT instantaneous**. They happen in **time windows**:

```
Session (container)
  └── Pass (time window for location + category)
        ├── started_at (begin counting)
        ├── submitted_at (end counting)
        └── Lines (individual scanned items)
```

**Variance Reconciliation:**
```
expected_at_count_time = snapshot_qty + movements_during_window
variance = counted_total - expected_at_count_time
```

### Upstock Model
Pull list computed from sales since last upstock:

```
UpstockRun
  ├── window_start_at (last run completed_at)
  ├── window_end_at (now)
  └── Lines (computed from inventory_movements)
        ├── sold_qty (from movements)
        ├── suggested_pull_qty (= sold_qty)
        ├── pulled_qty (entered by staff)
        └── status (pending/done/skipped/exception)
```

---

## API Reference

### Authentication
```http
POST /api/auth/dev-login
Content-Type: application/json

{"email": "dev@example.com"}

Response: {"access_token": "...", "user": {...}}
```

Use JWT in subsequent requests:
```http
Authorization: Bearer <access_token>
```

### Key Endpoints

| Module | Endpoint | Description |
|--------|----------|-------------|
| **Auth** | POST `/api/auth/dev-login` | Dev login (no PIN) |
| **Auth** | POST `/api/auth/login` | PIN login |
| **Products** | GET `/api/products/lookup?barcode=X` | Lookup by barcode |
| **Count** | GET `/api/count/sessions` | List sessions |
| **Count** | POST `/api/count/sessions` | Create session |
| **Count** | POST `/api/count/sessions/{id}/passes` | Create pass |
| **Count** | POST `/api/count/passes/{id}/lines` | Add count line |
| **Upstock** | POST `/api/upstock/runs/start` | Start upstock run |
| **Upstock** | PATCH `/api/upstock/runs/{id}/lines/{sku}` | Update line |
| **Upstock** | POST `/api/upstock/runs/{id}/complete` | Complete run |

See `UPSTOCK_API.md` for full upstock API documentation.

---

## Database Schema

### Core Tables
```sql
users           -- Employee accounts
stores          -- Store locations
products        -- Product catalog
inventory_items -- Store-specific stock levels
```

### Inventory Count Tables
```sql
inventory_locations      -- FOH_DISPLAY, BOH_STORAGE, etc.
inventory_count_sessions -- Container for a full count
inventory_count_passes   -- Time-windowed partial count
inventory_count_lines    -- Individual scanned items
inventory_movements      -- Sales/adjustments for reconciliation
```

### Upstock Tables
```sql
upstock_baselines  -- Par levels (target stock)
upstock_runs       -- Upstock session
upstock_run_lines  -- Items to pull with fulfillment tracking
upstock_imports    -- CSV import audit trail
```

---

## Configuration

### Backend Environment (.env)
```bash
DATABASE_URL=sqlite:///instance/inventory_count.db
JWT_SECRET_KEY=your-secret-key
FLASK_ENV=development
CORS_ORIGINS=*
```

### Flutter API Endpoint
Edit `tablet_app/lib/services/api_service.dart`:
```dart
static const String baseUrl = 'http://192.168.x.x:5000/api';
```

For tablet testing, use your dev machine's LAN IP.

---

## Building APK for Tablet

1. **Update API URL** in `api_service.dart` with your machine's IP
2. **Build release APK:**
   ```bash
   cd tablet_app
   flutter build apk --release
   ```
3. **APK location:** `build/app/outputs/flutter-apk/app-release.apk`
4. **Install:** Transfer to tablet and install (enable "Unknown Sources")

---

## Known Issues / Tech Debt

1. **No migration scripts** - Database changes require manual schema updates or re-init
2. **Hardcoded store_id** - Some endpoints assume store_id=1
3. **No offline support** - Flutter app requires network connection
4. **Test coverage** - No automated tests yet
5. **Error handling** - Some API errors not gracefully handled in UI

---

## Next Steps for New Team

### Immediate (Testing)
1. Seed test data for upstock (add inventory_movements)
2. Test full upstock workflow: start → scan → confirm → complete
3. Test count pass submission

### Short-term (Production Readiness)
1. Add Alembic migrations for schema changes
2. Implement proper error handling and loading states
3. Add input validation on backend
4. Create test suite

### Medium-term (Integration)
1. Set up Cova email CSV ingestion (see INTEGRATION_PROPOSAL.md)
2. Integrate with JFK for Google OAuth
3. Move to Postgres for multi-device concurrency

### Long-term (Kotlin App)
1. Port Flutter UI patterns to Kotlin + Jetpack Compose
2. Add Room database for offline support
3. Implement ML Kit barcode scanning

---

## Contact

For questions about this codebase:
- **Repository:** https://github.com/LocalCannabis/IKE
- **Slack:** #localbot-dev
- **Email:** tim@localcannabisco.ca

---

**Good luck! 🚀**
