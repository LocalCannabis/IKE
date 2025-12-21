# IKE - Inventory Count Tablet App
Flask Backend + Dual Frontend Strategy (Flutter Dev / Kotlin Prod)

================================================
LOCALCANNABIS ECOSYSTEM
================================================

IKE fits into the LocalCannabis product family:
- **LBJ, RBG** - Earlier proof-of-concept systems
- **JFK** - Current production system (MK4)
- **BHO** - Next-gen system (MK5, in development)
- **AOC** - Data analysis module
- **IKE** - This app. Standalone inventory counting
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
- [ ] Full login → session → pass → scan flow testing
- [ ] UI polish and error handling
- [ ] Product lookup integration
- [ ] Quantity editing and line management
- [ ] Pass submission workflow
- [ ] Validate UX patterns before Kotlin port

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

## 📋 Phase 6: BHO Integration (FUTURE)
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

Upstocking:
- Staff request quantity per SKU per location
- BOH fulfillment records actual moved qty
- Track product flow between locations

Lot-level tracking:
- 2D barcode parsing
- Supplier-specific formats

Offline mode:
- Local pass queue
- Sync when network restored

================================================
IMPLEMENTATION MILESTONES
================================================

✅ 1. Database migrations (Flask/SQLAlchemy)
✅ 2. Auth endpoint (PIN dev, Google planned)
✅ 3. Product lookup API
✅ 4. Session / Count Pass / Line CRUD
✅ 5. Flutter app scaffold
🔄 6. Scanner wedge support (keyboard input works)
📋 7. Camera barcode scanning
📋 8. Variance report v1
📋 9. Inventory movement ingestion
📋 10. Reconciliation logic
📋 11. Manager tools + export
📋 12. JFK integration (Phase 5)
📋 13. BHO integration (Phase 6)

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
