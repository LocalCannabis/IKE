"""
Inventory Count API - core counting endpoints for the tablet app.
"""
from datetime import datetime
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from sqlalchemy import func, and_, or_

from app import db
from app.models.user import User, Store
from app.models.product import Product, InventoryItem
from app.models.inventory_count import (
    InventoryLocation,
    InventoryCountSession,
    InventoryCountPass,
    InventoryCountLine,
    InventoryMovement,
)

bp = Blueprint("count", __name__)


# =============================================================================
# LOCATIONS
# =============================================================================

@bp.route("/locations", methods=["GET"])
@jwt_required()
def list_locations():
    """
    List inventory locations for a store.
    
    GET /api/count/locations?store_id=1
    """
    store_id = request.args.get("store_id", type=int)
    
    if not store_id:
        return jsonify({"error": "store_id required"}), 400
    
    locations = InventoryLocation.query.filter_by(
        store_id=store_id,
        is_active=True
    ).order_by(InventoryLocation.sort_order).all()
    
    return jsonify({
        "locations": [_serialize_location(loc) for loc in locations],
    })


@bp.route("/locations", methods=["POST"])
@jwt_required()
def create_location():
    """
    Create a new inventory location.
    
    POST /api/count/locations
    {
        "store_id": 1,
        "code": "FOH_DISPLAY",
        "name": "Front of House - Display",
        "description": "Main floor display cases"
    }
    """
    payload = request.get_json(silent=True) or {}
    
    store_id = payload.get("store_id")
    code = str(payload.get("code", "")).strip().upper()
    name = str(payload.get("name", "")).strip()
    description = str(payload.get("description", "")).strip() or None
    
    if not all([store_id, code, name]):
        return jsonify({"error": "store_id, code, and name required"}), 400
    
    # Check for duplicate
    existing = InventoryLocation.query.filter_by(store_id=store_id, code=code).first()
    if existing:
        return jsonify({"error": f"Location '{code}' already exists"}), 409
    
    location = InventoryLocation(
        store_id=store_id,
        code=code,
        name=name,
        description=description,
    )
    db.session.add(location)
    db.session.commit()
    
    return jsonify(_serialize_location(location)), 201


# =============================================================================
# SESSIONS
# =============================================================================

@bp.route("/sessions", methods=["GET"])
@jwt_required()
def list_sessions():
    """
    List count sessions.
    
    GET /api/count/sessions?store_id=1&status=in_progress
    """
    store_id = request.args.get("store_id", type=int)
    status = request.args.get("status")
    
    query = InventoryCountSession.query
    
    if store_id:
        query = query.filter(InventoryCountSession.store_id == store_id)
    
    if status:
        query = query.filter(InventoryCountSession.status == status)
    
    query = query.order_by(InventoryCountSession.created_at.desc())
    
    sessions = query.limit(50).all()
    
    return jsonify({
        "sessions": [_serialize_session(s) for s in sessions],
    })


@bp.route("/sessions", methods=["POST"])
@jwt_required()
def create_session():
    """
    Create a new count session.
    
    POST /api/count/sessions
    {
        "store_id": 1,
        "notes": "Monthly inventory count"
    }
    """
    user_id = int(get_jwt_identity())
    payload = request.get_json(silent=True) or {}
    
    store_id = payload.get("store_id")
    notes = str(payload.get("notes", "")).strip() or None
    
    if not store_id:
        return jsonify({"error": "store_id required"}), 400
    
    # Verify store exists
    store = Store.query.get(store_id)
    if not store:
        return jsonify({"error": "Store not found"}), 404
    
    session = InventoryCountSession(
        store_id=store_id,
        created_by_user_id=user_id,
        notes=notes,
        expected_snapshot_at=datetime.utcnow(),
    )
    db.session.add(session)
    db.session.commit()
    
    return jsonify(_serialize_session(session)), 201


@bp.route("/sessions/<session_id>", methods=["GET"])
@jwt_required()
def get_session(session_id: str):
    """Get session details with passes summary."""
    session = InventoryCountSession.query.get(session_id)
    
    if not session:
        return jsonify({"error": "Session not found"}), 404
    
    return jsonify(_serialize_session(session, include_passes=True))


