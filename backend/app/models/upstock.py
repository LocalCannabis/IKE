"""
Upstock models - for nightly restocking workflow.
Computes pull lists from sales data and tracks fulfillment.
"""
from datetime import datetime
import uuid
from app import db


def generate_uuid():
    return str(uuid.uuid4())


class UpstockBaseline(db.Model):
    """
    Par levels (target stock) for FOH locations.
    Used for reporting and future par-aware suggestions.
    """
    
    __tablename__ = "upstock_baselines"
    
    id = db.Column(db.Integer, primary_key=True)
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    location_id = db.Column(db.String(50), nullable=False)  # FOH_DISPLAY, etc.
    
    # Product reference
    sku = db.Column(db.String(50), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"))
    
    # Classification (for grouping)
    cabinet = db.Column(db.String(100))  # Menu category grouping
    subcategory = db.Column(db.String(100))
    
    # Par level
    par_qty = db.Column(db.Integer, nullable=False, default=0)
    
    # Audit
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    updated_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    # Relationships
    store = db.relationship("Store", backref="upstock_baselines")
    product = db.relationship("Product")
    updated_by = db.relationship("User")
    
    __table_args__ = (
        db.UniqueConstraint("store_id", "location_id", "sku", name="unique_baseline_sku"),
        db.Index("idx_baselines_store_location", "store_id", "location_id"),
    )
    
    def __repr__(self):
        return f"<UpstockBaseline {self.sku} par={self.par_qty}>"


class UpstockRun(db.Model):
    """
    A single upstock session - computing what needs to be pulled and tracking fulfillment.
    """
    
    __tablename__ = "upstock_runs"
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    location_id = db.Column(db.String(50), nullable=False)  # Target FOH location
    
    # Time window for sales computation
    window_start_at = db.Column(db.DateTime, nullable=False)  # Last run completed_at or start of day
    window_end_at = db.Column(db.DateTime, nullable=False)    # When this run was started
    
    # Run lifecycle
    status = db.Column(db.String(30), default="in_progress")
    # in_progress -> completed | abandoned
    
    # Attribution
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    completed_at = db.Column(db.DateTime)
    completed_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    notes = db.Column(db.Text)
    
    # Relationships
    store = db.relationship("Store", backref="upstock_runs")
    created_by = db.relationship("User", foreign_keys=[created_by_user_id])
    completed_by = db.relationship("User", foreign_keys=[completed_by_user_id])
    lines = db.relationship("UpstockRunLine", back_populates="run", cascade="all, delete-orphan")
    
    __table_args__ = (
        db.Index("idx_upstock_runs_store_status", "store_id", "status"),
        db.Index("idx_upstock_runs_store_location", "store_id", "location_id"),
    )
    
    def __repr__(self):
        return f"<UpstockRun {self.id[:8]}... [{self.status}]>"
    
    @property
    def stats(self):
        """Compute run statistics."""
        total = len(self.lines)
        if total == 0:
            return {
                "total": 0,
                "done": 0,
                "pending": 0,
                "skipped": 0,
                "exceptions": 0,
                "completion_rate": 0.0
            }
        
        done = sum(1 for l in self.lines if l.status == "done")
        pending = sum(1 for l in self.lines if l.status == "pending")
        skipped = sum(1 for l in self.lines if l.status == "skipped")
        exceptions = sum(1 for l in self.lines if l.status == "exception")
        
        return {
            "total": total,
            "done": done,
            "pending": pending,
            "skipped": skipped,
            "exceptions": exceptions,
            "completion_rate": round((done + skipped) / total * 100, 1) if total > 0 else 0.0
        }


class UpstockRunLine(db.Model):
    """
    Individual line item in an upstock run.
    Tracks sold qty, suggested pull, actual pulled, and status.
    """
    
    __tablename__ = "upstock_run_lines"
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    run_id = db.Column(db.String(36), db.ForeignKey("upstock_runs.id"), nullable=False)
    
    # Product identification
    sku = db.Column(db.String(50), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"))
    
    # Denormalized product info for display
    product_name = db.Column(db.String(200))
    brand = db.Column(db.String(100))
    category = db.Column(db.String(100))
    subcategory = db.Column(db.String(100))
    cabinet = db.Column(db.String(100))  # Menu grouping
    item_size = db.Column(db.String(50))
    
    # Computed quantities
    sold_qty = db.Column(db.Integer, nullable=False, default=0)  # Units sold in window
    suggested_pull_qty = db.Column(db.Integer, nullable=False, default=0)  # Suggested to pull
    boh_qty = db.Column(db.Integer)  # Back-of-house available (if known)
    
    # Fulfillment
    pulled_qty = db.Column(db.Integer)  # Actual units pulled by staff
    status = db.Column(db.String(30), default="pending")
    # pending -> done | skipped | exception
    
    exception_reason = db.Column(db.Text)  # "BOH short", "Already stocked", etc.
    
    # Audit
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    updated_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    # Relationships
    run = db.relationship("UpstockRun", back_populates="lines")
    product = db.relationship("Product")
    updated_by = db.relationship("User")
    
    __table_args__ = (
        db.Index("idx_upstock_lines_run", "run_id"),
        db.Index("idx_upstock_lines_sku", "sku"),
        db.Index("idx_upstock_lines_status", "status"),
    )
    
    def __repr__(self):
        return f"<UpstockRunLine {self.sku} sold={self.sold_qty} pulled={self.pulled_qty}>"


class UpstockImport(db.Model):
    """
    Tracks email/CSV imports from Cova for audit and debugging.
    """
    
    __tablename__ = "upstock_imports"
    
    id = db.Column(db.String(36), primary_key=True, default=generate_uuid)
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    
    # Import metadata
    import_type = db.Column(db.String(50), nullable=False)  # itemized_sales, inventory_snapshot
    source = db.Column(db.String(50), default="email")  # email, manual, api
    filename = db.Column(db.String(255))
    
    # Processing status
    received_at = db.Column(db.DateTime, nullable=False)
    processed_at = db.Column(db.DateTime)
    status = db.Column(db.String(30), default="pending")  # pending, processed, failed
    
    # Results
    rows_processed = db.Column(db.Integer, default=0)
    rows_failed = db.Column(db.Integer, default=0)
    error_message = db.Column(db.Text)
    
    # Relationships
    store = db.relationship("Store", backref="upstock_imports")
    
    __table_args__ = (
        db.Index("idx_upstock_imports_store_status", "store_id", "status"),
    )
    
    def __repr__(self):
        return f"<UpstockImport {self.import_type} [{self.status}]>"
