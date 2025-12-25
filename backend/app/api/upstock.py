"""
Upstock API - endpoints for nightly restocking workflow.
"""
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from sqlalchemy import func

from app import db
from app.models.user import User, Store
from app.models.product import Product
from app.models.inventory_count import InventoryMovement
from app.models.upstock import (
    UpstockBaseline,
    UpstockRun,
    UpstockRunLine,
    UpstockImport,
)

bp = Blueprint("upstock", __name__)


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def _serialize_run(run: UpstockRun, include_lines: bool = True) -> dict:
    """Serialize an upstock run to JSON."""
    data = {
        "id": run.id,
        "store_id": run.store_id,
        "location_id": run.location_id,
        "window_start_at": run.window_start_at.isoformat() if run.window_start_at else None,
        "window_end_at": run.window_end_at.isoformat() if run.window_end_at else None,
        "status": run.status,
        "created_by_user_id": run.created_by.email if run.created_by else None,
        "created_at": run.created_at.isoformat() if run.created_at else None,
        "completed_at": run.completed_at.isoformat() if run.completed_at else None,
        "notes": run.notes,
    }
    
    if include_lines:
        data["lines"] = [_serialize_line(line) for line in run.lines]
    
    return data


def _serialize_line(line: UpstockRunLine) -> dict:
    """Serialize an upstock run line to JSON."""
    return {
        "id": line.id,
        "run_id": line.run_id,
        "sku": line.sku,
        "product_name": line.product_name,
        "brand": line.brand,
        "category": line.category,
        "subcategory": line.subcategory,
        "cabinet": line.cabinet,
        "item_size": line.item_size,
        "sold_qty": line.sold_qty,
        "suggested_pull_qty": line.suggested_pull_qty,
        "pulled_qty": line.pulled_qty,
        "status": line.status,
        "boh_qty": line.boh_qty,
        "exception_reason": line.exception_reason,
        "updated_at": line.updated_at.isoformat() if line.updated_at else None,
        "updated_by_user_id": line.updated_by.email if line.updated_by else None,
    }


def _serialize_baseline(baseline: UpstockBaseline) -> dict:
    """Serialize a baseline to JSON."""
    return {
        "id": baseline.id,
        "store_id": baseline.store_id,
        "location_id": baseline.location_id,
        "sku": baseline.sku,
        "par_qty": baseline.par_qty,
        "cabinet": baseline.cabinet,
        "subcategory": baseline.subcategory,
        "updated_at": baseline.updated_at.isoformat() if baseline.updated_at else None,
        "updated_by_user_id": baseline.updated_by.email if baseline.updated_by else None,
    }


def _get_current_user() -> User:
    """Get the current authenticated user."""
    identity = get_jwt_identity()
    return User.query.filter_by(email=identity).first()


def _compute_run_lines(store_id: int, location_id: str, window_start: datetime, window_end: datetime) -> list[UpstockRunLine]:
    """
    Compute upstock run lines from inventory movements in the time window.
    
    For each SKU with sales in the window:
    - sold_qty = SUM(-qty_delta) for movement_type='sale'
    - suggested_pull_qty = sold_qty (v1 simple logic)
    """
    # Get sales aggregated by SKU in the window
    sales = db.session.query(
        InventoryMovement.sku,
        InventoryMovement.product_id,
        func.sum(-InventoryMovement.qty_delta).label("sold_qty")
    ).filter(
        InventoryMovement.store_id == store_id,
        InventoryMovement.movement_type == "sale",
        InventoryMovement.occurred_at >= window_start,
        InventoryMovement.occurred_at <= window_end
    ).group_by(
        InventoryMovement.sku,
        InventoryMovement.product_id
    ).having(
        func.sum(-InventoryMovement.qty_delta) > 0
    ).all()
    
    lines = []
    for sale in sales:
        # Get product details
        product = Product.query.get(sale.product_id) if sale.product_id else None
        
        line = UpstockRunLine(
            sku=sale.sku,
            product_id=sale.product_id,
            product_name=product.name if product else None,
            brand=product.brand if product else None,
            category=product.category if product else None,
            subcategory=product.subcategory if product else None,
            cabinet=product.category if product else None,  # Use category as cabinet for now
            item_size=product.item_size if product else None,
            sold_qty=int(sale.sold_qty),
            suggested_pull_qty=int(sale.sold_qty),  # v1: suggest = sold
            status="pending"
        )
        lines.append(line)
    
    return lines


