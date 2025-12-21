"""
User model - simplified for dev (no Google OAuth yet).
Will integrate with JFK auth in MK5.
"""
from datetime import datetime
from app import db


class User(db.Model):
    """Simplified user for dev/testing. MK5 will use JFK's Google OAuth."""
    
    __tablename__ = "users"
    
    id = db.Column(db.Integer, primary_key=True)
    google_id = db.Column(db.String(100), unique=True, nullable=False)  # From cannabis_retail.db schema
    email = db.Column(db.String(255), unique=True, nullable=False)
    name = db.Column(db.String(255), nullable=False)
    avatar_url = db.Column(db.Text)  # From cannabis_retail.db schema
    pin = db.Column(db.String(10))  # Simple PIN for tablet login during dev
    role = db.Column(db.String(50), default="staff")  # staff | manager | admin
    is_active = db.Column(db.Boolean, default=True)
    default_store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    last_login = db.Column(db.DateTime)
    
    # Relationships
    default_store = db.relationship("Store", foreign_keys=[default_store_id])
    
    def __repr__(self):
        return f"<User {self.email}>"
    
    def can_count(self) -> bool:
        """Staff and above can count inventory."""
        return self.role in ("staff", "manager", "admin")
    
    def can_reconcile(self) -> bool:
        """Only managers and admins can reconcile."""
        return self.role in ("manager", "admin")
    
    def can_admin(self) -> bool:
        """Only admins can manage users/locations."""
        return self.role == "admin"


class Store(db.Model):
    """Store model - mirrors JFK structure for future integration."""
    
    __tablename__ = "stores"
    
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(255), nullable=False)
    code = db.Column(db.String(10), unique=True, nullable=False)
    address = db.Column(db.Text)
    phone = db.Column(db.String(20))
    email = db.Column(db.String(100))
    license_number = db.Column(db.String(50))
    cova_location_id = db.Column(db.String(100))
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def __repr__(self):
        return f"<Store {self.name}>"
