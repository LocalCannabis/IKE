"""
Sales Sync Service

Syncs sales data from cova_sales to inventory_movements for upstock computation.
This allows IKE to compute "what sold today" for the 10pm upstock pull list.
"""
from datetime import datetime, date, timedelta
from typing import Optional, Dict, Any
from sqlalchemy import text
from app import db
from app.models.inventory_count import InventoryMovement
from app.models.product import Product


class SalesSyncService:
    """
    Service to sync sales from cova_sales table to inventory_movements.
    
    The cova_sales table is populated by cova-bridge from Cova email exports.
    This service transforms those sales into movements for upstock computation.
    """
    
    STORE_ID_MAP = {
        # Map Cova store IDs to IKE store IDs
        'kingsway': 1,
        'Kingsway': 1,
        '1': 1,
        'fraser': 2,
        'Fraser': 2, 
        '2': 2,
    }

    @classmethod
    def sync_sales_to_movements(
        cls,
        store_id: int,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
        force_resync: bool = False
    ) -> Dict[str, Any]:
        """
        Sync sales from cova_sales to inventory_movements.
        
        Args:
            store_id: IKE store ID
            from_date: Start date (default: yesterday)
            to_date: End date (default: today)
            force_resync: If True, delete existing movements and re-sync
            
        Returns:
            Dict with sync stats
        """
        if from_date is None:
            from_date = date.today() - timedelta(days=1)
        if to_date is None:
            to_date = date.today()
            
        stats = {
            'from_date': from_date.isoformat(),
            'to_date': to_date.isoformat(),
            'store_id': store_id,
            'sales_found': 0,
            'movements_created': 0,
            'movements_skipped': 0,
            'products_not_found': [],
            'errors': []
        }
        
        try:
            # Get Cova store ID(s) for this IKE store
            cova_store_ids = cls._get_cova_store_ids(store_id)
            
            # Query cova_sales for the date range
            # Note: cova_sales might be in a different schema or via DB link
            sales_query = text("""
                SELECT 
                    transaction_id,
                    line_number,
                    store_id as cova_store_id,
                    transaction_date,
                    transaction_time,
                    product_sku,
                    product_name,
                    category,
                    quantity,
                    total_price
                FROM cova_sales
                WHERE transaction_date BETWEEN :from_date AND :to_date
                  AND store_id IN :cova_store_ids
                ORDER BY transaction_date, transaction_time
            """)
            
            result = db.session.execute(sales_query, {
                'from_date': from_date,
                'to_date': to_date,
                'cova_store_ids': tuple(cova_store_ids)
            })
            
            sales = result.fetchall()
            stats['sales_found'] = len(sales)
            
            if force_resync:
                # Delete existing movements in date range
                deleted = InventoryMovement.query.filter(
                    InventoryMovement.store_id == store_id,
                    db.func.date(InventoryMovement.occurred_at) >= from_date,
                    db.func.date(InventoryMovement.occurred_at) <= to_date,
                    InventoryMovement.source == 'cova_sync'
                ).delete(synchronize_session=False)
                stats['movements_deleted'] = deleted
            
            # Transform sales to movements
            for sale in sales:
                try:
                    movement = cls._sale_to_movement(sale, store_id)
                    if movement:
                        # Check if already exists
                        existing = InventoryMovement.query.filter_by(
                            store_id=store_id,
                            sku=movement.sku,
                            source_ref=movement.source_ref
                        ).first()
                        
                        if existing and not force_resync:
                            stats['movements_skipped'] += 1
                            continue
                            
                        db.session.add(movement)
                        stats['movements_created'] += 1
                    else:
                        # Product not found in catalog
                        if sale.product_sku and sale.product_sku not in stats['products_not_found']:
                            stats['products_not_found'].append(sale.product_sku)
                        stats['movements_skipped'] += 1
                except Exception as e:
                    stats['errors'].append(str(e))
                    
            db.session.commit()
            
        except Exception as e:
            db.session.rollback()
            stats['errors'].append(f"Sync failed: {str(e)}")
            
        return stats
    
    @classmethod
    def _get_cova_store_ids(cls, ike_store_id: int) -> list:
        """Map IKE store ID to Cova store ID(s)."""
        # Reverse lookup
        cova_ids = []
        for cova_id, ike_id in cls.STORE_ID_MAP.items():
            if ike_id == ike_store_id:
                cova_ids.append(cova_id)
        return cova_ids if cova_ids else [str(ike_store_id)]
    
    @classmethod
    def _sale_to_movement(cls, sale, store_id: int) -> Optional[InventoryMovement]:
        """Transform a cova_sales row to an InventoryMovement."""
        sku = sale.product_sku
        if not sku:
            return None
            
        # Look up product
        product = Product.query.filter(
            (Product.sku == sku) | (Product.cova_sku == sku)
        ).first()
        
        if not product:
            # Can't create movement without product_id (FK constraint)
            return None
        
        # Combine date + time
        occurred_at = datetime.combine(
            sale.transaction_date,
            sale.transaction_time or datetime.min.time()
        )
        
        # Create movement (sales are negative qty_delta)
        movement = InventoryMovement(
            store_id=store_id,
            product_id=product.id if product else None,
            sku=sku,
            movement_type='sale',
            qty_delta=-abs(sale.quantity),  # Negative = sold
            occurred_at=occurred_at,
            source='cova_sync',
            source_ref=f"{sale.transaction_id}:{sale.line_number}"
        )
        
        return movement
    
    @classmethod
    def get_sync_status(cls, store_id: int) -> Dict[str, Any]:
        """Get current sync status for a store."""
        # Find latest movement
        latest = InventoryMovement.query.filter_by(
            store_id=store_id,
            source='cova_sync'
        ).order_by(InventoryMovement.occurred_at.desc()).first()
        
        # Count today's movements
        today = date.today()
        today_count = InventoryMovement.query.filter(
            InventoryMovement.store_id == store_id,
            InventoryMovement.source == 'cova_sync',
            db.func.date(InventoryMovement.occurred_at) == today
        ).count()
        
        return {
            'store_id': store_id,
            'latest_movement_at': latest.occurred_at.isoformat() if latest else None,
            'today_movement_count': today_count,
            'synced': latest is not None
        }


