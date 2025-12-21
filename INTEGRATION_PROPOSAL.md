# LocalBot Inventory Count Integration Proposal

Based on analysis of the JFK (LocalBot) codebase and the Inventory Count App roadmap.

---

## 1. CODEBASE ANALYSIS SUMMARY

### Existing Architecture
```
JFK/backend/
├── app/
│   ├── __init__.py          # Flask app factory, blueprint registration
│   ├── api/                  # REST endpoints (Blueprint pattern)
│   │   ├── auth.py           # Google OAuth + JWT (existing!)
│   │   ├── inventory.py      # Product/item management
│   │   ├── stores.py         # Multi-store CRUD
│   │   └── ...
│   ├── models/               # SQLAlchemy models
│   │   ├── product.py        # Product (universal catalog)
│   │   ├── store.py          # Store + InventoryItem
│   │   ├── user.py           # User + UserStorePermission
│   │   └── catalog.py        # Cabinet, CatalogPage, CatalogPageItem
│   └── services/             # Business logic
│       └── ingestion/        # CSV parsing pipeline
└── migrations/               # Alembic (no versions yet)
```

### Key Existing Models

| Model | Purpose | Key Fields |
|-------|---------|------------|
| `Store` | Multi-location support | `id`, `code`, `name`, `cova_location_id` |
| `Product` | Universal catalog hub | `id`, `sku`, `cova_sku`, `category`, `subcategory` |
| `InventoryItem` | Store-specific stock | `store_id`, `product_id`, `current_quantity` |
| `User` | Google Workspace auth | `id`, `google_id`, `email`, `role` |
| `UserStorePermission` | Store-level RBAC | `user_id`, `store_id`, `permissions` |
| `Cabinet` | Menu organization | `store_id`, `name`, `slug` |

### Authentication (Already Implemented!)
- **Google OAuth** → `/api/auth/google` (token validation)
- **JWT tokens** returned with user payload
- `@jwt_required()` decorator on protected routes
- Role system: `admin`, `manager`, `operator`, `viewer`

---

## 2. INTEGRATION POINTS

### A. Reuse Existing Infrastructure

| Roadmap Need | JFK Already Has |
|--------------|-----------------|
| Google Sign-In | ✅ `app/api/auth.py` - full implementation |
| User management | ✅ `User` model with roles |
| Store selection | ✅ `Store` model + `UserStorePermission` |
| Product lookup | ✅ `Product` model with `sku` index |
| Category/Subcategory | ✅ `Product.category`, `Product.subcategory` |
| JWT authentication | ✅ Flask-JWT-Extended configured |

### B. New Tables Needed

The roadmap defines these new tables. They integrate cleanly:

```
inventory_locations      → NEW (physical locations within store)
inventory_count_sessions → NEW (count session container)
inventory_count_passes   → NEW (partial count within session)
inventory_count_lines    → NEW (individual item counts)
inventory_movements      → NEW (sales/adjustments for reconciliation)
```

### C. Category/Subcategory Mapping

From the example DB and CSV, the existing classification system maps well:

| CSV Classification | DB Category | DB Subcategory |
|--------------------|-------------|----------------|
| Dried Flower | Flower | Dried Flower |
| Pre-Rolls | Pre-roll | Pre-Rolls |
| Resin Vapes | Inhalable Extracts | Resin Vapes |
| Distillate Gummies/Chews | Edibles | Distillate Gummies/Chews |

This matches the `_CLASSIFICATION_CATEGORY_MAP` in `services/ingestion/service.py`.

---

## 3. PROPOSED SCHEMA ADDITIONS

### New Model File: `app/models/inventory_count.py`

