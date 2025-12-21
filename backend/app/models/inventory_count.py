"""
Inventory Count models - the core of the counting app.
These are NEW tables that extend the existing schema.
"""
from datetime import datetime
import uuid
from app import db


def generate_uuid():
    return str(uuid.uuid4())


class InventoryLocation(db.Model):
    """Physical counting locations within a store (FOH Display, BOH Storage, etc.)."""
    
    __tablename__ = "inventory_locations"
    
    id = db.Column(db.Integer, primary_key=True)
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    code = db.Column(db.String(50), nullable=False)  # FOH_DISPLAY, BOH_STORAGE
    name = db.Column(db.String(100), nullable=False)  # "Front of House - Display"
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
    
    def __repr__(self):
        return f"<InventoryLocation {self.code}>"


class InventoryCountSession(db.Model):
    """
    Container for a full inventory count.
    May span multiple days and contain many passes.
    """
    
    __tablename__ = "inventory_count_sessions"
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Session lifecycle
    status = db.Column(db.String(30), default="draft")
    # draft -> in_progress -> submitted -> reconciled -> closed
    
    # Expected inventory baseline for variance calculation
    expected_snapshot_source = db.Column(db.String(30), default="localbot")  # cova | localbot | manual
    expected_snapshot_at = db.Column(db.DateTime)  # When baseline was captured
    
    notes = db.Column(db.Text)
    closed_at = db.Column(db.DateTime)
    closed_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    # Relationships
    store = db.relationship("Store", backref="count_sessions")
    created_by = db.relationship("User", foreign_keys=[created_by_user_id], backref="created_sessions")
    closed_by = db.relationship("User", foreign_keys=[closed_by_user_id])
    passes = db.relationship("InventoryCountPass", back_populates="session", cascade="all, delete-orphan")
    
    __table_args__ = (
        db.Index("idx_count_sessions_store_status", "store_id", "status"),
    )
    
    def __repr__(self):
        return f"<CountSession {self.id[:8]}... [{self.status}]>"


class InventoryCountPass(db.Model):
    """
    A focused counting window for a specific location + category/subcategory.
    
    This is the key concept: counts happen in TIME WINDOWS, not instantaneously.
    Each pass has a start time and end time for reconciliation.
    """
    
    __tablename__ = "inventory_count_passes"
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    session_id = db.Column(db.String(36), db.ForeignKey("inventory_count_sessions.id"), nullable=False)
    location_id = db.Column(db.Integer, db.ForeignKey("inventory_locations.id"), nullable=False)
    
    # Counting scope (category hierarchy)
    category = db.Column(db.String(100))  # Flower, Edibles, Inhalable Extracts, etc.
    subcategory = db.Column(db.String(100))  # Dried Flower, Gummies, Resin Vapes, etc.
    
    # TIME WINDOW - critical for reconciliation
    started_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    submitted_at = db.Column(db.DateTime)  # NULL = still counting
    
    # Attribution
    started_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    submitted_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    # Pass state
    status = db.Column(db.String(30), default="in_progress")  # in_progress | submitted | voided
    
    # Device tracking (for audit)
    device_id = db.Column(db.String(100))
    scan_mode = db.Column(db.String(20), default="scanner")  # scanner | camera | manual
    
    # Relationships
    session = db.relationship("InventoryCountSession", back_populates="passes")
    location = db.relationship("InventoryLocation", back_populates="count_passes")
    started_by = db.relationship("User", foreign_keys=[started_by_user_id])
    submitted_by = db.relationship("User", foreign_keys=[submitted_by_user_id])
    lines = db.relationship("InventoryCountLine", back_populates="count_pass", cascade="all, delete-orphan")
    
    __table_args__ = (
        db.Index("idx_count_passes_session", "session_id"),
        db.Index("idx_count_passes_window", "started_at", "submitted_at"),
    )
    
    def __repr__(self):
        scope = f"{self.category}/{self.subcategory}" if self.subcategory else self.category
        return f"<CountPass {self.id[:8]}... {scope} [{self.status}]>"


class InventoryCountLine(db.Model):
    """Individual counted item within a pass."""
    
    __tablename__ = "inventory_count_lines"
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    count_pass_id = db.Column(db.String(36), db.ForeignKey("inventory_count_passes.id"), nullable=False)
    
    # Product identification
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"), nullable=False)
    sku = db.Column(db.String(50), nullable=False)  # Denormalized for audit trail
    barcode = db.Column(db.String(100))  # What was actually scanned (may differ from SKU)
    package_id = db.Column(db.String(100))  # Optional lot/package tracking
    
    # Count data
    counted_qty = db.Column(db.Integer, nullable=False)
    unit = db.Column(db.String(20), default="each")
    
    # Attribution and audit
    captured_at = db.Column(db.DateTime, default=datetime.utcnow)
    captured_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    confidence = db.Column(db.String(20), default="scanned")  # scanned | typed | corrected
    notes = db.Column(db.Text)
    
    # Relationships
    count_pass = db.relationship("InventoryCountPass", back_populates="lines")
    product = db.relationship("Product")
    captured_by = db.relationship("User")
    
    __table_args__ = (
        db.Index("idx_count_lines_pass", "count_pass_id"),
        db.Index("idx_count_lines_sku", "sku"),
        db.Index("idx_count_lines_product", "product_id"),
    )
    
    def __repr__(self):
        return f"<CountLine {self.sku} x{self.counted_qty}>"


class InventoryMovement(db.Model):
    """
    Sales, transfers, adjustments for variance reconciliation.
    
    Imported from Cova or entered manually.
    Used to adjust expected quantities during count windows.
    """
    
    __tablename__ = "inventory_movements"
    
    id = db.Column(db.Integer, primary_key=True)
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"), nullable=False)
    sku = db.Column(db.String(50), nullable=False)  # Denormalized for queries
    
    # Movement details
    movement_type = db.Column(db.String(30), nullable=False)
    # sale | refund | transfer_in | transfer_out | adjustment | shrinkage
    
    qty_delta = db.Column(db.Integer, nullable=False)  # Negative = decrease (sales)
    
    # Timing (critical for reconciliation window matching)
    occurred_at = db.Column(db.DateTime, nullable=False)
    
    # Source tracking
    source = db.Column(db.String(30), default="manual")  # cova | manual | import
    source_ref = db.Column(db.String(100))  # Transaction/receipt ID
    
    # Import tracking
    imported_at = db.Column(db.DateTime, default=datetime.utcnow)
    imported_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    # Relationships
    store = db.relationship("Store", backref="inventory_movements")
    product = db.relationship("Product")
    imported_by = db.relationship("User")
    
    __table_args__ = (
        db.Index("idx_movements_store_time", "store_id", "occurred_at"),
        db.Index("idx_movements_sku_time", "sku", "occurred_at"),
        db.Index("idx_movements_product", "product_id"),
    )
    
    def __repr__(self):
        return f"<Movement {self.movement_type} {self.sku} {self.qty_delta:+d}>"