@bp.route("/sessions/<session_id>/start", methods=["POST"])
@jwt_required()
def start_session(session_id: str):
    """Mark session as in_progress."""
    session = InventoryCountSession.query.get(session_id)
    
    if not session:
        return jsonify({"error": "Session not found"}), 404
    
    if session.status != "draft":
        return jsonify({"error": f"Cannot start session in '{session.status}' status"}), 400
    
    session.status = "in_progress"
    db.session.commit()
    
    return jsonify(_serialize_session(session))


@bp.route("/sessions/<session_id>/submit", methods=["POST"])
@jwt_required()
def submit_session(session_id: str):
    """Mark session counting as complete (ready for reconciliation)."""
    session = InventoryCountSession.query.get(session_id)
    
    if not session:
        return jsonify({"error": "Session not found"}), 404
    
    if session.status != "in_progress":
        return jsonify({"error": f"Cannot submit session in '{session.status}' status"}), 400
    
    # Check all passes are submitted
    open_passes = InventoryCountPass.query.filter_by(
        session_id=session_id,
        status="in_progress"
    ).count()
    
    if open_passes > 0:
        return jsonify({"error": f"{open_passes} passes still in progress"}), 400
    
    session.status = "submitted"
    db.session.commit()
    
    return jsonify(_serialize_session(session))


# =============================================================================
# PASSES
# =============================================================================

@bp.route("/sessions/<session_id>/passes", methods=["GET"])
@jwt_required()
def list_passes(session_id: str):
    """List all passes for a session."""
    passes = InventoryCountPass.query.filter_by(
        session_id=session_id
    ).order_by(InventoryCountPass.started_at.desc()).all()
    
    return jsonify({
        "passes": [_serialize_pass(p) for p in passes],
    })


@bp.route("/sessions/<session_id>/passes", methods=["POST"])
@jwt_required()
def create_pass(session_id: str):
    """
    Start a new counting pass.
    
    POST /api/count/sessions/{session_id}/passes
    {
        "location_id": 1,
        "category": "Flower",
        "subcategory": "Dried Flower",
        "device_id": "TABLET-001",
        "scan_mode": "scanner"
    }
    """
    user_id = int(get_jwt_identity())
    payload = request.get_json(silent=True) or {}
    
    session = InventoryCountSession.query.get(session_id)
    if not session:
        return jsonify({"error": "Session not found"}), 404
    
    if session.status not in ("draft", "in_progress"):
        return jsonify({"error": f"Cannot add passes to '{session.status}' session"}), 400
    
    location_id = payload.get("location_id")
    if not location_id:
        return jsonify({"error": "location_id required"}), 400
    
    location = InventoryLocation.query.get(location_id)
    if not location or location.store_id != session.store_id:
        return jsonify({"error": "Invalid location"}), 400
    
    # Auto-start session if still draft
    if session.status == "draft":
        session.status = "in_progress"
    
    count_pass = InventoryCountPass(
        session_id=session_id,
        location_id=location_id,
        category=str(payload.get("category", "")).strip() or None,
        subcategory=str(payload.get("subcategory", "")).strip() or None,
        started_by_user_id=user_id,
        device_id=str(payload.get("device_id", "")).strip() or None,
        scan_mode=str(payload.get("scan_mode", "scanner")).strip(),
    )
    db.session.add(count_pass)
    db.session.commit()
    
    return jsonify(_serialize_pass(count_pass)), 201


@bp.route("/passes/<pass_id>", methods=["GET"])
@jwt_required()
def get_pass(pass_id: str):
    """Get pass details with lines."""
    count_pass = InventoryCountPass.query.get(pass_id)
    
    if not count_pass:
        return jsonify({"error": "Pass not found"}), 404
    
    return jsonify(_serialize_pass(count_pass, include_lines=True))


@bp.route("/passes/<pass_id>/submit", methods=["POST"])
@jwt_required()
def submit_pass(pass_id: str):
    """Complete a counting pass (sets submitted_at timestamp)."""
    user_id = int(get_jwt_identity())
    count_pass = InventoryCountPass.query.get(pass_id)
    
    if not count_pass:
        return jsonify({"error": "Pass not found"}), 404
    
    if count_pass.status != "in_progress":
        return jsonify({"error": f"Cannot submit pass in '{count_pass.status}' status"}), 400
    
    count_pass.status = "submitted"
    count_pass.submitted_at = datetime.utcnow()
    count_pass.submitted_by_user_id = user_id
    db.session.commit()
    
    return jsonify(_serialize_pass(count_pass))


