from datetime import timedelta
from pathlib import Path
import os

from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from dotenv import load_dotenv

load_dotenv()

db = SQLAlchemy()
migrate = Migrate()
jwt = JWTManager()


def create_app(config_name="development"):
    """Application factory."""
    app = Flask(__name__)
    
    # Ensure instance folder exists
    instance_path = Path(app.instance_path)
    instance_path.mkdir(parents=True, exist_ok=True)
    
    # Configuration
    database_url = os.getenv("DATABASE_URL", "sqlite:///instance/inventory_count.db")
    
    # Handle relative SQLite paths
    if database_url.startswith("sqlite:///") and not database_url.startswith("sqlite:////"):
        db_path = database_url.replace("sqlite:///", "")
        if not Path(db_path).is_absolute():
            abs_path = Path(__file__).parent.parent / db_path
            database_url = f"sqlite:///{abs_path.resolve()}"
    
    app.config["SECRET_KEY"] = os.getenv("JWT_SECRET_KEY", "dev-secret")
    app.config["SQLALCHEMY_DATABASE_URI"] = database_url
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    app.config["JWT_SECRET_KEY"] = os.getenv("JWT_SECRET_KEY", "dev-secret")
    app.config["JWT_ACCESS_TOKEN_EXPIRES"] = timedelta(hours=24) if os.getenv("FLASK_ENV") == "production" else False
    
    # Initialize extensions
    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    
    # CORS
    cors_origins = os.getenv("CORS_ORIGINS", "*")
    if cors_origins == "*":
        CORS(app)
    else:
        origins = [o.strip() for o in cors_origins.split(",") if o.strip()]
        CORS(app, origins=origins, supports_credentials=True)
    
    # Import models (triggers table registration)
    from app.models import user, product, inventory_count  # noqa: F401
    
    # Register blueprints
    from app.api import auth, count, products
    app.register_blueprint(auth.bp, url_prefix="/api/auth")
    app.register_blueprint(count.bp, url_prefix="/api/count")
    app.register_blueprint(products.bp, url_prefix="/api/products")
    
    # Health check
    @app.route("/api/health")
    def health():
        return {"status": "healthy", "app": "inventory-count-api", "version": "0.1.0"}
    
    return app
