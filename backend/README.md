# IKE Backend

Standalone inventory counting API for the IKE tablet app (part of LocalCannabis ecosystem).

## Quick Start

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
# .venv\Scripts\activate   # Windows

# Install dependencies
pip install -r requirements.txt

# Copy environment config
cp .env.example .env

# Initialize database (copies example data + adds new tables)
python init_db.py

# Run development server
python run.py
```

Server runs at: http://localhost:5000

## Dev Users (Seeded)

| Email | PIN | Role |
|-------|-----|------|
| admin@example.com | 1111 | admin |
| manager@example.com | 2222 | manager |
| staff@example.com | 3333 | staff |
| dev@example.com | (none) | manager |

## Quick Dev Login

```bash
# No PIN required
curl -X POST http://localhost:5000/api/auth/dev-login \
  -H "Content-Type: application/json" \
  -d '{"email": "dev@example.com"}'
```

Response includes `access_token` - use in Authorization header:
```
Authorization: Bearer <access_token>
```

## API Endpoints

### Auth
- `POST /api/auth/login` - Login with email + PIN
- `POST /api/auth/dev-login` - Quick dev login (auto-creates user)
- `GET /api/auth/me` - Get current user
- `GET /api/auth/users` - List users
- `GET /api/auth/stores` - List stores

### Products
- `GET /api/products/lookup?barcode=XXX` - Barcode lookup
- `GET /api/products` - List products (with filters)
- `GET /api/products/categories` - List category hierarchy
- `GET /api/products/<id>` - Get product

### Count Sessions
- `GET /api/count/sessions` - List sessions
- `POST /api/count/sessions` - Create session
- `GET /api/count/sessions/<id>` - Get session
- `POST /api/count/sessions/<id>/start` - Start counting
- `POST /api/count/sessions/<id>/submit` - Submit for reconciliation

### Count Passes
- `GET /api/count/sessions/<id>/passes` - List passes
- `POST /api/count/sessions/<id>/passes` - Start pass
- `GET /api/count/passes/<id>` - Get pass with lines
- `POST /api/count/passes/<id>/submit` - Complete pass
- `POST /api/count/passes/<id>/void` - Cancel pass

### Count Lines
- `GET /api/count/passes/<id>/lines` - List lines
- `POST /api/count/passes/<id>/lines` - Add/increment line
- `PUT /api/count/lines/<id>` - Edit line
- `DELETE /api/count/lines/<id>` - Delete line

### Variance
- `GET /api/count/sessions/<id>/variance` - Calculate variance report

### Locations
- `GET /api/count/locations?store_id=1` - List locations
- `POST /api/count/locations` - Create location

## Example Workflow

```bash
TOKEN="your_access_token"
AUTH="Authorization: Bearer $TOKEN"

# 1. Get store ID
curl -H "$AUTH" http://localhost:5000/api/auth/stores

# 2. Create a count session
curl -X POST -H "$AUTH" -H "Content-Type: application/json" \
  http://localhost:5000/api/count/sessions \
  -d '{"store_id": 1, "notes": "Test count"}'

# 3. Get locations
curl -H "$AUTH" "http://localhost:5000/api/count/locations?store_id=1"

# 4. Start a count pass
curl -X POST -H "$AUTH" -H "Content-Type: application/json" \
  http://localhost:5000/api/count/sessions/SESSION_ID/passes \
  -d '{"location_id": 1, "category": "Flower", "subcategory": "Dried Flower"}'

# 5. Add count lines (barcode scan)
curl -X POST -H "$AUTH" -H "Content-Type: application/json" \
  http://localhost:5000/api/count/passes/PASS_ID/lines \
  -d '{"barcode": "1066956", "counted_qty": 1}'

# 6. Submit pass
curl -X POST -H "$AUTH" http://localhost:5000/api/count/passes/PASS_ID/submit

# 7. Get variance report
curl -H "$AUTH" http://localhost:5000/api/count/sessions/SESSION_ID/variance
```

## Database

Uses SQLite for development. The `init_db.py` script:
1. Copies `ExampleFormatsDoNotTreatAsLive/cannabis_retail.db` to `instance/inventory_count.db`
2. Adds new tables for inventory counting
3. Seeds dev users and inventory locations

## Future Integration (MK5)

This backend is designed to integrate with the JFK (LocalBot) codebase:
- Same model structure for Store, Product, InventoryItem, User
- Compatible auth patterns (swap dev-login for Google OAuth)
- New tables can be migrated via Alembic