# API endpoint for triggering sync
def register_sync_routes(bp):
    """Register sales sync routes on the upstock blueprint."""
    from flask import request, jsonify
    from flask_jwt_extended import jwt_required
    
    @bp.route("/sync/sales", methods=["POST"])
    @jwt_required()
    def sync_sales():
        """
        Sync sales from cova_sales to inventory_movements.
        
        POST /api/upstock/sync/sales
        {
            "store_id": 1,
            "from_date": "2025-12-23",  // optional
            "to_date": "2025-12-24",    // optional
            "force": false              // optional
        }
        """
        payload = request.get_json(silent=True) or {}
        
        store_id = payload.get("store_id")
        if not store_id:
            return jsonify({"error": "store_id required"}), 400
            
        from_date = None
        to_date = None
        
        if payload.get("from_date"):
            from_date = date.fromisoformat(payload["from_date"])
        if payload.get("to_date"):
            to_date = date.fromisoformat(payload["to_date"])
            
        force = payload.get("force", False)
        
        stats = SalesSyncService.sync_sales_to_movements(
            store_id=store_id,
            from_date=from_date,
            to_date=to_date,
            force_resync=force
        )
        
        return jsonify(stats)
    
    @bp.route("/sync/status", methods=["GET"])
    @jwt_required()
    def sync_status():
        """
        Get sales sync status for a store.
        
        GET /api/upstock/sync/status?store_id=1
        """
        store_id = request.args.get("store_id", type=int)
        if not store_id:
            return jsonify({"error": "store_id required"}), 400
            
        status = SalesSyncService.get_sync_status(store_id)
        return jsonify(status)
