-- Reference schema for DiskWise v1
-- Applied programmatically via GRDB migrator

CREATE TABLE IF NOT EXISTS disks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    mount_path TEXT NOT NULL UNIQUE,
    total_size INTEGER NOT NULL,
    free_size INTEGER NOT NULL,
    scanned_at DATETIME
);

CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    disk_id INTEGER NOT NULL REFERENCES disks(id) ON DELETE CASCADE,
    path TEXT NOT NULL UNIQUE,
    size INTEGER NOT NULL,
    hash TEXT,
    mime_type TEXT,
    category TEXT NOT NULL,
    subcategory TEXT,
    created_at DATETIME,
    modified_at DATETIME,
    last_accessed DATETIME,
    extension_name TEXT
);

CREATE INDEX IF NOT EXISTS idx_files_disk_id ON files(disk_id);
CREATE INDEX IF NOT EXISTS idx_files_size ON files(size);
CREATE INDEX IF NOT EXISTS idx_files_hash ON files(hash);
CREATE INDEX IF NOT EXISTS idx_files_category ON files(category);

CREATE TABLE IF NOT EXISTS file_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    metadata_type TEXT NOT NULL,
    payload_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_file_metadata_file_id ON file_metadata(file_id);

CREATE TABLE IF NOT EXISTS duplicate_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    detection_level INTEGER NOT NULL,
    fingerprint TEXT NOT NULL,
    total_size INTEGER NOT NULL,
    file_count INTEGER NOT NULL,
    created_at DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_duplicate_groups_fingerprint ON duplicate_groups(fingerprint);

CREATE TABLE IF NOT EXISTS duplicate_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER NOT NULL REFERENCES duplicate_groups(id) ON DELETE CASCADE,
    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    UNIQUE(group_id, file_id)
);

CREATE INDEX IF NOT EXISTS idx_duplicate_members_group_id ON duplicate_members(group_id);
CREATE INDEX IF NOT EXISTS idx_duplicate_members_file_id ON duplicate_members(file_id);

CREATE TABLE IF NOT EXISTS recommendations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    estimated_savings INTEGER NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at DATETIME NOT NULL
);
