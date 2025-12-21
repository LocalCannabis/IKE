#!/bin/bash
# Quick setup script for the Inventory Count backend

set -e

cd "$(dirname "$0")"

echo "=================================="
echo "Inventory Count Backend Setup"
echo "=================================="

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

# Activate virtual environment
echo "Activating virtual environment..."
source .venv/bin/activate

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements.txt

# Copy .env if it doesn't exist
if [ ! -f ".env" ]; then
    echo "Creating .env from template..."
    cp .env.example .env
fi

# Initialize database
echo "Initializing database..."
python init_db.py

echo ""
echo "=================================="
echo "Setup complete!"
echo "=================================="
echo ""
echo "To start the server:"
echo "  cd backend"
echo "  source .venv/bin/activate"
echo "  python run.py"
echo ""
echo "Server will run at: http://localhost:5000"
echo ""
echo "Quick test:"
echo '  curl -X POST http://localhost:5000/api/auth/dev-login -H "Content-Type: application/json" -d '\''{"email": "dev@example.com"}'\'''