@bp.route("/passes/<pass_id>/void", methods=["POST"])
@jwt_required()
def void_pass(pass_id: str):
    """Void/cancel a pass."""
    count_pass = InventoryCountPass.query.get(pass_id)
    
    if not count_pass:
        return jsonify({"error": "Pass not found"}), 404
    
    if count_pass.status == "voided":
        return jsonify({"error": "Pass already voided"}), 400
    
    count_pass.status = "voided"
    db.session.commit()
    
    return jsonify(_serialize_pass(count_pass))


# =============================================================================
# LINES
# =============================================================================

@bp.route("/passes/<pass_id>/lines", methods=["GET"])
@jwt_required()
def list_lines(pass_id: str):
    """List all lines for a pass."""
    lines = InventoryCountLine.query.filter_by(
        count_pass_id=pass_id
    ).order_by(InventoryCountLine.captured_at.desc()).all()
    
    return jsonify({
        "lines": [_serialize_line(ln) for ln in lines],
    })


@bp.route("/passes/<pass_id>/lines", methods=["POST"])
@jwt_required()
def add_line(pass_id: str):
    """
    Add or update a count line.
    
    If a line for the same SKU already exists in this pass,
    the quantity is ADDED (incremented), not replaced.
    
    POST /api/count/passes/{pass_id}/lines
    {
        "barcode": "SKU123",      // What was scanned
        "counted_qty": 1,         // Usually 1 per scan
        "package_id": "LOT-001",  // Optional
        "confidence": "scanned",  // scanned | typed | corrected
        "notes": ""
    }
    """
    user_id = int(get_jwt_identity())
    payload = request.get_json(silent=True) or {}
    
    count_pass = InventoryCountPass.query.get(pass_id)
    if not count_pass:
        return jsonify({"error": "Pass not found"}), 404
    
    if count_pass.status != "in_progress":
        return jsonify({"error": f"Cannot add lines to '{count_pass.status}' pass"}), 400
    
    barcode = str(payload.get("barcode", "")).strip()
    if not barcode:
        return jsonify({"error": "barcode required"}), 400
    
    # Look up product
    product = Product.query.filter(
        (Product.sku == barcode) | (Product.cova_sku == barcode)
    ).first()
    
    if not product:
        return jsonify({"error": "Product not found", "barcode": barcode}), 404
    
    # Validate category/subcategory if pass has scope
    if count_pass.category and product.category:
        if product.category.lower() != count_pass.category.lower():
            return jsonify({
                "error": "Product category mismatch",
                "expected": count_pass.category,
                "got": product.category,
                "product": product.name,
            }), 400
    
    if count_pass.subcategory and product.subcategory:
        if product.subcategory.lower() != count_pass.subcategory.lower():
            return jsonify({
                "error": "Product subcategory mismatch",
                "expected": count_pass.subcategory,
                "got": product.subcategory,
                "product": product.name,
            }), 400
    
    counted_qty = int(payload.get("counted_qty", 1))
    package_id = str(payload.get("package_id", "")).strip() or None
    confidence = str(payload.get("confidence", "scanned")).strip()
    notes = str(payload.get("notes", "")).strip() or None
    
    # Check for existing line with same SKU in this pass
    existing_line = InventoryCountLine.query.filter_by(
        count_pass_id=pass_id,
        sku=product.sku,
    ).first()
    
    if existing_line:
        # Increment existing quantity
        existing_line.counted_qty += counted_qty
        existing_line.captured_at = datetime.utcnow()
        existing_line.captured_by_user_id = user_id
        if notes:
            existing_line.notes = notes
        db.session.commit()
        
        return jsonify({
            "line": _serialize_line(existing_line),
            "incremented": True,
            "previous_qty": existing_line.counted_qty - counted_qty,
        })
    
    # Create new line
    line = InventoryCountLine(
        count_pass_id=pass_id,
        product_id=product.id,
        sku=product.sku,
        barcode=barcode,
        package_id=package_id,
        counted_qty=counted_qty,
        captured_by_user_id=user_id,
        confidence=confidence,
        notes=notes,
    )
    db.session.add(line)
    db.session.commit()
    
    return jsonify({
        "line": _serialize_line(line),
        "incremented": False,
        "product": {
            "id": product.id,
            "name": product.name,
            "brand": product.brand,
            "category": product.category,
            "subcategory": product.subcategory,
        },
    }), 201