```python
from app import db
from datetime import datetime
import uuid


class InventoryLocation(db.Model):
    """Physical counting locations within a store (FOH, BOH, etc.)"""
    
    __tablename__ = "inventory_locations"
    
    id = db.Column(db.Integer, primary_key=True)
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    code = db.Column(db.String(50), nullable=False)  # FOH_DISPLAY, BOH_STORAGE
    name = db.Column(db.String(100), nullable=False)
    description = db.Column(db.Text)
    is_active = db.Column(db.Boolean, default=True)
    sort_order = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    store = db.relationship("Store", backref="inventory_locations")
    count_passes = db.relationship("InventoryCountPass", back_populates="location")
    
    __table_args__ = (
        db.UniqueConstraint("store_id", "code", name="unique_store_location_code"),
        db.Index("idx_inv_locations_store", "store_id"),
    )


class InventoryCountSession(db.Model):
    """Container for a full inventory count (may span multiple days)"""
    
    __tablename__ = "inventory_count_sessions"
    
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Session lifecycle
    status = db.Column(db.String(30), default="draft")  # draft|in_progress|submitted|reconciled|closed
    
    # Expected inventory baseline
    expected_snapshot_source = db.Column(db.String(30), default="cova")  # cova|localbot|manual
    expected_snapshot_at = db.Column(db.DateTime)  # When baseline was captured
    expected_snapshot_id = db.Column(db.Integer, db.ForeignKey("inventory_snapshots.id"))
    
    notes = db.Column(db.Text)
    closed_at = db.Column(db.DateTime)
    closed_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    # Relationships
    store = db.relationship("Store", backref="count_sessions")
    created_by = db.relationship("User", foreign_keys=[created_by_user_id])
    closed_by = db.relationship("User", foreign_keys=[closed_by_user_id])
    passes = db.relationship("InventoryCountPass", back_populates="session", cascade="all, delete-orphan")
    
    __table_args__ = (
        db.Index("idx_count_sessions_store_status", "store_id", "status"),
    )


class InventoryCountPass(db.Model):
    """A focused counting window for a specific location + category/subcategory"""
    
    __tablename__ = "inventory_count_passes"
    
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = db.Column(db.String(36), db.ForeignKey("inventory_count_sessions.id"), nullable=False)
    location_id = db.Column(db.Integer, db.ForeignKey("inventory_locations.id"), nullable=False)
    
    # Counting scope (category hierarchy)
    cabinet = db.Column(db.String(100))  # Category: Flower, Edibles, etc.
    subcategory = db.Column(db.String(100))  # Subcategory: Dried Flower, Gummies, etc.
    
    # Time window (critical for reconciliation)
    started_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    submitted_at = db.Column(db.DateTime)  # NULL = still counting
    
    # Attribution
    started_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    submitted_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    # Pass state
    status = db.Column(db.String(30), default="in_progress")  # in_progress|submitted|voided
    
    # Device tracking (for audit)
    device_id = db.Column(db.String(100))
    scan_mode = db.Column(db.String(20), default="scanner")  # scanner|camera|mixed
    
    # Relationships
    session = db.relationship("InventoryCountSession", back_populates="passes")
    location = db.relationship("InventoryLocation", back_populates="count_passes")
    started_by = db.relationship("User", foreign_keys=[started_by_user_id])
    submitted_by = db.relationship("User", foreign_keys=[submitted_by_user_id])
    lines = db.relationship("InventoryCountLine", back_populates="pass_", cascade="all, delete-orphan")
    
    __table_args__ = (
        db.Index("idx_count_passes_session", "session_id"),
        db.Index("idx_count_passes_window", "started_at", "submitted_at"),
    )


class InventoryCountLine(db.Model):
    """Individual counted item within a pass"""
    
    __tablename__ = "inventory_count_lines"
    
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    count_pass_id = db.Column(db.String(36), db.ForeignKey("inventory_count_passes.id"), nullable=False)
    
    # Product identification
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"), nullable=False)
    sku = db.Column(db.String(50), nullable=False)  # Denormalized for audit
    barcode = db.Column(db.String(100))  # Scanned barcode (may differ from SKU)
    package_id = db.Column(db.String(100))  # Optional lot/package tracking
    
    # Count data
    counted_qty = db.Column(db.Integer, nullable=False)
    unit = db.Column(db.String(20), default="each")
    
    # Attribution and audit
    captured_at = db.Column(db.DateTime, default=datetime.utcnow)
    captured_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    confidence = db.Column(db.String(20), default="scanned")  # scanned|typed|corrected
    notes = db.Column(db.Text)
    
    # Relationships
    pass_ = db.relationship("InventoryCountPass", back_populates="lines")
    product = db.relationship("Product")
    captured_by = db.relationship("User")
    
    __table_args__ = (
        db.Index("idx_count_lines_pass", "count_pass_id"),
        db.Index("idx_count_lines_sku", "sku"),
    )


class InventoryMovement(db.Model):
    """Sales, transfers, adjustments for variance reconciliation"""
    
    __tablename__ = "inventory_movements"
    
    id = db.Column(db.Integer, primary_key=True)
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"), nullable=False)
    sku = db.Column(db.String(50), nullable=False)  # Denormalized
    
    # Movement details
    movement_type = db.Column(db.String(30), nullable=False)  # sale|refund|transfer_in|transfer_out|adjustment
    qty_delta = db.Column(db.Integer, nullable=False)  # Negative = decrease
    
    # Timing (critical for reconciliation window matching)
    occurred_at = db.Column(db.DateTime, nullable=False)
    
    # Source tracking
    source = db.Column(db.String(30), default="cova")  # cova|manual|import
    source_ref = db.Column(db.String(100))  # Transaction/receipt ID
    
    # Import tracking
    imported_at = db.Column(db.DateTime, default=datetime.utcnow)
    imported_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    # Relationships
    store = db.relationship("Store")
    product = db.relationship("Product")
    imported_by = db.relationship("User")
    
    __table_args__ = (
        db.Index("idx_movements_store_time", "store_id", "occurred_at"),
        db.Index("idx_movements_sku_time", "sku", "occurred_at"),
    )
```

