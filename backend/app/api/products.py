"""
Product lookup API - for barcode scanning during counts.
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from sqlalchemy import func

from app import db
from app.models.product import Product, InventoryItem
from app.models.user import Store

bp = Blueprint("products", __name__)


@bp.route("/lookup", methods=["GET"])
@jwt_required()
def lookup_by_barcode():
    """
    Resolve barcode to product for inventory counting.
    
    GET /api/products/lookup?barcode=XXX&store_id=1
    
    Searches: SKU, cova_sku (exact match)
    """
    barcode = request.args.get("barcode", "").strip()
    store_id = request.args.get("store_id", type=int)
    
    if not barcode:
        return jsonify({"error": "barcode parameter required"}), 400
    
    # Try exact match on SKU or cova_sku
    product = Product.query.filter(
        (Product.sku == barcode) | (Product.cova_sku == barcode)
    ).first()
    
    if not product:
        return jsonify({
            "error": "Product not found",
            "barcode": barcode,
        }), 404
    
    # Get inventory item if store specified
    inventory = None
    if store_id:
        inventory = InventoryItem.query.filter_by(
            store_id=store_id,
            product_id=product.id
        ).first()
    
    return jsonify({
        "product": _serialize_product(product),
        "inventory": _serialize_inventory(inventory) if inventory else None,
    })


@bp.route("", methods=["GET"])
@jwt_required()
def list_products():
    """
    List products with optional filtering.
    
    GET /api/products?category=Flower&subcategory=Dried+Flower&store_id=1&search=blue+dream
    """
    category = request.args.get("category")
    subcategory = request.args.get("subcategory")
    store_id = request.args.get("store_id", type=int)
    search = request.args.get("search", "").strip()
    page = request.args.get("page", 1, type=int)
    per_page = min(request.args.get("per_page", 50, type=int), 200)
    
    query = Product.query.filter(Product.is_active == True)
    
    if category:
        query = query.filter(func.lower(Product.category) == category.lower())
    
    if subcategory:
        query = query.filter(func.lower(Product.subcategory) == subcategory.lower())
    
    if search:
        pattern = f"%{search}%"
        query = query.filter(
            func.lower(Product.name).like(func.lower(pattern)) |
            func.lower(Product.brand).like(func.lower(pattern)) |
            Product.sku.like(pattern)
        )
    
    # If store specified, only return products with inventory at that store
    if store_id:
        query = query.join(InventoryItem).filter(InventoryItem.store_id == store_id)
    
    query = query.order_by(Product.name)
    
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    
    return jsonify({
        "products": [_serialize_product(p) for p in pagination.items],
        "page": pagination.page,
        "per_page": pagination.per_page,
        "total": pagination.total,
        "pages": pagination.pages,
        "has_next": pagination.has_next,
        "has_prev": pagination.has_prev,
    })


@bp.route("/categories", methods=["GET"])
@jwt_required()
def list_categories():
    """
    List all category/subcategory combinations.
    
    GET /api/products/categories?store_id=1
    """
    store_id = request.args.get("store_id", type=int)
    
    query = db.session.query(
        Product.category,
        Product.subcategory,
        func.count(Product.id).label("product_count")
    ).filter(
        Product.is_active == True,
        Product.category.isnot(None)
    )
    
    if store_id:
        query = query.join(InventoryItem).filter(InventoryItem.store_id == store_id)
    
    query = query.group_by(Product.category, Product.subcategory)
    query = query.order_by(Product.category, Product.subcategory)
    
    results = query.all()
    
    # Build hierarchical structure
    categories = {}
    for category, subcategory, count in results:
        if category not in categories:
            categories[category] = {
                "name": category,
                "subcategories": [],
                "total_products": 0,
            }
        
        if subcategory:
            categories[category]["subcategories"].append({
                "name": subcategory,
                "product_count": count,
            })
        
        categories[category]["total_products"] += count
    
    return jsonify({
        "categories": list(categories.values()),
    })


@bp.route("/<int:product_id>", methods=["GET"])
@jwt_required()
def get_product(product_id: int):
    """Get a single product by ID."""
    product = Product.query.get(product_id)
    
    if not product:
        return jsonify({"error": "Product not found"}), 404
    
    return jsonify(_serialize_product(product))


def _serialize_product(product: Product) -> dict:
    return {
        "id": product.id,
        "sku": product.sku,
        "cova_sku": product.cova_sku,
        "name": product.name,
        "brand": product.brand,
        "category": product.category,
        "subcategory": product.subcategory,
        "dominance": product.dominance,
        "thc_min": product.thc_min,
        "thc_max": product.thc_max,
        "thc_uom": product.thc_uom,
        "cbd_min": product.cbd_min,
        "cbd_max": product.cbd_max,
        "cbd_uom": product.cbd_uom,
        "format": product.format,
        "item_count": product.item_count,
        "item_size": product.item_size,
        "item_size_uom": product.item_size_uom,
    }


def _serialize_inventory(item: InventoryItem) -> dict:
    return {
        "id": item.id,
        "store_id": item.store_id,
        "current_quantity": item.current_quantity,
        "retail_price": item.retail_price,
        "cost_price": item.cost_price,
        "cabinet": item.cabinet,
    }
