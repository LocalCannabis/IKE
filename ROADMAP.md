# IKE - Inventory Count & Upstock Tablet App
Flask Backend + Dual Frontend Strategy (Flutter Dev / Kotlin Prod)

================================================
LOCALCANNABIS ECOSYSTEM
================================================

IKE fits into the LocalCannabis product family:
- **LBJ, RBG** - Earlier proof-of-concept systems
- **JFK** - Current production system (MK4)
- **BHO** - Next-gen system (MK5, in development)
- **AOC** - Data analysis module
- **IKE** - This app. Standalone inventory counting & upstocking
  - Integrates with JFK now
  - Will integrate with BHO later

================================================
PROJECT STATUS (Updated: December 2025)
================================================

## ✅ Phase 1: Backend API (COMPLETE)
- Flask 3.0.0 backend with SQLAlchemy 2.0.45
- JWT authentication (dev PIN-based, Google Auth planned)
- Full data models: User, Store, Product, InventoryItem, 
  InventoryLocation, CountSession, CountPass, CountLine, InventoryMovement
- API endpoints: /api/auth, /api/products, /api/count
- SQLite database with schema migration support
- All endpoints tested and verified working

## ✅ Phase 2: Flutter Dev App Scaffold (COMPLETE)
- Flutter 3.38.5 cross-platform app (DEV/PREVIEW ONLY)
- Provider state management
- API service client
- Core screens: Login, Session List, Count Pass
- Chrome preview for rapid UI iteration
- Data models matching backend

## 🔄 Phase 3: Flutter Workflow Validation (IN PROGRESS)
- [x] Full login → session → pass → scan flow testing
- [x] QR code and 2D barcode scanning (Data Matrix, PDF417)
- [x] Product lookup integration
- [x] Quantity editing and line management
- [ ] UI polish and error handling
- [ ] Pass submission workflow testing
- [ ] Validate UX patterns before Kotlin port

