#!/usr/bin/env python
"""
Initialize the database from the example cannabis_retail.db.

This script:
1. Copies the example database to instance/
2. Adds the new inventory count tables
3. Seeds dummy users and locations for dev

Usage:
    python init_db.py
"""
import os
import shutil
import sqlite3
from pathlib import Path

# Ensure we're in the backend directory
backend_dir = Path(__file__).parent
os.chdir(backend_dir)

# Paths
example_db = backend_dir.parent / "ExampleFormatsDoNotTreatAsLive" / "cannabis_retail.db"
instance_dir = backend_dir / "instance"
target_db = instance_dir / "inventory_count.db"


def _add_missing_columns(db_path: Path):
    """Add columns that our models need but the example DB doesn't have."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Check existing columns in users table
    cursor.execute("PRAGMA table_info(users)")
    existing_columns = {row[1] for row in cursor.fetchall()}
    
    # Add missing columns to users table
    users_additions = [
        ("pin", "VARCHAR(10)"),
        ("role", "VARCHAR(50) DEFAULT 'staff'"),
        ("is_active", "BOOLEAN DEFAULT 1"),
        ("default_store_id", "INTEGER"),
        ("created_at", "DATETIME"),
        ("last_login", "DATETIME"),
    ]
    
    for col_name, col_type in users_additions:
        if col_name not in existing_columns:
            try:
                cursor.execute(f"ALTER TABLE users ADD COLUMN {col_name} {col_type}")
                print(f"  + Added column users.{col_name}")
            except sqlite3.OperationalError as e:
                if "duplicate column" not in str(e).lower():
                    raise
    
    conn.commit()
    conn.close()


def main():
    print("=" * 60)
    print("Inventory Count Database Initialization")
    print("=" * 60)
    
    # Create instance directory
    instance_dir.mkdir(exist_ok=True)
    print(f"✓ Instance directory: {instance_dir}")
    
    # Copy example database
    if example_db.exists():
        if target_db.exists():
            response = input(f"Database already exists at {target_db}. Overwrite? [y/N]: ")
            if response.lower() != "y":
                print("Aborted.")
                return
        
        shutil.copy2(example_db, target_db)
        print(f"✓ Copied example database to: {target_db}")
    else:
        print(f"⚠ Example database not found at: {example_db}")
        print("  Will create empty database with schema only.")
    
    # Initialize Flask app and create tables
    print("\nInitializing Flask app...")
    
    # Set environment for local dev
    os.environ.setdefault("DATABASE_URL", f"sqlite:///{target_db}")
    os.environ.setdefault("JWT_SECRET_KEY", "dev-secret-change-in-production")
    
    from app import create_app, db
    app = create_app()
    
    with app.app_context():
        # Add any missing columns to existing tables (since we're extending the example DB)
        if target_db.exists():
            _add_missing_columns(target_db)
        
        # Create all tables (including new inventory count tables)
        db.create_all()
        print("✓ Database tables created")
        
        # Seed dev data
        seed_dev_data(db)
    
    print("\n" + "=" * 60)
    print("Database initialization complete!")
    print("=" * 60)
    print(f"\nDatabase location: {target_db}")
    print("\nTo start the server:")
    print("  cd backend")
    print("  pip install -r requirements.txt")
    print("  python run.py")
    print("\nDev login endpoint:")
    print("  POST /api/auth/dev-login")
    print('  {"email": "dev@example.com"}')


def seed_dev_data(db):
    """Seed dummy users and inventory locations for development."""
    from app.models.user import User, Store
    from app.models.inventory_count import InventoryLocation
    
    # Check if users already exist
    if User.query.first():
        print("✓ Users already exist, skipping user seed")
    else:
        # Create dev users with fake google_ids
        users = [
            User(google_id="dev_admin_001", email="admin@example.com", name="Admin User", role="admin", pin="1111"),
            User(google_id="dev_manager_001", email="manager@example.com", name="Manager User", role="manager", pin="2222"),
            User(google_id="dev_staff_001", email="staff@example.com", name="Staff User", role="staff", pin="3333"),
            User(google_id="dev_default_001", email="dev@example.com", name="Dev User", role="manager"),  # No PIN for quick dev login
        ]
        for user in users:
            db.session.add(user)
        db.session.commit()
        print(f"✓ Created {len(users)} dev users")
    
    # Get or create store (should exist from example DB)
    store = Store.query.first()
    if not store:
        store = Store(
            name="Kingsway Cannabis",
            code="KW01",
            address="1234 Kingsway Ave",
            is_active=True,
        )
        db.session.add(store)
        db.session.commit()
        print("✓ Created default store")
    else:
        print(f"✓ Using existing store: {store.name}")
    
    # Create inventory locations if they don't exist
    if not InventoryLocation.query.filter_by(store_id=store.id).first():
        locations = [
            InventoryLocation(
                store_id=store.id,
                code="FOH_DISPLAY",
                name="Front of House - Display",
                description="Main floor display cases and cabinets",
                sort_order=1,
            ),
            InventoryLocation(
                store_id=store.id,
                code="FOH_SHELF",
                name="Front of House - Shelving",
                description="Shelf units on sales floor",
                sort_order=2,
            ),
            InventoryLocation(
                store_id=store.id,
                code="BOH_STORAGE",
                name="Back of House - Storage",
                description="Main storage room",
                sort_order=3,
            ),
            InventoryLocation(
                store_id=store.id,
                code="BOH_FRIDGE",
                name="Back of House - Refrigerated",
                description="Temperature-controlled storage",
                sort_order=4,
            ),
        ]
        for loc in locations:
            db.session.add(loc)
        db.session.commit()
        print(f"✓ Created {len(locations)} inventory locations")
    else:
        print("✓ Inventory locations already exist")


if __name__ == "__main__":
    main()
