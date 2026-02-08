"""
Blockchain interaction for Sentinel Watcher
Connects to Ethereum via Web3.py and processes blocks
"""

from web3 import Web3
from typing import List, Dict, Optional
import os
import yaml
import re
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


def _load_services_config():
    default_path = os.path.join(os.path.dirname(__file__), "../config/services.yaml")
    config_path = os.getenv("SERVICE_CONFIG_PATH", default_path)
    if not os.path.exists(config_path):
        return {}
    with open(config_path, "r") as f:
        data = yaml.safe_load(f) or {}
    return _interpolate_env(data)

class BlockchainConnector:
    """
    Handles connection to Ethereum blockchain and transaction processing
    """
    def __init__(self):
        """Initialize Web3 connection to Ethereum"""
        services_cfg = _load_services_config()
        watcher_cfg = services_cfg.get("watcher", {})

        # Build RPC URL: prefer explicit RPC_URL env var, otherwise use services.yaml
        explicit = os.getenv("RPC_URL")
        if explicit:
            rpc_url = explicit
        elif watcher_cfg.get("rpc_url"):
            rpc_url = watcher_cfg.get("rpc_url")
        else:
            rpc_provider = os.getenv("RPC_PROVIDER", "alchemy")
            if rpc_provider == "alchemy":
                api_key = os.getenv("ALCHEMY_API_KEY", "")
                if not api_key:
                    raise ValueError("ALCHEMY_API_KEY not set")
                rpc_url = f"https://eth-sepolia.g.alchemy.com/v2/{api_key}"
            elif rpc_provider == "infura":
                api_key = os.getenv("INFURA_API_KEY", "")
                if not api_key:
                    raise ValueError("INFURA_API_KEY not set")
                rpc_url = f"https://sepolia.infura.io/v3/{api_key}"
            else:
                raise ValueError(f"Unknown RPC provider: {rpc_provider}")
        # Create Web3 instance
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        # Verify connection
        if not self.w3.is_connected():
            raise ConnectionError("Failed to connect to Ethereum network")
        
        print(f"Connected to Ethereum (Chain ID: {self.w3.eth.chain_id})")
    
    def get_latest_block_number(self) -> int:
        """
        Get the most recent block number
        
        Returns:
            Latest block number on chain
        """
        return self.w3.eth.block_number
    
    def get_block_with_transactions(self, block_number: int) -> Optional[Dict]:
        """
        Fetch a specific block with all its transactions
        
        Args:
            block_number: Which block to fetch
        
        Returns:
            Block data with transactions, or None if block doesn't exist
        
        Why full_transactions=True?
        - We need transaction details (from, to, value)
        - Without it, we only get transaction hashes
        """
        try:
            block = self.w3.eth.get_block(block_number, full_transactions=True)
            return block
        except Exception as e:
            print(f"✗ Error fetching block {block_number}: {e}")
            return None
    
    def extract_transactions(self, block: Dict, watch_addresses: List[str]) -> List[Dict]:
        """
        Extract relevant transactions from a block
        
        Args:
            block: Block data from blockchain
            watch_addresses: List of addresses we're monitoring
        
        Returns:
            List of transactions involving watched addresses
        
        Transaction filtering logic:
        1. Check if 'to' or 'from' matches watched addresses
        2. Only include successful transactions (not reverted)
        3. Convert Wei to ETH for easier reading
        """
        relevant_txs = []
        
        # Normalize addresses to lowercase for comparison
        # Ethereum addresses are case-insensitive
        watch_addresses_lower = [addr.lower() for addr in watch_addresses]
        
        for tx in block.transactions:
            # Skip if transaction has no 'to' address (contract creation)
            if tx['to'] is None:
                continue
            
            # Check if transaction involves any watched address
            from_addr = tx['from'].lower()
            to_addr = tx['to'].lower()
            
            if from_addr in watch_addresses_lower or to_addr in watch_addresses_lower:
                # Convert Wei to ETH (1 ETH = 10^18 Wei)
                value_eth = self.w3.from_wei(tx['value'], 'ether')
                
                relevant_txs.append({
                    'tx_hash': tx['hash'].hex(),
                    'from_address': tx['from'],
                    'to_address': tx['to'],
                    'value_eth': float(value_eth),
                    'block_number': block['number'],
                    'timestamp': block['timestamp'],
                    'gas_used': tx.get('gas', 0)
                })
        
        return relevant_txs
    
    def is_address_valid(self, address: str) -> bool:
        """
        Validate Ethereum address format
        
        Args:
            address: Ethereum address to validate
        
        Returns:
            True if valid, False otherwise
        """
        return self.w3.is_address(address)
    
    def get_balance(self, address: str) -> float:
        """
        Get ETH balance of an address
        
        Args:
            address: Ethereum address
        
        Returns:
            Balance in ETH
        """
        try:
            balance_wei = self.w3.eth.get_balance(address)
            return float(self.w3.from_wei(balance_wei, 'ether'))
        except Exception as e:
            print(f"✗ Error getting balance for {address}: {e}")
            return 0.0
