"""
IPFS client for Sentinel Watcher
Posts event data to IPFS and retrieves Content IDs (CIDs)
"""

import requests
import json
import os
import yaml
import re
from dotenv import load_dotenv
from typing import Optional

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


def _load_services_config():
    default_path = os.path.join(os.path.dirname(__file__), "../config/services.yaml")
    config_path = os.getenv("SERVICE_CONFIG_PATH", default_path)
    if not os.path.exists(config_path):
        return {}
    with open(config_path, "r") as f:
        data = yaml.safe_load(f) or {}
    return _interpolate_env(data)

class IPFSClient:
    """
    Client for interacting with IPFS HTTP API
    """

    def __init__(self, api_url: str = None):
        """
        Initialize IPFS client
        
        Args:
            api_url: IPFS API endpoint (default from .env)
        """
        if api_url:
            self.api_url = api_url
        else:
            services_cfg = _load_services_config()
            watcher_cfg = services_cfg.get("watcher", {})
            ipfs_cfg = services_cfg.get("ipfs", {})
            self.api_url = (
                os.getenv("IPFS_API_URL")
                or watcher_cfg.get("ipfs_api_url")
                or ipfs_cfg.get("api_url")
            )
        self.enabled = False  # Will be True once IPFS node is running
        
        # Try to connect to IPFS
        try:
            self._check_connection()
            self.enabled = True
            print(f"IPFS client connected: {self.api_url}")
        except Exception as e:
            print(f"IPFS not available (will skip IPFS storage): {e}")
            print("   This is OK for now - we'll set up IPFS later")
    
    def _check_connection(self):
        """Check if IPFS daemon is running"""
        response = requests.post(
            f"{self.api_url}/api/v0/version",
            timeout=2
        )
        response.raise_for_status()
    
    def add_json(self, data: dict) -> Optional[str]:
        """
        Add JSON data to IPFS
        
        Args:
            data: Dictionary to store in IPFS
        
        Returns:
            CID (Content Identifier) or None if IPFS unavailable
        
        How it works:
        1. Convert dict to JSON string
        2. POST to IPFS /api/v0/add endpoint
        3. IPFS calculates SHA-256 hash of content
        4. Returns CID (hash in base58 format)
        5. Content now retrievable from any IPFS node using CID
        """
        if not self.enabled:
            return None  # Skip if IPFS not available
        
        try:
            # Convert to JSON
            json_str = json.dumps(data, indent=2)
            
            # Prepare file for upload
            files = {
                'file': ('event.json', json_str, 'application/json')
            }
            
            # POST to IPFS
            response = requests.post(
                f"{self.api_url}/api/v0/add",
                files=files,
                timeout=10
            )
            response.raise_for_status()
            
            # Extract CID from response
            result = response.json()
            cid = result['Hash']
            
            return cid
        
        except Exception as e:
            print(f"✗ IPFS storage failed: {e}")
            return None
    
    def get_json(self, cid: str) -> Optional[dict]:
        """
        Retrieve JSON data from IPFS using CID
        
        Args:
            cid: Content Identifier
        
        Returns:
            Retrieved data as dictionary, or None if not found
        """
        if not self.enabled:
            return None
        
        try:
            response = requests.post(
                f"{self.api_url}/api/v0/cat",
                params={'arg': cid},
                timeout=10
            )
            response.raise_for_status()
            
            return response.json()
        
        except Exception as e:
            print(f"✗ IPFS retrieval failed: {e}")
            return None
    
    def pin_cid(self, cid: str) -> bool:
        """
        Pin CID to ensure it stays on this node
        
        Args:
            cid: Content Identifier to pin
        
        Returns:
            True if pinned successfully
        """
        if not self.enabled:
            return False
        
        try:
            response = requests.post(
                f"{self.api_url}/api/v0/pin/add",
                params={'arg': cid},
                timeout=10
            )
            response.raise_for_status()
            return True
        
        except Exception as e:
            print(f"✗ IPFS pinning failed: {e}")
            return False
