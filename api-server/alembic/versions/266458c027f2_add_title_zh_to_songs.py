"""add title_zh to songs

Revision ID: 266458c027f2
Revises: 315baecc3cc6
Create Date: 2026-05-28 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '266458c027f2'
down_revision: Union[str, None] = '315baecc3cc6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('songs', sa.Column('title_zh', sa.String(length=255), nullable=True))


def downgrade() -> None:
    op.drop_column('songs', 'title_zh')
