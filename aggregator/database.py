import sqlite3
import logging
from typing import List, Optional, Dict
from contextlib import contextmanager

from config import get_config

logger = logging.getLogger(__name__)

@contextmanager
def get_db_connection():
    config = get_config()
    conn = sqlite3.connect(config.db_path)
    conn.row_factory = sqlite3.Row  # Makes rows dict-like
    
    try:
        yield conn
    finally:
        conn.close()

def get_tenant_events(
    tenant_id: str,
    limit: int = 100,
    offset: int = 0
) -> List[Dict]:
    
    table_name = f"events_{tenant_id.replace('-', '_')}"
    
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            query = f"""
                SELECT 
                    tx_hash,
                    from_address,
                    to_address,
                    value_eth,
                    block_number,
                    timestamp,
                    ipfs_cid
                FROM {table_name}
                ORDER BY timestamp DESC
                LIMIT ? OFFSET ?
            """
            
            cursor.execute(query, (limit, offset))
            rows = cursor.fetchall()
            events = [dict(row) for row in rows]

            logger.info(f"Retrieved {len(events)} events for {tenant_id}")
            return events
            
    except sqlite3.Error as e:
        logger.error(f"Database error fetching events for {tenant_id}: {e}")
        raise DatabaseError(f"Failed to fetch events: {str(e)}")


def get_event_by_hash(tenant_id: str, tx_hash: str) -> Optional[Dict]:
    table_name = f"events_{tenant_id.replace('-', '_')}"
    
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            query = f"""
                SELECT 
                    tx_hash,
                    from_address,
                    to_address,
                    value_eth,
                    block_number,
                    timestamp,
                    ipfs_cid
                FROM {table_name}
                WHERE tx_hash = ?
            """
            
            cursor.execute(query, (tx_hash,))
            row = cursor.fetchone()
            
            if row:
                logger.debug(f"Found event {tx_hash} for {tenant_id}")
                return dict(row)
            else:
                logger.debug(f"Event {tx_hash} not found for {tenant_id}")
                return None
                
    except sqlite3.Error as e:
        logger.error(f"Database error fetching event {tx_hash} for {tenant_id}: {e}")
        raise DatabaseError(f"Failed to fetch event: {str(e)}")


def get_tenant_stats(tenant_id: str) -> Dict:
    table_name = f"events_{tenant_id.replace('-', '_')}"
    
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            # Count total events
            cursor.execute(f"SELECT COUNT(*) as total FROM {table_name}")
            total = cursor.fetchone()['total']
            
            # Count significant events (those with IPFS CIDs)
            cursor.execute(
                f"SELECT COUNT(*) as significant FROM {table_name} WHERE ipfs_cid IS NOT NULL"
            )
            significant = cursor.fetchone()['significant']
            
            # Get latest event timestamp
            cursor.execute(f"SELECT MAX(timestamp) as latest FROM {table_name}")
            latest = cursor.fetchone()['latest']
            
            return {
                'total_events': total,
                'significant_events': significant,
                'normal_events': total - significant,
                'latest_event': latest
            }
            
    except sqlite3.Error as e:
        logger.error(f"Database error getting stats for {tenant_id}: {e}")
        raise DatabaseError(f"Failed to get stats: {str(e)}")


def check_address_watched(tenant_id: str, address: str) -> bool:
    """
    Check if an address is already being watched by this tenant.
    
    Note: This checks the configuration, not the database.
    The actual watched addresses are in tenants.yaml.
    
    Args:
        tenant_id: Which tenant
        address: Ethereum address to check
    
    Returns:
        True if address is being watched, False otherwise
    
    Example:
        if check_address_watched("dao-alpha", "0x742d35..."):
            print("Already watching this address")
        else:
            print("Not watching yet")
    """
    config = get_config()
    tenant_config = config.get_tenant(tenant_id)
    
    if not tenant_config:
        return False
    
    watched = tenant_config.get('watch_addresses', [])
    # Case-insensitive comparison (Ethereum addresses)
    return address.lower() in [addr.lower() for addr in watched]


def get_events_by_address(
    tenant_id: str,
    address: str,
    limit: int = 100
) -> List[Dict]:
    """
    Get all events involving a specific address.
    
    Finds events where address is either sender OR receiver.
    
    Args:
        tenant_id: Which tenant
        address: Ethereum address to filter by
        limit: Maximum results
    
    Returns:
        List of events
    
    Example:
        events = get_events_by_address("dao-alpha", "0x742d35...", limit=20)
    """
    table_name = f"events_{tenant_id.replace('-', '_')}"
    address_lower = address.lower()
    
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            query = f"""
                SELECT 
                    tx_hash,
                    from_address,
                    to_address,
                    value_eth,
                    block_number,
                    timestamp,
                    ipfs_cid
                FROM {table_name}
                WHERE LOWER(from_address) = ? OR LOWER(to_address) = ?
                ORDER BY timestamp DESC
                LIMIT ?
            """
            
            cursor.execute(query, (address_lower, address_lower, limit))
            rows = cursor.fetchall()
            
            return [dict(row) for row in rows]
            
    except sqlite3.Error as e:
        logger.error(f"Database error fetching events for address {address}: {e}")
        raise DatabaseError(f"Failed to fetch events by address: {str(e)}")


def get_significant_events(tenant_id: str, limit: int = 100) -> List[Dict]:
    """
    Get only significant events (those with IPFS CIDs).
    
    These are events above the tenant's alert threshold.
    
    Args:
        tenant_id: Which tenant
        limit: Maximum results
    
    Returns:
        List of significant events
    
    Example:
        significant = get_significant_events("dao-alpha", limit=10)
        for event in significant:
            print(f"CID: {event['ipfs_cid']}")
    """
    table_name = f"events_{tenant_id.replace('-', '_')}"
    
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            query = f"""
                SELECT 
                    tx_hash,
                    from_address,
                    to_address,
                    value_eth,
                    block_number,
                    timestamp,
                    ipfs_cid
                FROM {table_name}
                WHERE ipfs_cid IS NOT NULL
                ORDER BY timestamp DESC
                LIMIT ?
            """
            
            cursor.execute(query, (limit,))
            rows = cursor.fetchall()
            
            return [dict(row) for row in rows]
            
    except sqlite3.Error as e:
        logger.error(f"Database error fetching significant events for {tenant_id}: {e}")
        raise DatabaseError(f"Failed to fetch significant events: {str(e)}")



def verify_table_exists(tenant_id: str) -> bool:
    """
    Check if a tenant's table exists in the database.
    
    Useful for:
    - Debugging
    - Initialization checks
    - Error handling
    
    Args:
        tenant_id: Tenant to check
    
    Returns:
        True if table exists, False otherwise
    """
    table_name = f"events_{tenant_id.replace('-', '_')}"
    
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            
            cursor.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                (table_name,)
            )
            
            return cursor.fetchone() is not None
            
    except sqlite3.Error as e:
        logger.error(f"Error checking table existence: {e}")
        return False


def get_table_row_count(tenant_id: str) -> int:
    """
    Get total number of rows in tenant's table.
    
    Args:
        tenant_id: Tenant to count
    
    Returns:
        Number of rows
    """
    table_name = f"events_{tenant_id.replace('-', '_')}"
    
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(f"SELECT COUNT(*) as count FROM {table_name}")
            return cursor.fetchone()['count']
            
    except sqlite3.Error as e:
        logger.error(f"Error counting rows: {e}")
        return 0




class DatabaseError(Exception):
    """
    Custom exception for database errors.
    
    Why custom exception?
    - Clearer error handling
    - Can catch specifically: except DatabaseError
    - Better logging
    """
    pass