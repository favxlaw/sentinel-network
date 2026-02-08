"""
Database management for Sentinel Watcher
Handles SQLite operations with tenant-partitioned tables
"""

import sqlite3
import os
import yaml
import re
from contextlib import contextmanager


def _interpolate_env(value):
    if isinstance(value, str):
        def replacer(match):
            var_name = match.group(1)
            return os.getenv(var_name, match.group(0))
        return re.sub(r"\$\{([^}]+)\}", replacer, value)
    if isinstance(value, dict):
        return {k: _interpolate_env(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_interpolate_env(v) for v in value]
    return value


def _load_services_config():
    default_path = os.path.join(os.path.dirname(__file__), "../config/services.yaml")
    config_path = os.getenv("SERVICE_CONFIG_PATH", default_path)
    if not os.path.exists(config_path):
        return {}
    with open(config_path, "r") as f:
        data = yaml.safe_load(f) or {}
    return _interpolate_env(data)


class DatabaseManager:
    """
    Manages SQLite database for event storage
    """
    
    def __init__(self, db_path: str = None):
        if db_path is None:
            services_cfg = _load_services_config()
            watcher_cfg = services_cfg.get("watcher", {})
            paths_cfg = services_cfg.get("paths", {})
            db_path = (
                os.getenv("SENTINEL_DB_PATH")
                or watcher_cfg.get("db_path")
                or paths_cfg.get("watcher_db")
                or "watcher.db"
            )
        self.db_path = db_path
        self._init_database()
    
    @contextmanager
    def get_connection(self):
        """Context manager for safe database connections"""
        conn = sqlite3.connect(self.db_path)
        try:
            yield conn
            conn.commit()
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            conn.close()
    
    def _init_database(self):
        """Initialize database with state tracking table"""
        with self.get_connection() as conn:
            cursor = conn.cursor()
            
            # State table tracks our polling progress
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS watcher_state (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            cursor.execute("""
                INSERT OR IGNORE INTO watcher_state (key, value)
                VALUES ('last_processed_block', '0')
            """)
        
        print(f"Database initialized: {self.db_path}")
    
    def create_tenant_table(self, tenant_id: str):
        """Create events table for a tenant"""
        table_name = f"events_{tenant_id.replace('-', '_')}"
        
        with self.get_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute(f"""
                CREATE TABLE IF NOT EXISTS {table_name} (
                    tx_hash TEXT PRIMARY KEY,
                    from_address TEXT NOT NULL,
                    to_address TEXT NOT NULL,
                    value_eth REAL NOT NULL,
                    block_number INTEGER NOT NULL,
                    timestamp INTEGER NOT NULL,
                    ipfs_cid TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Indexes for fast queries
            cursor.execute(f"""
                CREATE INDEX IF NOT EXISTS idx_{table_name}_block 
                ON {table_name}(block_number)
            """)
        
        print(f"Created table: {table_name}")
    
    def insert_event(self, tenant_id: str, event_data: dict) -> bool:
        """Insert event, return False if duplicate"""
        table_name = f"events_{tenant_id.replace('-', '_')}"
        
        try:
            with self.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute(f"""
                    INSERT INTO {table_name} 
                    (tx_hash, from_address, to_address, value_eth, 
                     block_number, timestamp, ipfs_cid)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (
                    event_data['tx_hash'],
                    event_data['from_address'],
                    event_data['to_address'],
                    event_data['value_eth'],
                    event_data['block_number'],
                    event_data['timestamp'],
                    event_data.get('ipfs_cid')
                ))
                return True
        except sqlite3.IntegrityError:
            return False  # Duplicate transaction
    
    def update_ipfs_cid(self, tenant_id: str, tx_hash: str, ipfs_cid: str):
        """Update event with IPFS CID"""
        table_name = f"events_{tenant_id.replace('-', '_')}"
        
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(f"""
                UPDATE {table_name} SET ipfs_cid = ? WHERE tx_hash = ?
            """, (ipfs_cid, tx_hash))
    
    def get_tenant_events(self, tenant_id: str, limit: int = 100) -> list:
        """Get recent events for tenant"""
        table_name = f"events_{tenant_id.replace('-', '_')}"
        
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(f"""
                SELECT tx_hash, from_address, to_address, value_eth,
                       block_number, timestamp, ipfs_cid, created_at
                FROM {table_name}
                ORDER BY block_number DESC
                LIMIT ?
            """, (limit,))
            
            columns = ['tx_hash', 'from_address', 'to_address', 'value_eth',
                      'block_number', 'timestamp', 'ipfs_cid', 'created_at']
            
            return [dict(zip(columns, row)) for row in cursor.fetchall()]
    
    def get_last_processed_block(self) -> int:
        """Get last processed block number"""
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT value FROM watcher_state
                WHERE key = 'last_processed_block'
            """)
            result = cursor.fetchone()
            return int(result[0]) if result else 0
    
    def update_last_processed_block(self, block_number: int):
        """Update last processed block"""
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE watcher_state
                SET value = ?, updated_at = CURRENT_TIMESTAMP
                WHERE key = 'last_processed_block'
            """, (str(block_number),))
    
    def get_event_count(self, tenant_id: str) -> int:
        """Count events for tenant"""
        table_name = f"events_{tenant_id.replace('-', '_')}"
        
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
            return cursor.fetchone()[0]