# =============================================================================
# UPSTOCK RUNS
# =============================================================================

@bp.route("/runs/start", methods=["POST"])
@jwt_required()
def start_run():
    """
    Start a new upstock run.
    
    POST /api/upstock/runs/start
    {
        "store_id": 1,
        "location_id": "FOH_DISPLAY",
        "window_end_at": "2025-12-23T22:00:00Z",  // optional
        "notes": "End of day upstock"  // optional
    }
    """
    user = _get_current_user()
    if not user:
        return jsonify({"error": "User not found"}), 401
    
    payload = request.get_json(silent=True) or {}
    
    store_id = payload.get("store_id")
    location_id = payload.get("location_id")
    notes = payload.get("notes")
    
    if not store_id or not location_id:
        return jsonify({"error": "store_id and location_id required"}), 400
    
    # Find the last completed run to determine window_start
    last_run = UpstockRun.query.filter_by(
        store_id=store_id,
        location_id=location_id,
        status="completed"
    ).order_by(UpstockRun.completed_at.desc()).first()
    
    if last_run and last_run.completed_at:
        window_start = last_run.completed_at
    else:
        # Default to start of today
        now = datetime.utcnow()
        window_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    
    # Window end is now or provided time
    if payload.get("window_end_at"):
        window_end = datetime.fromisoformat(payload["window_end_at"].replace("Z", "+00:00")).replace(tzinfo=None)
    else:
        window_end = datetime.utcnow()
    
    # Create the run
    run = UpstockRun(
        store_id=store_id,
        location_id=location_id,
        window_start_at=window_start,
        window_end_at=window_end,
        status="in_progress",
        created_by_user_id=user.id,
        notes=notes
    )
    
    # Compute lines from movements
    lines = _compute_run_lines(store_id, location_id, window_start, window_end)
    run.lines = lines
    
    db.session.add(run)
    db.session.commit()
    
    return jsonify({
        "run": _serialize_run(run),
        "stats": run.stats
    }), 201


@bp.route("/runs", methods=["GET"])
@jwt_required()
def list_runs():
    """
    List upstock runs with optional filters.
    
    GET /api/upstock/runs?store_id=1&location_id=FOH_DISPLAY&status=in_progress&limit=50
    """
    store_id = request.args.get("store_id", type=int)
    location_id = request.args.get("location_id")
    status = request.args.get("status")
    limit = request.args.get("limit", 50, type=int)
    
    if not store_id:
        return jsonify({"error": "store_id required"}), 400
    
    query = UpstockRun.query.filter_by(store_id=store_id)
    
    if location_id:
        query = query.filter_by(location_id=location_id)
    if status:
        query = query.filter_by(status=status)
    
    runs = query.order_by(UpstockRun.created_at.desc()).limit(limit).all()
    
    return jsonify({
        "runs": [_serialize_run(r, include_lines=False) for r in runs],
        "count": len(runs)
    })


@bp.route("/runs/<run_id>", methods=["GET"])
@jwt_required()
def get_run(run_id: str):
    """
    Get detailed run with all lines.
    
    GET /api/upstock/runs/{run_id}
    """
    run = UpstockRun.query.get(run_id)
    if not run:
        return jsonify({"error": "Run not found"}), 404
    
    return jsonify({
        "run": _serialize_run(run),
        "stats": run.stats
    })