---

## 4. PROPOSED API ADDITIONS

### New Blueprint: `app/api/count.py`

Following existing patterns from `inventory.py` and `stores.py`:

```
# Count Sessions
POST   /api/count/sessions                    # Create new session
GET    /api/count/sessions                    # List sessions (filtered by store/status)
GET    /api/count/sessions/<id>               # Get session details
POST   /api/count/sessions/<id>/start         # Begin counting (status → in_progress)
POST   /api/count/sessions/<id>/submit        # Mark counting complete
POST   /api/count/sessions/<id>/reconcile     # Run variance calculation
GET    /api/count/sessions/<id>/variance      # Get variance report

# Count Passes
POST   /api/count/sessions/<id>/passes        # Start a new pass
GET    /api/count/passes/<id>                 # Get pass details
POST   /api/count/passes/<id>/submit          # Complete pass (set submitted_at)
POST   /api/count/passes/<id>/void            # Cancel pass

# Count Lines
POST   /api/count/passes/<id>/lines           # Add/update line (increment on duplicate)
PUT    /api/count/lines/<id>                  # Edit line
DELETE /api/count/lines/<id>                  # Remove line

# Product Lookup (for barcode scanning)
GET    /api/count/products/lookup?barcode=XXX # Resolve barcode to product

# Inventory Locations
GET    /api/count/locations                   # List locations for store
POST   /api/count/locations                   # Create location (admin)

# Movements (for reconciliation)
POST   /api/count/movements/import            # Bulk import movements from Cova
```

### Blueprint Registration

Add to `app/__init__.py`:

```python
from app.api import count

app.register_blueprint(count.bp, url_prefix="/api/count")
```

---

## 5. RECONCILIATION SERVICE

### New Service: `app/services/reconciliation.py`

```python
from datetime import datetime
from typing import Dict, List, Tuple
from sqlalchemy import func, and_
from app import db
from app.models.inventory_count import (
    InventoryCountSession, InventoryCountPass, InventoryCountLine, InventoryMovement
)
from app.models.store import InventoryItem
from app.models.product import Product


class ReconciliationService:
    """
    Variance = Counted - Expected @ Count Time
    
    Expected @ Count Time = Snapshot + Movements during count windows
    """
    
    def calculate_variance(self, session_id: str) -> List[Dict]:
        session = InventoryCountSession.query.get(session_id)
        if not session:
            raise ValueError("Session not found")
        
        # Get all submitted passes
        passes = InventoryCountPass.query.filter(
            InventoryCountPass.session_id == session_id,
            InventoryCountPass.status == "submitted"
        ).all()
        
        if not passes:
            return []
        
        # Build time windows
        earliest_start = min(p.started_at for p in passes)
        latest_submit = max(p.submitted_at for p in passes if p.submitted_at)
        
        # Aggregate counted quantities by SKU
        counted_by_sku = self._aggregate_counts(session_id)
        
        # Get baseline snapshot quantities
        baseline_by_sku = self._get_baseline(session)
        
        # Calculate movement deltas during count windows
        movement_deltas = self._calculate_movement_deltas(
            session.store_id, passes
        )
        
        # Build variance report
        all_skus = set(counted_by_sku.keys()) | set(baseline_by_sku.keys())
        results = []
        
        for sku in all_skus:
            counted = counted_by_sku.get(sku, 0)
            baseline = baseline_by_sku.get(sku, 0)
            movement = movement_deltas.get(sku, 0)
            
            expected = baseline + movement
            variance = counted - expected
            
            results.append({
                "sku": sku,
                "counted_qty": counted,
                "baseline_qty": baseline,
                "movement_delta": movement,
                "expected_qty": expected,
                "variance": variance,
            })
        
        return sorted(results, key=lambda x: abs(x["variance"]), reverse=True)
    
    def _aggregate_counts(self, session_id: str) -> Dict[str, int]:
        """Sum counted quantities across all submitted passes."""
        results = db.session.query(
            InventoryCountLine.sku,
            func.sum(InventoryCountLine.counted_qty)
        ).join(
            InventoryCountPass
        ).filter(
            InventoryCountPass.session_id == session_id,
            InventoryCountPass.status == "submitted"
        ).group_by(
            InventoryCountLine.sku
        ).all()
        
        return {sku: int(total) for sku, total in results}
    
    def _get_baseline(self, session: InventoryCountSession) -> Dict[str, int]:
        """Get expected quantities from snapshot or current inventory."""
        # For v1, use current inventory as baseline
        results = db.session.query(
            Product.sku,
            InventoryItem.current_quantity
        ).join(
            InventoryItem
        ).filter(
            InventoryItem.store_id == session.store_id
        ).all()
        
        return {sku: qty or 0 for sku, qty in results}
    
    def _calculate_movement_deltas(
        self, store_id: int, passes: List[InventoryCountPass]
    ) -> Dict[str, int]:
        """
        Sum movements that occurred during ANY pass window.
        This handles overlapping passes correctly.
        """
        # Build OR conditions for each pass window
        window_conditions = []
        for p in passes:
            if p.submitted_at:
                window_conditions.append(
                    and_(
                        InventoryMovement.occurred_at >= p.started_at,
                        InventoryMovement.occurred_at <= p.submitted_at
                    )
                )
        
        if not window_conditions:
            return {}
        
        from sqlalchemy import or_
        results = db.session.query(
            InventoryMovement.sku,
            func.sum(InventoryMovement.qty_delta)
        ).filter(
            InventoryMovement.store_id == store_id,
            or_(*window_conditions)
        ).group_by(
            InventoryMovement.sku
        ).all()
        
        return {sku: int(delta) for sku, delta in results}
```