@bp.route("/lines/<line_id>", methods=["PUT"])
@jwt_required()
def update_line(line_id: str):
    """Update a count line (manual correction)."""
    user_id = int(get_jwt_identity())
    payload = request.get_json(silent=True) or {}
    
    line = InventoryCountLine.query.get(line_id)
    if not line:
        return jsonify({"error": "Line not found"}), 404
    
    if line.count_pass.status != "in_progress":
        return jsonify({"error": "Cannot edit lines on submitted pass"}), 400
    
    if "counted_qty" in payload:
        line.counted_qty = int(payload["counted_qty"])
    
    if "notes" in payload:
        line.notes = str(payload["notes"]).strip() or None
    
    line.confidence = "corrected"
    line.captured_at = datetime.utcnow()
    line.captured_by_user_id = user_id
    
    db.session.commit()
    
    return jsonify(_serialize_line(line))


@bp.route("/lines/<line_id>", methods=["DELETE"])
@jwt_required()
def delete_line(line_id: str):
    """Delete a count line."""
    line = InventoryCountLine.query.get(line_id)
    
    if not line:
        return jsonify({"error": "Line not found"}), 404
    
    if line.count_pass.status != "in_progress":
        return jsonify({"error": "Cannot delete lines from submitted pass"}), 400
    
    db.session.delete(line)
    db.session.commit()
    
    return jsonify({"deleted": True})


# =============================================================================
# VARIANCE / RECONCILIATION
# =============================================================================

@bp.route("/sessions/<session_id>/variance", methods=["GET"])
@jwt_required()
def get_variance(session_id: str):
    """
    Calculate variance report for a session.
    
    Variance = Counted - Expected
    Expected = Baseline + Movements during count windows
    
    GET /api/count/sessions/{session_id}/variance?non_zero_only=true
    """
    session = InventoryCountSession.query.get(session_id)
    
    if not session:
        return jsonify({"error": "Session not found"}), 404
    
    non_zero_only = request.args.get("non_zero_only", "").lower() in ("true", "1", "yes")
    
    # Aggregate counted quantities by SKU
    counted_query = db.session.query(
        InventoryCountLine.sku,
        func.sum(InventoryCountLine.counted_qty).label("counted_qty")
    ).join(
        InventoryCountPass
    ).filter(
        InventoryCountPass.session_id == session_id,
        InventoryCountPass.status == "submitted"
    ).group_by(
        InventoryCountLine.sku
    )
    
    counted_by_sku = {row.sku: int(row.counted_qty) for row in counted_query.all()}
    
    # Get baseline quantities from inventory
    baseline_query = db.session.query(
        Product.sku,
        InventoryItem.current_quantity
    ).join(
        InventoryItem
    ).filter(
        InventoryItem.store_id == session.store_id
    )
    
    baseline_by_sku = {row.sku: row.current_quantity or 0 for row in baseline_query.all()}
    
    # Get movements during count windows (simplified: entire session window)
    passes = InventoryCountPass.query.filter_by(
        session_id=session_id,
        status="submitted"
    ).all()
    
    movement_deltas = {}
    if passes:
        earliest = min(p.started_at for p in passes)
        latest = max(p.submitted_at for p in passes if p.submitted_at)
        
        if latest:
            movement_query = db.session.query(
                InventoryMovement.sku,
                func.sum(InventoryMovement.qty_delta).label("delta")
            ).filter(
                InventoryMovement.store_id == session.store_id,
                InventoryMovement.occurred_at >= earliest,
                InventoryMovement.occurred_at <= latest
            ).group_by(
                InventoryMovement.sku
            )
            
            movement_deltas = {row.sku: int(row.delta) for row in movement_query.all()}
    
    # Build variance report
    all_skus = set(counted_by_sku.keys()) | set(baseline_by_sku.keys())
    
    # Get product info for all SKUs
    products = Product.query.filter(Product.sku.in_(all_skus)).all()
    product_info = {p.sku: p for p in products}
    
    results = []
    for sku in sorted(all_skus):
        counted = counted_by_sku.get(sku, 0)
        baseline = baseline_by_sku.get(sku, 0)
        movement = movement_deltas.get(sku, 0)
        
        expected = baseline + movement
        variance = counted - expected
        
        if non_zero_only and variance == 0:
            continue
        
        product = product_info.get(sku)
        
        results.append({
            "sku": sku,
            "product_name": product.name if product else None,
            "brand": product.brand if product else None,
            "category": product.category if product else None,
            "subcategory": product.subcategory if product else None,
            "counted_qty": counted,
            "baseline_qty": baseline,
            "movement_delta": movement,
            "expected_qty": expected,
            "variance": variance,
        })
    
    # Sort by absolute variance (biggest discrepancies first)
    results.sort(key=lambda x: abs(x["variance"]), reverse=True)
    
    return jsonify({
        "session_id": session_id,
        "store_id": session.store_id,
        "status": session.status,
        "total_skus": len(results),
        "total_variance": sum(abs(r["variance"]) for r in results),
        "items": results,
    })


