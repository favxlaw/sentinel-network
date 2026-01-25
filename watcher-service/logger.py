"""
Tenant-specific logging for Sentinel Watcher
Each tenant gets their own log file for event tracking
"""

import logging
import os
from datetime import datetime


class TenantLogger:
    """
    Manages separate log files for each tenant
    
    """
    
    def __init__(self, log_dir: str = "logs"):
        """
        Initialize tenant logger
        
        Args:
            log_dir: Directory to store log files
        """
        self.log_dir = log_dir
        self.loggers = {}  # Cache loggers to avoid recreating
        
        # Create logs directory if it doesn't exist
        os.makedirs(log_dir, exist_ok=True)
        
        print(f"✓ Tenant logging initialized: {log_dir}/")
    
    def get_logger(self, tenant_id: str) -> logging.Logger:
        """
        Get or create logger for a tenant
        
        Args:
            tenant_id: Tenant identifier
        
        Returns:
            Logger instance for this tenant
        """
        # Return cached logger if it exists
        if tenant_id in self.loggers:
            return self.loggers[tenant_id]
        
        # Create new logger
        logger = logging.getLogger(f"watcher.{tenant_id}")
        logger.setLevel(logging.INFO)
        
        # Prevent duplicate handlers if logger already exists
        if not logger.handlers:
            # File handler - writes to tenant-specific file
            log_file = os.path.join(self.log_dir, f"{tenant_id}.log")
            file_handler = logging.FileHandler(log_file)
            file_handler.setLevel(logging.INFO)
            
            # Format: [2026-01-23 14:30:45] INFO: Message
            formatter = logging.Formatter(
                '[%(asctime)s] %(levelname)s: %(message)s',
                datefmt='%Y-%m-%d %H:%M:%S'
            )
            file_handler.setFormatter(formatter)
            
            logger.addHandler(file_handler)
        
        # Cache logger
        self.loggers[tenant_id] = logger
        
        return logger
    
    def log_event(self, tenant_id: str, event_type: str, details: dict):
        """
        Log an event for a tenant
        
        Args:
            tenant_id: Which tenant
            event_type: Type of event (TRANSACTION, ALERT, etc.)
            details: Event details dictionary
        """
        logger = self.get_logger(tenant_id)
        
        # Format log message
        message = f"[{event_type}] "
        
        if event_type == "TRANSACTION":
            message += (
                f"TX: {details['tx_hash']} | "
                f"From: {details['from_address'][:10]}... | "
                f"To: {details['to_address'][:10]}... | "
                f"Value: {details['value_eth']} ETH | "
                f"Block: {details['block_number']}"
            )
        elif event_type == "SIGNIFICANT_EVENT":
            message += (
                f"ALERT: {details['value_eth']} ETH moved | "
                f"TX: {details['tx_hash']} | "
                f"Threshold: {details['threshold']} ETH"
            )
        elif event_type == "IPFS_STORED":
            message += f"Stored to IPFS | CID: {details['ipfs_cid']}"
        else:
            message += str(details)
        
        logger.info(message)
    
    def log_error(self, tenant_id: str, error_message: str):
        """
        Log an error for a tenant
        
        Args:
            tenant_id: Which tenant
            error_message: Error description
        """
        logger = self.get_logger(tenant_id)
        logger.error(error_message)
    
    def log_system(self, message: str, level: str = "INFO"):
        """
        Log system-wide messages (not tenant-specific)
        
        Args:
            message: System message
            level: Log level (INFO, WARNING, ERROR)
        """
        # System logger goes to console and system.log
        system_logger = logging.getLogger("watcher.system")
        
        if not system_logger.handlers:
            # Console handler
            console_handler = logging.StreamHandler()
            console_handler.setLevel(logging.INFO)
            
            # File handler
            file_handler = logging.FileHandler(
                os.path.join(self.log_dir, "system.log")
            )
            file_handler.setLevel(logging.INFO)
            
            # Format
            formatter = logging.Formatter(
                '[%(asctime)s] %(levelname)s: %(message)s',
                datefmt='%Y-%m-%d %H:%M:%S'
            )
            console_handler.setFormatter(formatter)
            file_handler.setFormatter(formatter)
            
            system_logger.addHandler(console_handler)
            system_logger.addHandler(file_handler)
            system_logger.setLevel(logging.INFO)
        
        # Log at appropriate level
        if level == "WARNING":
            system_logger.warning(message)
        elif level == "ERROR":
            system_logger.error(message)
        else:
            system_logger.info(message)