"""
Dev authentication - simple PIN-based login for tablet.
Will be replaced with JFK Google OAuth integration in MK5.
"""
import uuid
from datetime import datetime
from flask import Blueprint, request, jsonify
from flask_jwt_extended import create_access_token, jwt_required, get_jwt_identity

from app import db
from app.models.user import User, Store

bp = Blueprint("auth", __name__)


@bp.route("/login", methods=["POST"])
def login():
    """
    Dev login with email + PIN.
    
    POST /api/auth/login
    {
        "email": "staff@example.com",
        "pin": "1234"
    }
    """
    payload = request.get_json(silent=True) or {}
    
    email = str(payload.get("email", "")).strip().lower()
    pin = str(payload.get("pin", "")).strip()
    
    if not email:
        return jsonify({"error": "Email required"}), 400
    
    user = User.query.filter_by(email=email, is_active=True).first()
    
    if not user:
        return jsonify({"error": "User not found"}), 401
    
    # PIN check (empty PIN allowed in dev for convenience)
    if user.pin and user.pin != pin:
        return jsonify({"error": "Invalid PIN"}), 401
    
    # Update last login
    user.last_login = datetime.utcnow()
    db.session.commit()
    
    # Create JWT
    access_token = create_access_token(identity=str(user.id))
    
    return jsonify({
        "access_token": access_token,
        "user": _serialize_user(user),
    })


@bp.route("/dev-login", methods=["POST"])
def dev_login():
    """
    Quick dev login - just provide email, no PIN required.
    Auto-creates user if not exists.
    
    POST /api/auth/dev-login
    {
        "email": "dev@example.com",
        "name": "Dev User"  // optional
    }
    """
    payload = request.get_json(silent=True) or {}
    
    email = str(payload.get("email", "dev@example.com")).strip().lower()
    name = str(payload.get("name", "")).strip() or email.split("@")[0].title()
    
    user = User.query.filter_by(email=email).first()
    
    if not user:
        # Auto-create dev user with generated google_id
        user = User(
            google_id=f"dev_{uuid.uuid4().hex[:16]}",  # Fake google_id for dev
            email=email,
            name=name,
            role="manager",  # Give dev users manager access
            is_active=True,
        )
        db.session.add(user)
        db.session.commit()
    
    user.last_login = datetime.utcnow()
    db.session.commit()
    
    access_token = create_access_token(identity=str(user.id))
    
    return jsonify({
        "access_token": access_token,
        "user": _serialize_user(user),
        "created": user.created_at == user.last_login,  # Was just created
    })


@bp.route("/me", methods=["GET"])
@jwt_required()
def get_current_user():
    """Get current authenticated user."""
    user_id = int(get_jwt_identity())
    user = User.query.get(user_id)
    
    if not user:
        return jsonify({"error": "User not found"}), 404
    
    return jsonify(_serialize_user(user))


@bp.route("/users", methods=["GET"])
@jwt_required()
def list_users():
    """List all active users (for user selection on tablet)."""
    users = User.query.filter_by(is_active=True).order_by(User.name).all()
    return jsonify([_serialize_user(u) for u in users])


@bp.route("/users", methods=["POST"])
@jwt_required()
def create_user():
    """Create a new user (admin only in production, open in dev)."""
    payload = request.get_json(silent=True) or {}
    
    email = str(payload.get("email", "")).strip().lower()
    name = str(payload.get("name", "")).strip()
    pin = str(payload.get("pin", "")).strip() or None
    role = str(payload.get("role", "staff")).strip()
    
    if not email or not name:
        return jsonify({"error": "Email and name required"}), 400
    
    if User.query.filter_by(email=email).first():
        return jsonify({"error": "Email already exists"}), 409
    
    if role not in ("staff", "manager", "admin"):
        role = "staff"
    
    user = User(
        google_id=f"dev_{uuid.uuid4().hex[:16]}",  # Fake google_id for dev
        email=email,
        name=name,
        pin=pin,
        role=role,
        is_active=True,
    )
    db.session.add(user)
    db.session.commit()
    
    return jsonify(_serialize_user(user)), 201


@bp.route("/stores", methods=["GET"])
@jwt_required()
def list_stores():
    """List all active stores."""
    stores = Store.query.filter_by(is_active=True).order_by(Store.name).all()
    return jsonify([_serialize_store(s) for s in stores])


def _serialize_user(user: User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "name": user.name,
        "role": user.role,
        "is_active": user.is_active,
        "default_store_id": user.default_store_id,
        "last_login": user.last_login.isoformat() if user.last_login else None,
        "permissions": {
            "can_count": user.can_count(),
            "can_reconcile": user.can_reconcile(),
            "can_admin": user.can_admin(),
        },
    }


def _serialize_store(store: Store) -> dict:
    return {
        "id": store.id,
        "name": store.name,
        "code": store.code,
        "address": store.address,
        "is_active": store.is_active,
    }