@bp.route("/runs/<run_id>/lines/<sku>", methods=["PATCH"])
@jwt_required()
def update_line(run_id: str, sku: str):
    """
    Update a run line with pulled quantity and status.
    
    PATCH /api/upstock/runs/{run_id}/lines/{sku}
    {
        "pulled_qty": 5,
        "status": "done",
        "exception_reason": null
    }
    """
    user = _get_current_user()
    if not user:
        return jsonify({"error": "User not found"}), 401
    
    run = UpstockRun.query.get(run_id)
    if not run:
        return jsonify({"error": "Run not found"}), 404
    
    if run.status != "in_progress":
        return jsonify({"error": "Run is not in progress"}), 400
    
    # Find the line by SKU
    line = UpstockRunLine.query.filter_by(run_id=run_id, sku=sku).first()
    if not line:
        return jsonify({"error": "Line not found"}), 404
    
    payload = request.get_json(silent=True) or {}
    
    if "pulled_qty" in payload:
        line.pulled_qty = payload["pulled_qty"]
    if "status" in payload:
        if payload["status"] not in ["pending", "done", "skipped", "exception"]:
            return jsonify({"error": "Invalid status"}), 400
        line.status = payload["status"]
    if "exception_reason" in payload:
        line.exception_reason = payload["exception_reason"]
    
    line.updated_by_user_id = user.id
    line.updated_at = datetime.utcnow()
    
    db.session.commit()
    
    return jsonify({
        "line": _serialize_line(line)
    })


@bp.route("/runs/<run_id>/complete", methods=["POST"])
@jwt_required()
def complete_run(run_id: str):
    """
    Mark run as completed.
    
    POST /api/upstock/runs/{run_id}/complete
    {
        "validate_all_resolved": false  // optional
    }
    """
    user = _get_current_user()
    if not user:
        return jsonify({"error": "User not found"}), 401
    
    run = UpstockRun.query.get(run_id)
    if not run:
        return jsonify({"error": "Run not found"}), 404
    
    if run.status != "in_progress":
        return jsonify({"error": "Run is not in progress"}), 400
    
    payload = request.get_json(silent=True) or {}
    
    # Check if all lines are resolved
    pending_count = sum(1 for l in run.lines if l.status == "pending")
    if payload.get("validate_all_resolved") and pending_count > 0:
        return jsonify({
            "error": f"{pending_count} lines still pending",
            "pending_count": pending_count
        }), 400
    
    run.status = "completed"
    run.completed_at = datetime.utcnow()
    run.completed_by_user_id = user.id
    
    db.session.commit()
    
    return jsonify({
        "run": _serialize_run(run, include_lines=False),
        "stats": run.stats
    })


@bp.route("/runs/<run_id>/abandon", methods=["POST"])
@jwt_required()
def abandon_run(run_id: str):
    """
    Mark run as abandoned.
    
    POST /api/upstock/runs/{run_id}/abandon
    {
        "reason": "Staff shortage"
    }
    """
    user = _get_current_user()
    if not user:
        return jsonify({"error": "User not found"}), 401
    
    run = UpstockRun.query.get(run_id)
    if not run:
        return jsonify({"error": "Run not found"}), 404
    
    if run.status != "in_progress":
        return jsonify({"error": "Run is not in progress"}), 400
    
    payload = request.get_json(silent=True) or {}
    reason = payload.get("reason", "")
    
    run.status = "abandoned"
    run.completed_at = datetime.utcnow()
    run.completed_by_user_id = user.id
    
    # Append reason to notes
    if reason:
        if run.notes:
            run.notes = f"{run.notes}\nAbandoned: {reason}"
        else:
            run.notes = f"Abandoned: {reason}"
    
    db.session.commit()
    
    return jsonify({
        "run": _serialize_run(run, include_lines=False)
    })


# =============================================================================
# BASELINES (PAR LEVELS)
# =============================================================================

@bp.route("/baselines", methods=["GET"])
@jwt_required()
def list_baselines():
    """
    List baselines for a store/location.
    
    GET /api/upstock/baselines?store_id=1&location_id=FOH_DISPLAY
    """
    store_id = request.args.get("store_id", type=int)
    location_id = request.args.get("location_id")
    
    if not store_id:
        return jsonify({"error": "store_id required"}), 400
    
    query = UpstockBaseline.query.filter_by(store_id=store_id)
    
    if location_id:
        query = query.filter_by(location_id=location_id)
    
    baselines = query.all()
    
    return jsonify({
        "baselines": [_serialize_baseline(b) for b in baselines],
        "count": len(baselines)
    })


