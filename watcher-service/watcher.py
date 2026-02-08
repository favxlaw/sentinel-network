"""
Sentinel Network - Watcher Service
Monitors blockchain for tenant-specific address activity
"""

from config_loader import ConfigLoader
from database import DatabaseManager
from blockchain import BlockchainConnector
from logger import TenantLogger
from ipfs_client import IPFSClient
import time
import os
import yaml
import re
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from dotenv import load_dotenv

load_dotenv()


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


def load_services_config():
    default_path = os.path.join(os.path.dirname(__file__), "../config/services.yaml")
    config_path = os.getenv("SERVICE_CONFIG_PATH", default_path)
    if not os.path.exists(config_path):
        return {}
    with open(config_path, "r") as f:
        data = yaml.safe_load(f) or {}
    return _interpolate_env(data)


class WatcherService:
    """
    Main watcher service that orchestrates all components
    
    Architecture:
    - ConfigLoader: Reads tenant configuration
    - DatabaseManager: Stores events persistently
    - BlockchainConnector: Fetches blockchain data
    - TenantLogger: Logs events per tenant
    - IPFSClient: Archives significant events
    """
    
    def __init__(self):
        """Initialize all service components"""
        print("\n" + "="*60)
        print("SENTINEL WATCHER SERVICE - INITIALIZING")
        print("="*60 + "\n")

        services_cfg = load_services_config()
        watcher_cfg = services_cfg.get("watcher", {})
        paths_cfg = services_cfg.get("paths", {})

        tenant_config_path = (
            os.getenv("TENANT_CONFIG_PATH")
            or watcher_cfg.get("tenant_config_path")
            or paths_cfg.get("tenant_config")
        )

        db_path = (
            os.getenv("SENTINEL_DB_PATH")
            or watcher_cfg.get("db_path")
            or paths_cfg.get("watcher_db")
        )

        ipfs_api_url = (
            os.getenv("IPFS_API_URL")
            or watcher_cfg.get("ipfs_api_url")
        )

        log_dir = os.getenv("WATCHER_LOG_DIR", watcher_cfg.get("log_dir", "logs"))
        self.health_host = os.getenv("WATCHER_HEALTH_HOST", watcher_cfg.get("health_host", "0.0.0.0"))
        self.health_port = int(os.getenv("WATCHER_HEALTH_PORT", str(watcher_cfg.get("health_port", 9001))))

        # Load configuration
        self.config = ConfigLoader(config_path=tenant_config_path)
        self.tenants = self.config.load()
        self.config.validate()
        
        # Initialize database
        self.db = DatabaseManager(db_path=db_path)
        
        # Create tables for all tenants
        for tenant in self.tenants:
            self.db.create_tenant_table(tenant.id)
        
        # Initialize blockchain connection
        self.blockchain = BlockchainConnector()
        
        # Initialize logging
        self.logger = TenantLogger(log_dir=log_dir)
        
        # Initialize IPFS (optional - gracefully handles if unavailable)
        self.ipfs = IPFSClient(api_url=ipfs_api_url)
        
        # Polling interval (seconds)
        self.poll_interval = int(
            os.getenv("POLL_INTERVAL", str(watcher_cfg.get("poll_interval_seconds", 12)))
        )

        # Start health check server
        self._start_health_server()
        
        print("\n" + "="*60)
        print("INITIALIZATION COMPLETE - READY TO MONITOR")
        print("="*60 + "\n")

    def _start_health_server(self):
        service = self

        class HealthHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path != "/health":
                    self.send_response(404)
                    self.end_headers()
                    return

                payload = {
                    "status": "healthy",
                    "service": "watcher",
                    "tenants_loaded": len(service.tenants),
                    "last_processed_block": service.db.get_last_processed_block(),
                    "ipfs_enabled": service.ipfs.enabled
                }

                body = json.dumps(payload).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format, *args):
                # Suppress default HTTP server logging
                return

        def run_server():
            httpd = HTTPServer((self.health_host, self.health_port), HealthHandler)
            httpd.serve_forever()

        thread = threading.Thread(target=run_server, daemon=True)
        thread.start()
    
    def process_block(self, block_number: int):
        """
        Process a single block for all tenants
        
        Args:
            block_number: Block number to process
        
        Steps:
        1. Fetch block from blockchain
        2. For each tenant, extract relevant transactions
        3. Check if transactions meet alert threshold
        4. Log events, store in database, post to IPFS
        """
        # Fetch block with all transactions
        block = self.blockchain.get_block_with_transactions(block_number)
        
        if block is None:
            self.logger.log_system(f"Block {block_number} not found", "WARNING")
            return
        
        # Process for each tenant
        for tenant in self.tenants:
            # Extract transactions involving this tenant's addresses
            transactions = self.blockchain.extract_transactions(
                block, 
                tenant.watch_addresses
            )
            
            # Process each transaction
            for tx in transactions:
                self._process_transaction(tenant, tx)
        
        # Update progress
        self.db.update_last_processed_block(block_number)
    
    def _process_transaction(self, tenant, tx: dict):
        """
        Process a single transaction for a tenant
        
        Args:
            tenant: Tenant object
            tx: Transaction dictionary
        """
        # Log transaction
        self.logger.log_event(tenant.id, "TRANSACTION", tx)
        
        # Check if significant (meets threshold)
        is_significant = tx['value_eth'] >= tenant.alert_threshold_eth
        
        if is_significant:
            # Log alert
            self.logger.log_event(tenant.id, "SIGNIFICANT_EVENT", {
                'tx_hash': tx['tx_hash'],
                'value_eth': tx['value_eth'],
                'threshold': tenant.alert_threshold_eth
            })
            
            # Post to IPFS
            ipfs_cid = self._post_to_ipfs(tenant.id, tx)
            tx['ipfs_cid'] = ipfs_cid
        else:
            tx['ipfs_cid'] = None
        
        # Store in database
        success = self.db.insert_event(tenant.id, tx)
        
        if not success:
            # Transaction already exists (duplicate)
            return
    
    def _post_to_ipfs(self, tenant_id: str, tx: dict) -> str:
        """
        Post transaction data to IPFS
        
        Args:
            tenant_id: Tenant identifier
            tx: Transaction data
        
        Returns:
            IPFS CID or None
        """
        # Prepare event receipt for IPFS
        receipt = {
            'tenant_id': tenant_id,
            'transaction': tx,
            'timestamp': tx['timestamp'],
            'block_number': tx['block_number']
        }
        
        # Add to IPFS
        cid = self.ipfs.add_json(receipt)
        
        if cid:
            self.logger.log_event(tenant_id, "IPFS_STORED", {'ipfs_cid': cid})
            
            # Pin to ensure persistence
            self.ipfs.pin_cid(cid)
        
        return cid
    
    def catch_up(self):
        """
        Process all missed blocks since last run
        
        """
        last_processed = self.db.get_last_processed_block()
        latest_block = self.blockchain.get_latest_block_number()
        
        blocks_behind = latest_block - last_processed
        
        if blocks_behind > 0:
            self.logger.log_system(
                f"Catching up: {blocks_behind} blocks behind (from {last_processed} to {latest_block})"
            )
            
            # Process missed blocks
            for block_num in range(last_processed + 1, latest_block + 1):
                self.process_block(block_num)
                
                # Progress update every 10 blocks
                if block_num % 10 == 0:
                    progress = ((block_num - last_processed) / blocks_behind) * 100
                    self.logger.log_system(f"Catch-up progress: {progress:.1f}%")
            
            self.logger.log_system("✓ Catch-up complete")
        else:
            self.logger.log_system("Already up-to-date")
    
    def run(self):
        """
        Main polling loop - runs forever
        
        Logic:
        1. Catch up on any missed blocks
        2. Poll for new blocks every ~12 seconds
        3. Process new blocks as they appear
        4. Handle errors gracefully (don't crash)
        """
        self.logger.log_system("Starting blockchain monitoring...")
        
        # Initial catch-up
        self.catch_up()
        
        # Main loop
        while True:
            try:
                # Get current state
                last_processed = self.db.get_last_processed_block()
                latest_block = self.blockchain.get_latest_block_number()
                
                # Check for new blocks
                if latest_block > last_processed:
                    blocks_to_process = latest_block - last_processed
                    self.logger.log_system(f"New blocks detected: {blocks_to_process}")
                    
                    # Process new blocks
                    for block_num in range(last_processed + 1, latest_block + 1):
                        self.process_block(block_num)
                        self.logger.log_system(f"Processed block {block_num}")
                
                # Wait before next poll
                time.sleep(self.poll_interval)
            
            except KeyboardInterrupt:
                self.logger.log_system("Shutting down gracefully...")
                break
            
            except Exception as e:
                self.logger.log_system(f"Error in main loop: {e}", "ERROR")
                time.sleep(self.poll_interval)  # Wait before retry


# ----------------------------------------------------------
# ENTRY POINT
# ----------------------------------------------------------

def main():
    """Main entry point"""
    watcher = WatcherService()
    watcher.run()


if __name__ == "__main__":
    main()