# =============================================================================
# SERIALIZERS
# =============================================================================

def _serialize_location(loc: InventoryLocation) -> dict:
    return {
        "id": loc.id,
        "store_id": loc.store_id,
        "code": loc.code,
        "name": loc.name,
        "description": loc.description,
        "is_active": loc.is_active,
        "sort_order": loc.sort_order,
    }


def _serialize_session(session: InventoryCountSession, include_passes: bool = False) -> dict:
    result = {
        "id": session.id,
        "store_id": session.store_id,
        "status": session.status,
        "notes": session.notes,
        "created_at": session.created_at.isoformat() if session.created_at else None,
        "created_by": {
            "id": session.created_by.id,
            "name": session.created_by.name,
        } if session.created_by else None,
        "expected_snapshot_at": session.expected_snapshot_at.isoformat() if session.expected_snapshot_at else None,
        "closed_at": session.closed_at.isoformat() if session.closed_at else None,
        "pass_count": len(session.passes),
        "submitted_pass_count": len([p for p in session.passes if p.status == "submitted"]),
    }
    
    if include_passes:
        result["passes"] = [_serialize_pass(p) for p in session.passes]
    
    return result


def _serialize_pass(count_pass: InventoryCountPass, include_lines: bool = False) -> dict:
    result = {
        "id": count_pass.id,
        "session_id": count_pass.session_id,
        "location": _serialize_location(count_pass.location) if count_pass.location else None,
        "category": count_pass.category,
        "subcategory": count_pass.subcategory,
        "status": count_pass.status,
        "started_at": count_pass.started_at.isoformat() if count_pass.started_at else None,
        "submitted_at": count_pass.submitted_at.isoformat() if count_pass.submitted_at else None,
        "started_by": {
            "id": count_pass.started_by.id,
            "name": count_pass.started_by.name,
        } if count_pass.started_by else None,
        "device_id": count_pass.device_id,
        "scan_mode": count_pass.scan_mode,
        "line_count": len(count_pass.lines),
        "total_counted": sum(ln.counted_qty for ln in count_pass.lines),
    }
    
    if include_lines:
        result["lines"] = [_serialize_line(ln) for ln in count_pass.lines]
    
    return result


def _serialize_line(line: InventoryCountLine) -> dict:
    return {
        "id": line.id,
        "count_pass_id": line.count_pass_id,
        "product_id": line.product_id,
        "sku": line.sku,
        "barcode": line.barcode,
        "package_id": line.package_id,
        "counted_qty": line.counted_qty,
        "unit": line.unit,
        "captured_at": line.captured_at.isoformat() if line.captured_at else None,
        "confidence": line.confidence,
        "notes": line.notes,
        "product": {
            "id": line.product.id,
            "name": line.product.name,
            "brand": line.product.brand,
            "category": line.product.category,
            "subcategory": line.product.subcategory,
        } if line.product else None,
    }