@bp.route("/baselines", methods=["PUT"])
@jwt_required()
def update_baselines():
    """
    Bulk create or update baselines.
    
    PUT /api/upstock/baselines
    {
        "store_id": 1,
        "location_id": "FOH_DISPLAY",
        "baselines": [
            {"sku": "1234567", "par_qty": 10, "cabinet": "Pre-Rolls", "subcategory": "Sativa"}
        ]
    }
    """
    user = _get_current_user()
    if not user:
        return jsonify({"error": "User not found"}), 401
    
    payload = request.get_json(silent=True) or {}
    
    store_id = payload.get("store_id")
    location_id = payload.get("location_id")
    baselines_data = payload.get("baselines", [])
    
    if not store_id or not location_id:
        return jsonify({"error": "store_id and location_id required"}), 400
    
    created = 0
    updated = 0
    
    for item in baselines_data:
        sku = item.get("sku")
        if not sku:
            continue
        
        # Find existing or create new
        baseline = UpstockBaseline.query.filter_by(
            store_id=store_id,
            location_id=location_id,
            sku=sku
        ).first()
        
        if baseline:
            baseline.par_qty = item.get("par_qty", baseline.par_qty)
            baseline.cabinet = item.get("cabinet", baseline.cabinet)
            baseline.subcategory = item.get("subcategory", baseline.subcategory)
            baseline.updated_by_user_id = user.id
            updated += 1
        else:
            # Try to find product
            product = Product.query.filter_by(sku=sku).first()
            
            baseline = UpstockBaseline(
                store_id=store_id,
                location_id=location_id,
                sku=sku,
                product_id=product.id if product else None,
                par_qty=item.get("par_qty", 0),
                cabinet=item.get("cabinet"),
                subcategory=item.get("subcategory"),
                updated_by_user_id=user.id
            )
            db.session.add(baseline)
            created += 1
    
    db.session.commit()
    
    return jsonify({
        "message": f"Updated {updated} and created {created} baselines",
        "created": created,
        "updated": updated
    })


# =============================================================================
# IMPORTS (FOR CSV PROCESSING)
# =============================================================================

@bp.route("/imports/process", methods=["POST"])
@jwt_required()
def process_imports():
    """
    Manually trigger processing of pending imports (for testing).
    
    POST /api/upstock/imports/process
    {
        "store_id": 1,
        "days_back": 2
    }
    """
    # This is a placeholder - actual email processing would be in a separate service
    payload = request.get_json(silent=True) or {}
    
    store_id = payload.get("store_id")
    if not store_id:
        return jsonify({"error": "store_id required"}), 400
    
    # Get pending imports
    imports = UpstockImport.query.filter_by(
        store_id=store_id,
        status="pending"
    ).all()
    
    processed = 0
    failed = 0
    
    for imp in imports:
        # TODO: Actually process the import
        # For now, just mark as processed
        imp.status = "processed"
        imp.processed_at = datetime.utcnow()
        processed += 1
    
    db.session.commit()
    
    return jsonify({
        "processed_count": processed,
        "failed_count": failed,
        "imports": [
            {
                "id": imp.id,
                "store_id": imp.store_id,
                "import_type": imp.import_type,
                "received_at": imp.received_at.isoformat() if imp.received_at else None,
                "processed_at": imp.processed_at.isoformat() if imp.processed_at else None,
                "status": imp.status,
                "rows_processed": imp.rows_processed
            }
            for imp in imports
        ]
    })


# =============================================================================
# SALES SYNC (from cova_sales to inventory_movements)
# =============================================================================

# Register sales sync routes
from app.services.sales_sync import register_sync_routes
register_sync_routes(bp)