---

## 6. EDIT PROPOSALS FOR JFK

### A. Add relationship backref to Store model

**File:** `backend/app/models/store.py`

Add to `Store` class relationships:

```python
# Add these backrefs for inventory count integration
# inventory_locations = relationship defined in inventory_count.py
# count_sessions = relationship defined in inventory_count.py
```

### B. Register new model in `__init__.py`

**File:** `backend/app/__init__.py`

Add import in the models block (~line 210):

```python
from app.models import (  # noqa: F401
    user,
    store,
    product,
    catalog,
    presentation,
    ingestion,
    app_setting,
    inventory_count,  # ADD THIS
)
```

### C. Add role constants for tablet app

**File:** `backend/app/models/user.py`

The existing roles work well:
- `operator` → Can count, submit passes
- `manager` → Can reconcile, close sessions
- `admin` → Full access

No changes needed, but document the mapping.

### D. Add barcode lookup endpoint

**File:** `backend/app/api/inventory.py`

Add endpoint for barcode resolution (useful for tablet app):

```python
@bp.route("/products/lookup", methods=["GET"])
@jwt_required()
def lookup_product_by_barcode():
    """Resolve barcode to product for inventory counting."""
    barcode = request.args.get("barcode", "").strip()
    if not barcode:
        return jsonify({"error": "barcode parameter required"}), 400
    
    # Try exact SKU match first
    product = Product.query.filter(
        (Product.sku == barcode) | (Product.cova_sku == barcode)
    ).first()
    
    if not product:
        return jsonify({"error": "Product not found", "barcode": barcode}), 404
    
    return jsonify({
        "id": product.id,
        "sku": product.sku,
        "cova_sku": product.cova_sku,
        "name": product.name,
        "brand": product.brand,
        "category": product.category,
        "subcategory": product.subcategory,
    })
```

---

## 7. CSV DATA MAPPING

The Cova "Inventory On Hand by Package" CSV maps to existing structures:

| CSV Column | Target |
|------------|--------|
| `SKU` | `Product.sku` / `Product.cova_sku` |
| `Product` | `Product.name` |
| `Classification` | `Product.subcategory` (via `_CLASSIFICATION_CATEGORY_MAP`) |
| `In Stock Qty` | `InventoryItem.current_quantity` |
| `PackageId` | `InventoryCountLine.package_id` (new, for lot tracking) |
| `Room` | `InventoryLocation.code` (new) |
| `Unit Cost` | `InventoryItem.cost_price` |
| `Regular Price` | `InventoryItem.retail_price` |

**Note:** The CSV has package-level granularity. Multiple rows may exist for the same SKU with different `PackageId` values. The count system should:
1. Allow scanning any package barcode → resolve to SKU
2. Aggregate counts at SKU level for variance
3. Optionally track package-level counts for lot reconciliation

---

## 8. MIGRATION CHECKLIST

1. [ ] Create `backend/app/models/inventory_count.py`
2. [ ] Update `backend/app/__init__.py` to import new models
3. [ ] Create Alembic migration: `flask db migrate -m "Add inventory count tables"`
4. [ ] Create `backend/app/api/count.py` blueprint
5. [ ] Register blueprint in `__init__.py`
6. [ ] Create `backend/app/services/reconciliation.py`
7. [ ] Add barcode lookup endpoint to `inventory.py`
8. [ ] Add tests in `backend/tests/`

---

## 9. NEXT STEPS

1. **Review this proposal** - Confirm alignment with business requirements
2. **Create models** - I can generate the full model file
3. **Create migration** - Generate Alembic migration
4. **Implement API** - Create count.py blueprint with full CRUD
5. **Reconciliation service** - Implement variance calculation
6. **Tests** - Unit tests for new functionality

Would you like me to proceed with implementing any of these components?
