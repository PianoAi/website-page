"""song_translations table

Revision ID: e49d17f2e6cb
Revises: 266458c027f2
Create Date: 2026-05-28 12:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "e49d17f2e6cb"
down_revision: Union[str, None] = "266458c027f2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "song_translations",
        sa.Column("song_id", sa.UUID(), nullable=False),
        sa.Column("locale", sa.String(length=10), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(["song_id"], ["songs.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("song_id", "locale"),
    )
    op.create_index("ix_song_translations_locale", "song_translations", ["locale"])

    # 迁移现有 title_zh 数据 → zh-Hans
    op.execute("""
        INSERT INTO song_translations (song_id, locale, title)
        SELECT id, 'zh-Hans', title_zh
        FROM songs
        WHERE title_zh IS NOT NULL
    """)

    op.drop_column("songs", "title_zh")


def downgrade() -> None:
    op.add_column("songs", sa.Column("title_zh", sa.String(255), nullable=True))
    op.execute("""
        UPDATE songs s
        SET title_zh = t.title
        FROM song_translations t
        WHERE t.song_id = s.id AND t.locale = 'zh-Hans'
    """)
    op.drop_index("ix_song_translations_locale", "song_translations")
    op.drop_table("song_translations")
