"""add gtin_14 and upc barcode columns to products

Revision ID: 3b8313add556
Revises: 
Create Date: 2025-12-24 23:25:26.203467

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '3b8313add556'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # Add barcode columns
    op.add_column('products', sa.Column('gtin_14', sa.String(14), nullable=True))
    op.add_column('products', sa.Column('upc', sa.String(12), nullable=True))
    
    # Add indexes for barcode lookups
    op.create_index('idx_products_gtin_14', 'products', ['gtin_14'])
    op.create_index('idx_products_upc', 'products', ['upc'])


def downgrade():
    op.drop_index('idx_products_upc', 'products')
    op.drop_index('idx_products_gtin_14', 'products')
    op.drop_column('products', 'upc')
    op.drop_column('products', 'gtin_14')
