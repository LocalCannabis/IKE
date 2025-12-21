"""
Product and InventoryItem models - mirrors JFK structure.
These will be read from the existing cannabis_retail.db data.
"""
from datetime import datetime
from app import db


class Product(db.Model):
    """Universal product catalog (read from existing data)."""
    
    __tablename__ = "products"
    
    id = db.Column(db.Integer, primary_key=True)
    sku = db.Column(db.String(50), nullable=False, index=True)
    cova_sku = db.Column(db.String(50), unique=True)
    name = db.Column(db.String(255), nullable=False)
    brand = db.Column(db.String(100))
    category = db.Column(db.String(50))
    subcategory = db.Column(db.String(50))
    
    # Cannabis attributes
    dominance = db.Column(db.String(20))
    thc_min = db.Column(db.Float)
    thc_max = db.Column(db.Float)
    thc_uom = db.Column(db.String(10))
    cbd_min = db.Column(db.Float)
    cbd_max = db.Column(db.Float)
    cbd_uom = db.Column(db.String(10))
    terpene_1_type = db.Column(db.String(50))
    terpene_2_type = db.Column(db.String(50))
    terpene_3_type = db.Column(db.String(50))
    cannabinoid_profile = db.Column(db.JSON, default=list)
    
    # Product format
    format = db.Column(db.String(100))
    item_count = db.Column(db.Integer)
    item_size = db.Column(db.Float)
    item_size_uom = db.Column(db.String(10))
    
    # Descriptions
    short_description = db.Column(db.Text)
    long_description = db.Column(db.Text)
    enriched_description = db.Column(db.Text)
    
    is_active = db.Column(db.Boolean, default=True)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    inventory_items = db.relationship("InventoryItem", back_populates="product")
    
    __table_args__ = (
        db.Index("idx_products_category", "category", "subcategory"),
        db.Index("idx_products_brand", "brand"),
    )
    
    def __repr__(self):
        return f"<Product {self.name}>"


class InventoryItem(db.Model):
    """Store-specific inventory (read from existing data)."""
    
    __tablename__ = "inventory_items"
    
    id = db.Column(db.Integer, primary_key=True)
    store_id = db.Column(db.Integer, db.ForeignKey("stores.id"), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey("products.id"), nullable=False)
    cova_item_id = db.Column(db.String(100))
    
    # Quantities
    current_quantity = db.Column(db.Integer, default=0)
    reserved_quantity = db.Column(db.Integer, default=0)
    available_quantity = db.Column(db.Integer, default=0)
    
    # Pricing
    cost_price = db.Column(db.Float)
    retail_price = db.Column(db.Float)
    
    # Management
    restocking = db.Column(db.Boolean, default=True)
    store_stock = db.Column(db.Boolean, default=True)
    out_of_stock_since = db.Column(db.DateTime)
    last_sync = db.Column(db.DateTime)
    cabinet = db.Column(db.String(100))
    card = db.Column(db.String(100))
    
    # Display overrides (from JFK)
    display_name = db.Column(db.String(255))
    display_brand = db.Column(db.String(255))
    display_dominance = db.Column(db.String(50))
    display_format = db.Column(db.String(100))
    display_retail_format = db.Column(db.String(100))
    display_flare = db.Column(db.String(100))
    
    # Workflow
    dirty = db.Column(db.Boolean, default=False)
    dirty_reasons = db.Column(db.Text)
    card_approved = db.Column(db.Boolean, default=False)
    content_version = db.Column(db.Integer, default=1)
    approved_version = db.Column(db.Integer, default=0)
    last_printed_at = db.Column(db.DateTime)
    last_updated_by = db.Column(db.Integer, db.ForeignKey("users.id"))
    
    # Relationships
    store = db.relationship("Store", backref="inventory_items")
    product = db.relationship("Product", back_populates="inventory_items")
    
    __table_args__ = (
        db.Index("idx_inventory_store_product", "store_id", "product_id"),
        db.UniqueConstraint("store_id", "product_id", name="unique_store_product"),
    )
    
    def __repr__(self):
        return f"<InventoryItem {self.product_id} @ Store {self.store_id}>"
