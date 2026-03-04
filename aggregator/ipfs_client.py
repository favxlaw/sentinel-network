import requests
import json
import os
from dotenv import load_dotenv
from typing import Optional

load_dotenv()


class IPFSClient:
    """Client for retrieving data from IPFS HTTP API"""

    def __init__(self, api_url: str = None):
        """
        Initialize IPFS client
        
        Args:
            api_url: IPFS API endpoint (default from .env)
        """
        ipfs_host = os.getenv('IPFS_HOST', '127.0.0.1')
        ipfs_port = os.getenv('IPFS_PORT', '5001')
        self.api_url = api_url or os.getenv('IPFS_API_URL') or f"http://{ipfs_host}:{ipfs_port}"
        self.enabled = False
        
        # Try to connect to IPFS
        try:
            self._check_connection()
            self.enabled = True
            print(f"✓ IPFS client connected: {self.api_url}")
        except Exception as e:
            print(f"✗ IPFS not available: {e}")
            self.enabled = False
    
    def _check_connection(self):
        """Check if IPFS daemon is running"""
        response = requests.post(
            f"{self.api_url}/api/v0/version",
            timeout=2
        )
        response.raise_for_status()
    
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
            print(f"IPFS retrieval failed for CID {cid}: {e}")
            return None
