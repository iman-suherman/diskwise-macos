# Database Schema

DiskWise uses SQLite via GRDB. Migrations live in `Sources/DatabaseKit/Migrations/DatabaseMigrator.swift`.

## Tables

### `disks`

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto increment |
| name | TEXT | Display name |
| mount_path | TEXT UNIQUE | e.g. `/Volumes/Media01` |
| total_size | INTEGER | Bytes |
| free_size | INTEGER | Bytes |
| scanned_at | DATETIME | Last scan timestamp |

### `files`

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto increment |
| disk_id | INTEGER FK | References `disks.id` |
| path | TEXT UNIQUE | Absolute file path |
| size | INTEGER | Bytes |
| hash | TEXT | SHA256 (optional until hashed) |
| mime_type | TEXT | Uniform type identifier |
| category | TEXT | video, photo, document, etc. |
| subcategory | TEXT | Optional custom label |
| created_at | DATETIME | File creation |
| modified_at | DATETIME | Content modification |
| last_accessed | DATETIME | Content access |
| extension_name | TEXT | Lowercase extension |

### `file_metadata`

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto increment |
| file_id | INTEGER FK | References `files.id` |
| metadata_type | TEXT | video, image, archive |
| payload_json | TEXT | Structured metadata JSON |

### `duplicate_groups`

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto increment |
| detection_level | INTEGER | 1–4 |
| fingerprint | TEXT | Group key |
| total_size | INTEGER | Combined size |
| file_count | INTEGER | Members in group |
| created_at | DATETIME | Detection timestamp |

### `duplicate_members`

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto increment |
| group_id | INTEGER FK | References `duplicate_groups.id` |
| file_id | INTEGER FK | References `files.id` |

### `recommendations`

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto increment |
| type | TEXT | duplicate_cleanup, delete_previews, etc. |
| title | TEXT | User-facing title |
| estimated_savings | INTEGER | Bytes |
| reason | TEXT | Explanation |
| status | TEXT | pending, applied, dismissed |
| created_at | DATETIME | Created timestamp |

## Default database location

`~/Library/Application Support/DiskWise/diskwise.sqlite`

## Reference SQL

See `database/migrations/001_initial.sql` for the canonical SQL snapshot.
