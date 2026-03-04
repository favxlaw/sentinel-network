#!/usr/bin/env python3
"""
Test script for blockchain proxy service
Demonstrates:
- Cache backend switching
- Tenant isolation
- Cache hit/miss behavior
"""

import requests
import json
import time
from typing import Dict, Any

BASE_URL = "http://localhost:8006"

def print_header(text: str):
    """Print formatted section header"""
    print(f"\n{'=' * 70}")
    print(f"  {text}")
    print(f"{'=' * 70}\n")

def check_health() -> Dict[str, Any]:
    """Check service health"""
    response = requests.get(f"{BASE_URL}/health")
    return response.json()

def make_rpc_request(tenant_id: str, method: str, params: list) -> Dict[str, Any]:
    """Make an RPC request"""
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1
    }
    headers = {
        "X-Tenant-ID": tenant_id,
        "Content-Type": "application/json"
    }
    response = requests.post(f"{BASE_URL}/rpc", json=payload, headers=headers)
    return response.json()

def get_cache_stats() -> Dict[str, Any]:
    """Get cache statistics"""
    response = requests.get(f"{BASE_URL}/cache/stats")
    return response.json()

def clear_cache():
    """Clear all cache"""
    response = requests.post(f"{BASE_URL}/cache/clear")
    return response.json()

def test_cache_behavior():
    """Test cache hit/miss behavior"""
    print_header("Testing Cache Behavior")
    
    # Clear cache first
    print("Clearing cache...")
    clear_cache()
    time.sleep(0.5)
    
    # Test 1: Cacheable request (specific block number)
    print("Test 1: Requesting block 0x100 (CACHEABLE)")
    print("  Request #1 (should MISS)...")
    start = time.time()
    response1 = make_rpc_request("dao-alpha", "eth_getBlockByNumber", ["0x100", False])
    time1 = time.time() - start
    print(f" Response time: {time1:.3f}s")
    
    print("  Request #2 (should HIT)...")
    start = time.time()
    response2 = make_rpc_request("dao-alpha", "eth_getBlockByNumber", ["0x100", False])
    time2 = time.time() - start
    print(f" Response time: {time2:.3f}s")
    print(f"  Cache speedup: {time1/time2:.2f}x faster")
    
    # Test 2: Non-cacheable request (latest block)
    print("\nTest 2: Requesting 'latest' block (NOT CACHEABLE)")
    print("  Request #1...")
    start = time.time()
    response3 = make_rpc_request("dao-alpha", "eth_getBlockByNumber", ["latest", False])
    time3 = time.time() - start
    print(f" Response time: {time3:.3f}s")
    
    print("  Request #2...")
    start = time.time()
    response4 = make_rpc_request("dao-alpha", "eth_getBlockByNumber", ["latest", False])
    time4 = time.time() - start
    print(f" Response time: {time4:.3f}s")
    print(f"  No cache benefit (dynamic data)")
    
    # Show cache stats
    stats = get_cache_stats()
    print(f"\nCache Statistics:")
    print(f"  Backend: {stats.get('backend', 'unknown')}")
    print(f"  Total entries: {stats.get('total_entries', 0)}")
    if 'keyspace_hits' in stats:
        hits = stats['keyspace_hits']
        misses = stats['keyspace_misses']
        total = hits + misses
        hit_rate = (hits / total * 100) if total > 0 else 0
        print(f"  Hit rate: {hit_rate:.1f}% ({hits} hits, {misses} misses)")

def test_tenant_isolation():
    """Test tenant namespace isolation"""
    print_header("Testing Tenant Isolation")
    
    # Clear cache
    clear_cache()
    time.sleep(0.5)
    
    print("Requesting same block from different tenants...")
    
    # dao-alpha request
    print("\n1. dao-alpha requests block 0x200")
    response1 = make_rpc_request("dao-alpha", "eth_getBlockByNumber", ["0x200", False])
    print(f" Success: {bool(response1.get('result'))}")
    
    # dao-beta request (should also miss cache due to tenant isolation)
    print("\n2. dao-beta requests block 0x200 (different namespace)")
    start = time.time()
    response2 = make_rpc_request("dao-beta", "eth_getBlockByNumber", ["0x200", False])
    time2 = time.time() - start
    print(f"  Success: {bool(response2.get('result'))}")
    print(f"  Response time: {time2:.3f}s (cache MISS due to tenant isolation)")
    
    # dao-beta second request (should hit cache)
    print("\n3. dao-beta requests block 0x200 again (same namespace)")
    start = time.time()
    response3 = make_rpc_request("dao-beta", "eth_getBlockByNumber", ["0x200", False])
    time3 = time.time() - start
    print(f" Success: {bool(response3.get('result'))}")
    print(f" Response time: {time3:.3f}s (cache HIT)")
    print(f" Speedup: {time2/time3:.2f}x faster")
    
    # Show cache stats
    stats = get_cache_stats()
    print(f"\nCache has {stats.get('total_entries', 0)} entries (one per tenant)")

def test_invalid_tenant():
    """Test tenant validation"""
    print_header("Testing Tenant Validation")
    
    print("Attempting request with invalid tenant...")
    try:
        response = requests.post(
            f"{BASE_URL}/rpc",
            json={"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1},
            headers={"X-Tenant-ID": "dao-invalid"}
        )
        if response.status_code == 403:
            print("✓ Invalid tenant correctly rejected (403 Forbidden)")
        else:
            print(f"✗ Unexpected status code: {response.status_code}")
    except Exception as e:
        print(f"✗ Error: {e}")
    
    print("\nAttempting request without tenant header...")
    try:
        response = requests.post(
            f"{BASE_URL}/rpc",
            json={"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1}
        )
        if response.status_code == 400:
            print("✓ Missing tenant header correctly rejected (400 Bad Request)")
        else:
            print(f"✗ Unexpected status code: {response.status_code}")
    except Exception as e:
        print(f"✗ Error: {e}")

def main():
    """Run all tests"""
    print_header("Blockchain Proxy Service - Test Suite")
    
    # Check health
    print("Checking service health...")
    try:
        health = check_health()
        print(f"✓ Service is {health['status']}")
        print(f"✓ Web3 connected: {health['web3_connected']}")
        print(f"✓ Cache backend: {health['cache']['backend']}")
        print(f"✓ Cache connected: {health['cache']['connected']}")
    except Exception as e:
        print(f"✗ Service not available: {e}")
        print("\nMake sure the service is running:")
        print("  python main.py")
        return
    
    # Run tests
    try:
        test_cache_behavior()
        test_tenant_isolation()
        test_invalid_tenant()
        
        print_header("All Tests Completed")
        
        # Final stats
        stats = get_cache_stats()
        print("Final Cache Statistics:")
        print(json.dumps(stats, indent=2))
        
    except Exception as e:
        print(f"\n✗ Test failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()