## ✅ Phase 3.5: Upstock Module (COMPLETE - Dec 2025)
- [x] DB models: upstock_baselines, upstock_runs, upstock_run_lines, upstock_imports
- [x] API: /api/upstock/* endpoints (start, update, complete, abandon, baselines)
- [x] Flutter: UpstockHomeScreen + UpstockRunScreen
- [x] Bottom navigation with Count / Upstock tabs
- [x] Scanner input and quick confirm dialogs
- [ ] End-to-end testing with seed data
- [ ] LocalBot dashboard integration (future)

## 📋 Phase 4: Kotlin + Jetpack Compose Production App (PLANNED)
- [ ] Android project setup with Kotlin + Jetpack Compose
- [ ] Material 3 design system
- [ ] Retrofit/OkHttp API client
- [ ] Hilt dependency injection
- [ ] Room local database (offline support)
- [ ] Camera barcode scanning (ML Kit)
- [ ] Bluetooth scanner wedge support
- [ ] Tablet-optimized Compose layouts
- [ ] Offline queue with WorkManager sync

## 📋 Phase 5: JFK Integration (PLANNED)
- [ ] Google OAuth authentication (both apps)
- [ ] Connect to JFK API (current production system)
- [ ] Product sync from cannabis_retail.db
- [ ] Cova inventory movement import
- [ ] Variance reconciliation

## 📋 Phase 6: Cova Email Ingestion (PLANNED)
- [ ] Email service to fetch Cova CSV attachments
- [ ] CSV parser for itemized sales reports
- [ ] Import into inventory_movements table
- [ ] Scheduled job (cron/Celery) for nightly processing
- [ ] Auto-stage upstock runs from imported data

## 📋 Phase 7: BHO Integration (FUTURE)
- [ ] Migrate to BHO API when available
- [ ] Enhanced features from next-gen platform

================================================
DUAL FRONTEND STRATEGY
================================================

Why two apps?

FLUTTER (tablet_app/):
- Rapid prototyping and iteration
- Chrome preview = instant feedback
- Cross-platform testing (Linux desktop too)
- Proves out UX patterns quickly
- NOT for production deployment

KOTLIN + JETPACK COMPOSE (android_app/):
- Production Android tablet deployment
- Native performance and battery efficiency
- Better hardware integration (Bluetooth scanners)
- Room database for robust offline support
- Google's recommended modern Android stack
- Long-term maintainability
- Integration with JFK (now) and BHO (future)

Workflow:
1. Design/test features in Flutter (fast iteration)
2. Validate UX and API contracts
3. Port validated features to Kotlin (production quality)
4. Flutter remains useful for rapid experiments

================================================
GOAL
================================================
Build a tablet-first Android app that enables multi-room, partial inventory
counting during business hours, with full auditability and reconciliation
against non-real-time POS inventory (Cova).

Key outcomes:
- Scan products via barcode (hardware scanner or camera)
- Count inventory per physical room AND per category/subcategory
- Allow partial counts over time (no requirement to finish a whole room)
- Timestamp every count window
- Attribute actions to logged-in employees (Google Auth)
- Reconcile variance even when sales occur mid-count
- Lay groundwork for upstocking and inventory flow tracking

================================================
HIGH-LEVEL ARCHITECTURE
================================================

[ Flutter Dev App ] (tablet_app/)        [ Kotlin Prod App ] (android_app/)
  - Dart / Flutter 3.38.5                  - Kotlin + Jetpack Compose
  - Provider state management              - Hilt DI + ViewModel
  - Chrome preview for rapid dev           - Room local database
  - PIN auth (dev only)                    - Google Sign-In (prod)
  - Barcode input (scanner wedge)          - ML Kit barcode scanning
  - JWT-authenticated API calls            - Retrofit API client
                |                                     |
                +----------------+--------------------+
                                 |
                                 v

                     [ Flask API ] (backend/)
                       - Auth (PIN dev / Google token -> JWT)
                       - Product lookup (barcode -> SKU)
                       - Inventory count sessions
                       - Room + category/subcategory passes
                       - Inventory movements
                       - Variance reconciliation logic

                                 |
                                 v

                     [ SQLite Database ] (instance/inventory_count.db)
                       - products
                       - inventory_items
                       - inventory_locations
                       - inventory_count_sessions
                       - inventory_count_passes
                       - inventory_count_lines
                       - inventory_movements

================================================
CORE DESIGN PRINCIPLE
================================================

Inventory counts are NOT instantaneous.

Counts:
- happen inside TIME WINDOWS
- may cover only PART of a room
- may be split across CATEGORY / SUBCATEGORY chunks
- may overlap with sales activity

Variance is reconciled by aligning:
COUNT WINDOWS  <->  INVENTORY MOVEMENTS

This avoids reliance on real-time POS sync.

================================================
COUNTING MODEL (IMPORTANT)
================================================

A "room" is too large to count in one uninterrupted pass.

Therefore:
- Counts are broken down by:
  - Location (room)
  - Category
  - Subcategory
- Each category/subcategory count is its own PASS
- Multiple passes may exist for the same room

Examples:
- FOH Display -> Flower -> Indica
- FOH Display -> Flower -> Sativa
- BOH Storage -> Vapes -> 510 Carts

Each pass has:
- its own start time
- its own end time
- its own audit trail

================================================
DATA MODEL (DATABASE)
================================================

--------------------------------
inventory_locations
--------------------------------
id (PK)
store_id
code                // FOH_DISPLAY, FOH_SHELF, BOH_STORAGE
name
is_active
sort_order

--------------------------------
inventory_count_sessions
--------------------------------
id (UUID, PK)
store_id
created_by_user_id
created_at
status              // draft | in_progress | submitted | reconciled | closed
expected_snapshot_source   // cova | localbot | manual
expected_snapshot_at       // DATETIME baseline
notes

--------------------------------
inventory_count_passes
--------------------------------
NOTE:
This replaces a strict "room pass".
A pass represents a partial, focused count.

id (UUID, PK)
session_id (FK)
location_id (FK)
cabinet            // category (e.g. Flower, Vapes)
subcategory        // subcategory (e.g. Indica, Live Resin)
started_by_user_id
started_at         // BEGIN COUNT WINDOW
submitted_at       // END COUNT WINDOW
status             // in_progress | submitted | voided
device_id
scan_mode           // scanner | camera | mixed

--------------------------------
inventory_count_lines
--------------------------------
id (UUID, PK)
count_pass_id (FK)
sku
barcode
package_id          // optional (lot/package)
counted_qty
unit                // each
captured_at
captured_by_user_id
confidence           // scanned | typed | corrected
notes

--------------------------------
inventory_movements
--------------------------------
id (PK)
store_id
sku
movement_type        // sale | refund | transfer_in | transfer_out | adjustment
qty_delta            // negative = sale, positive = increase
occurred_at
source               // cova | manual | import
source_ref           // receipt / transaction id

================================================
AUTHENTICATION
================================================

Development:
- PIN-based auth for local testing

Production (MK5+):
- Employee signs in with Google
- App sends Google ID token to JFK API
- API verifies token and returns JWT
- JWT used for all subsequent requests

Roles:
- staff   -> can count, submit passes
- manager -> can reconcile, close sessions, export reports

================================================
API ENDPOINTS (OVERVIEW)
================================================

Auth:
POST /auth/google

Sessions:
POST   /count-sessions
GET    /count-sessions
GET    /count-sessions/{id}
POST   /count-sessions/{id}/start
POST   /count-sessions/{id}/submit
POST   /count-sessions/{id}/reconcile

Count Passes (Room + Category/Subcategory):
POST   /count-sessions/{id}/passes
POST   /count-passes/{id}/submit
POST   /count-passes/{id}/void

Lines:
POST   /count-passes/{id}/lines
PUT    /lines/{id}
DELETE /lines/{id}

Products:
GET /products/lookup?barcode=XXXX

Reports:
GET /count-sessions/{id}/variance

================================================
RECONCILIATION LOGIC
================================================

Inputs:
- Counted quantities per SKU
- Count pass time windows (started_at -> submitted_at)
- Expected inventory snapshot (baseline)
- Inventory movements with timestamps

Algorithm (per SKU):

1. counted_total =
   SUM(counted_qty across all submitted passes)

2. movement_delta =
   SUM(qty_delta where occurred_at falls within
   ANY count pass window for that SKU)

3. expected_at_count_time =
   expected_snapshot_total + movement_delta

4. variance =
   counted_total - expected_at_count_time

Notes:
- Multiple passes may exist for the same SKU
- Overlapping windows are acceptable
- A simplified v1 may use session-wide window:
  earliest pass start -> latest pass submit

================================================
ANDROID APP UX FLOW
================================================

--------------------------------
Login Screen
--------------------------------
- Google Sign-In
- Store selection (future multi-store)

--------------------------------
Session Home
--------------------------------
- Current session status
- Locations listed
- Within each location:
  - Categories
  - Subcategories
  - Status per subcategory:
    - not started
    - in progress
    - submitted

--------------------------------
Start Count Pass
--------------------------------
User selects:
- Location
- Category
- Subcategory

This starts a new COUNT PASS and timer.

--------------------------------
Count Pass Screen (Primary)
--------------------------------
Top Bar:
- Location / Category / Subcategory
- Running timer (count window)
- "Submit Pass" button

Main Area:
- Always-focused input field for scanner wedge
- Optional "Scan with Camera" button
- On barcode scan:
  - Resolve product
  - Validate it belongs to selected category/subcategory
  - Show product card
  - Qty stepper (+ / -)
  - "Add Line"

Line List:
- Product name
- SKU
- Qty
- Tap to edit or delete
- Duplicate scan increments quantity

--------------------------------
Session Summary
--------------------------------
- Coverage matrix:
  Location -> Category -> Subcategory
- Visual gaps where no pass exists
- Button: "Generate Variance Report"

--------------------------------
Variance Report
--------------------------------
Columns:
- SKU
- Product name
- Counted total
- Expected at count time
- Variance

Filters:
- Location
- Category / Subcategory
- Non-zero only

Badges:
- PRELIMINARY (no movement reconciliation yet)
- RECONCILED

================================================
BARCODE STRATEGY
================================================

Primary:
- Bluetooth handheld scanner (HID keyboard wedge)
- Barcode typed into focused input + Enter

Secondary:
- Camera-based scanning fallback

Notes:
- Product barcode identifies SKU, not lot
- Package/lot ID optional in v1
- Counting should never be blocked by missing lot data

================================================
HANDLING NON-REAL-TIME POS SYNC
================================================

- Capture authoritative pass windows locally
- Import sales/movements later from Cova
- Re-run reconciliation when data is available

Reports can exist in two states:
- Preliminary (counts vs snapshot)
- Reconciled (counts vs snapshot + movements)

================================================
FUTURE EXTENSIONS (DESIGNED-IN)
================================================

Upstocking (Phase 6):
- See detailed UPSTOCK MODULE section below
- EOD pull list generation from sales data
- BOH fulfillment tracking
- Par-level baselines

Lot-level tracking:
- 2D barcode parsing
- Supplier-specific formats

Offline mode:
- Local pass queue
- Sync when network restored

================================================
UPSTOCK MODULE
================================================

Purpose:
- Remove friction from nightly upstocking
- Generate pull list automatically based on sales since last upstock
- Track completion with timestamps + employee identity
- Avoid paper lists and guessing
- Keep logic server-side; tablet app is a fast UI + scanner tool

Core idea:
- Establish a "Well Stocked" FOH baseline (par levels)
- Every day, compute what sold since last upstock run
- Suggested pull = sold qty (ignore sold-out items)
- Staff fulfills list from BOH and records actual pulled qty
- Store a completed upstock run for audit + dashboarding

--------------------------------
UPSTOCK DATA MODEL
--------------------------------

upstock_baselines:
- id (PK)
- store_id
- location_id              // FOH location (e.g. FOH_DISPLAY)
- cabinet (TEXT NULL)      // optional: category grouping
- subcategory (TEXT NULL)
- sku (TEXT)
- par_qty (INT)            // "well stocked" target
- updated_at (DATETIME)
- updated_by_user_id

upstock_runs:
- id (UUID, PK)
- store_id
- location_id              // FOH target location
- window_start_at (DATETIME)
- window_end_at (DATETIME NULL)
- status (TEXT)            // in_progress | completed | abandoned
- created_by_user_id
- created_at (DATETIME)
- completed_at (DATETIME NULL)
- notes (TEXT NULL)

upstock_run_lines:
- id (UUID, PK)
- run_id (FK -> upstock_runs.id)
- sku (TEXT)
- sold_qty (INT)                   // computed from movements
- suggested_pull_qty (INT)         // computed suggestion
- pulled_qty (INT NULL)            // entered by staff
- status (TEXT)                    // pending | done | skipped | exception
- exception_reason (TEXT NULL)     // BOH short, already stocked, missing
- updated_at (DATETIME)
- updated_by_user_id

--------------------------------
UPSTOCK API ENDPOINTS
--------------------------------

Baselines:
GET  /upstock/baselines?store_id=&location_id=
PUT  /upstock/baselines
  body: [{sku, par_qty, cabinet?, subcategory?}, ...]

Upstock Runs:
POST /upstock/runs/start
  body: {store_id, location_id, window_end_at?}
  server:
    - chooses window_start_at from last completed run
    - sets window_end_at to now (or provided)
    - computes run lines from movements
  returns: run + lines

GET /upstock/runs?store_id=&location_id=&status=
GET /upstock/runs/{run_id}

PATCH /upstock/runs/{run_id}/lines/{sku}
  body: {pulled_qty, status, exception_reason?}

POST /upstock/runs/{run_id}/complete

--------------------------------
UPSTOCK COMPUTATION LOGIC
--------------------------------

A) Determine the upstock window
- window_start_at = last completed upstock_run.completed_at for store/location
  - if none exists: default to start-of-day
- window_end_at = "now" when starting the run

B) Compute sold_qty per SKU
- Use inventory_movements where movement_type='sale'
- sold_qty = SUM(-qty_delta) for sales in window

C) Determine suggested_pull_qty
- v1 (simple): suggested_pull_qty = sold_qty
- Assumes FOH was "well stocked" at baseline time
- v2 (par-aware): can use par_qty for reporting

--------------------------------
UPSTOCK TABLET UX
--------------------------------

Screen: Upstock Home
- Last completed upstock time
- Button: START UPSTOCK
- Recent runs list

Screen: Upstock Run (Checklist)
Header:
- Location (FOH)
- Window start -> end
- Progress: completed / total
- Button: COMPLETE RUN

Body:
- Group lines by cabinet/subcategory
- Line item layout:
  - Product name, Brand, size
  - SKU
  - SOLD TODAY: sold_qty
  - SUGGESTED PULL: suggested_pull_qty
  - Pulled qty control: quick buttons [0] [1] [2] [3] [5] [+] [-]
  - Status: DONE / SKIP / EXCEPTION

Scanner Support:
- Hidden focused input field
- On barcode scan: highlight matching SKU line
- Allow fast qty confirm

Screen: Completion Summary
- Counts: done / skipped / exception
- List exceptions for manager review
- Timestamps + employee identity

--------------------------------
UPSTOCK DASHBOARD (LocalBot Frontend)
--------------------------------
Add page: Upstock Runs

Views:
1) Runs table: date, store, location, started_by, completion rate, exceptions
2) Run detail: grouped by cabinet/subcategory, sold_qty vs pulled_qty
3) Baseline editor (v2): set par_qty per SKU for FOH

================================================
IMPLEMENTATION MILESTONES
================================================

INVENTORY COUNTING:
✅ 1. Database migrations (Flask/SQLAlchemy)
✅ 2. Auth endpoint (PIN dev, Google planned)
✅ 3. Product lookup API
✅ 4. Session / Count Pass / Line CRUD
✅ 5. Flutter app scaffold
✅ 6. QR + 2D barcode scanning (Data Matrix, PDF417)
🔄 7. Scanner wedge support (keyboard input works)
📋 8. Camera barcode scanning polish
📋 9. Variance report v1
📋 10. Inventory movement ingestion
📋 11. Reconciliation logic
📋 12. Manager tools + export
📋 13. JFK integration (Phase 5)

UPSTOCKING (Phase 6):
📋 14. DB tables: upstock_baselines, upstock_runs, upstock_run_lines
📋 15. API: POST /upstock/runs/start (compute lines from movements)
📋 16. API: PATCH lines, POST complete
📋 17. Flutter: Upstock Home screen
📋 18. Flutter: Upstock Run checklist + qty controls
📋 19. Flutter: Scanner wedge highlight behavior
📋 20. Flutter: Completion summary
📋 21. LocalBot Frontend: Upstock dashboard
📋 22. Cova BOH availability integration (sold-out handling)

FUTURE:
📋 23. BHO integration (Phase 7)

================================================
DIRECTORY STRUCTURE
================================================

/home/macklemoron/Projects/IKE/
├── ROADMAP.md                    # This file
├── ExampleFormatsDoNotTreatAsLive/
│   ├── cannabis_retail.db        # Reference DB schema
│   └── Inventory On Hand...csv   # Sample data
├── backend/                      # Flask API server
│   ├── app/
│   │   ├── __init__.py          # App factory
│   │   ├── models/              # SQLAlchemy models
│   │   └── api/                 # API blueprints
│   ├── instance/
│   │   └── inventory_count.db   # SQLite database
│   ├── requirements.txt
│   └── run.py                   # Server entry point
├── tablet_app/                  # Flutter DEV app (preview/iteration)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/              # Data classes
│   │   ├── providers/           # State management
│   │   ├── screens/             # UI screens
│   │   └── services/            # API client
│   └── pubspec.yaml
└── android_app/                 # Kotlin PROD app (planned)
    ├── app/
    │   └── src/main/
    │       ├── java/.../        # Kotlin source
    │       └── res/             # Resources
    ├── build.gradle.kts
    └── settings.gradle.kts

================================================
RUNNING THE APPS
================================================

Backend:
  cd backend
  source .venv/bin/activate
  python run.py
  # Runs on http://127.0.0.1:5000

Flutter Dev App (Chrome preview):
  cd tablet_app
  flutter run -d chrome
  # Runs on http://localhost:8080

Flutter Dev App (Android device):
  flutter run -d <device_id>

Kotlin Prod App (planned):
  cd android_app
  ./gradlew installDebug
  # Or use Android Studio Run button

================================================
END BLUEPRINT
================================================
