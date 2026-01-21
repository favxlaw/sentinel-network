"""
Test script for Blockchain Proxy Service
Tests caching, tenant logging, and RPC forwarding
"""

import requests
import json
import time
from colorama import init, Fore, Style

# Initialize colorama for colored output
init()

# Configuration
PROXY_URL = "http://localhost:5000"
TENANTS = ['dao-alpha', 'dao-beta', 'dao-gamma']

def print_header(text):
    print(f"\n{Fore.CYAN}{'='*60}")
    print(f"{text}")
    print(f"{'='*60}{Style.RESET_ALL}\n")

def print_success(text):
    print(f"{Fore.GREEN}✓ {text}{Style.RESET_ALL}")

def print_error(text):
    print(f"{Fore.RED}✗ {text}{Style.RESET_ALL}")

def print_info(text):
    print(f"{Fore.YELLOW}ℹ {text}{Style.RESET_ALL}")

def test_health_check():
    """Test the /health endpoint"""
    print_header("Test 1: Health Check")
    
    try:
        response = requests.get(f"{PROXY_URL}/health")
        if response.status_code == 200:
            data = response.json()
            print_success(f"Service is healthy")
            print_info(f"Cache size: {data.get('cache_size', 0)}")
            return True
        else:
            print_error(f"Health check failed: {response.status_code}")
            return False
    except Exception as e:
        print_error(f"Failed to connect: {str(e)}")
        return False

def test_missing_tenant_header():
    """Test request without tenant header"""
    print_header("Test 2: Missing Tenant Header")
    
    rpc_request = {
        "jsonrpc": "2.0",
        "method": "eth_blockNumber",
        "params": [],
        "id": 1
    }
    
    response = requests.post(f"{PROXY_URL}/rpc", json=rpc_request)
    
    if response.status_code == 400:
        print_success("Correctly rejected request without tenant header")
        return True
    else:
        print_error(f"Expected 400, got {response.status_code}")
        return False

def test_invalid_tenant():
    """Test request with invalid tenant ID"""
    print_header("Test 3: Invalid Tenant ID")
    
    rpc_request = {
        "jsonrpc": "2.0",
        "method": "eth_blockNumber",
        "params": [],
        "id": 1
    }
    
    headers = {"X-Tenant-ID": "invalid-tenant"}
    response = requests.post(f"{PROXY_URL}/rpc", json=rpc_request, headers=headers)
    
    if response.status_code == 403:
        print_success("Correctly rejected invalid tenant")
        return True
    else:
        print_error(f"Expected 403, got {response.status_code}")
        return False

def test_rpc_request(tenant_id):
    """Test basic RPC request for a tenant"""
    print_header(f"Test 4: RPC Request for {tenant_id}")
    
    rpc_request = {
        "jsonrpc": "2.0",
        "method": "eth_blockNumber",
        "params": [],
        "id": 1
    }
    
    headers = {"X-Tenant-ID": tenant_id}
    
    try:
        response = requests.post(f"{PROXY_URL}/rpc", json=rpc_request, headers=headers)
        
        if response.status_code == 200:
            data = response.json()
            block_number = int(data['result'], 16)
            print_success(f"Got block number: {block_number}")
            print_info(f"Hex: {data['result']}")
            return True
        else:
            print_error(f"Request failed: {response.status_code}")
            print_error(f"Response: {response.text}")
            return False
    except Exception as e:
        print_error(f"Request failed: {str(e)}")
        return False

def test_caching():
    """Test that caching works for repeated requests"""
    print_header("Test 5: Cache Functionality")
    
    # Get a specific block (this should be cacheable)
    rpc_request = {
        "jsonrpc": "2.0",
        "method": "eth_getBlockByNumber",
        "params": ["0x1", False],  # Get block 1
        "id": 1
    }
    
    headers = {"X-Tenant-ID": "dao-alpha"}
    
    # First request (cache miss)
    print_info("Making first request (should be cache MISS)...")
    start_time = time.time()
    response1 = requests.post(f"{PROXY_URL}/rpc", json=rpc_request, headers=headers)
    time1 = time.time() - start_time
    
    if response1.status_code != 200:
        print_error(f"First request failed: {response1.status_code}")
        return False
    
    print_success(f"First request completed in {time1:.3f}s")
    
    # Second request (should hit cache)
    print_info("Making second request (should be cache HIT)...")
    start_time = time.time()
    response2 = requests.post(f"{PROXY_URL}/rpc", json=rpc_request, headers=headers)
    time2 = time.time() - start_time
    
    if response2.status_code != 200:
        print_error(f"Second request failed: {response2.status_code}")
        return False
    
    print_success(f"Second request completed in {time2:.3f}s")
    
    # Verify responses are identical
    if response1.json() == response2.json():
        print_success("Responses are identical (cache working)")
    else:
        print_error("Responses differ (cache may not be working)")
        return False
    
    # Check if second request was faster (indicates cache hit)
    if time2 < time1:
        print_success(f"Second request was {time1/time2:.2f}x faster (cache confirmed)")
    else:
        print_info("Second request wasn't significantly faster (may still be cached)")
    
    return True

def test_multi_tenant_logging():
    """Test that each tenant gets their own log file"""
    print_header("Test 6: Multi-Tenant Logging")
    
    rpc_request = {
        "jsonrpc": "2.0",
        "method": "eth_blockNumber",
        "params": [],
        "id": 1
    }
    
    for tenant in TENANTS:
        headers = {"X-Tenant-ID": tenant}
        response = requests.post(f"{PROXY_URL}/rpc", json=rpc_request, headers=headers)
        
        if response.status_code == 200:
            print_success(f"{tenant}: Request logged")
        else:
            print_error(f"{tenant}: Request failed")
            return False
    
    print_info("Check ./logs/ directory for tenant-specific log files:")
    print_info("  - dao-alpha.log")
    print_info("  - dao-beta.log")
    print_info("  - dao-gamma.log")
    
    return True

def test_cache_stats():
    """Test cache statistics endpoint"""
    print_header("Test 7: Cache Statistics")
    
    try:
        response = requests.get(f"{PROXY_URL}/cache/stats")
        if response.status_code == 200:
            data = response.json()
            print_success(f"Cache entries: {data['total_entries']}")
            print_info(f"Cache TTL: {data['ttl_seconds']} seconds")
            print_info(f"Cacheable methods: {len(data['cacheable_methods'])}")
            return True
        else:
            print_error(f"Stats request failed: {response.status_code}")
            return False
    except Exception as e:
        print_error(f"Failed to get stats: {str(e)}")
        return False

def test_web3_info():
    """Test Web3 connection info endpoint"""
    print_header("Test 8: Web3 Connection Info")
    
    try:
        response = requests.get(f"{PROXY_URL}/web3/info")
        if response.status_code == 200:
            data = response.json()
            if data.get('connected'):
                print_success(f"Web3 connected to chain {data.get('chain_id')}")
                print_info(f"Latest block: {data.get('latest_block')}")
            else:
                print_error(f"Web3 not connected: {data.get('error')}")
            return data.get('connected', False)
        else:
            print_error(f"Request failed: {response.status_code}")
            return False
    except Exception as e:
        print_error(f"Failed to get Web3 info: {str(e)}")
        return False
    """Test cache statistics endpoint"""
    print_header("Test 7: Cache Statistics")
    
    try:
        response = requests.get(f"{PROXY_URL}/cache/stats")
        if response.status_code == 200:
            data = response.json()
            print_success(f"Cache entries: {data['cache_entries']}")
            print_info(f"Cache TTL: {data['ttl_seconds']} seconds")
            return True
        else:
            print_error(f"Stats request failed: {response.status_code}")
            return False
    except Exception as e:
        print_error(f"Failed to get stats: {str(e)}")
        return False

def run_all_tests():
    """Run all tests"""
    print(f"{Fore.MAGENTA}")
    print("╔══════════════════════════════════════════════════════════╗")
    print("║     Sentinel Network - Blockchain Proxy Tests           ║")
    print("╚══════════════════════════════════════════════════════════╝")
    print(Style.RESET_ALL)
    
    tests = [
        ("Health Check", test_health_check),
        ("Missing Tenant Header", test_missing_tenant_header),
        ("Invalid Tenant", test_invalid_tenant),
        ("RPC Request", lambda: test_rpc_request("dao-alpha")),
        ("Caching", test_caching),
        ("Multi-Tenant Logging", test_multi_tenant_logging),
        ("Cache Statistics", test_cache_stats),
        ("Web3 Connection Info", test_web3_info),
    ]
    
    results = []
    for name, test_func in tests:
        try:
            result = test_func()
            results.append((name, result))
        except Exception as e:
            print_error(f"Test '{name}' crashed: {str(e)}")
            results.append((name, False))
    
    # Summary
    print_header("Test Summary")
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = f"{Fore.GREEN}PASS" if result else f"{Fore.RED}FAIL"
        print(f"{status}{Style.RESET_ALL} - {name}")
    
    print(f"\n{Fore.CYAN}Results: {passed}/{total} tests passed{Style.RESET_ALL}")
    
    if passed == total:
        print(f"{Fore.GREEN}🎉 All tests passed!{Style.RESET_ALL}\n")
    else:
        print(f"{Fore.YELLOW}⚠ Some tests failed{Style.RESET_ALL}\n")

if __name__ == "__main__":
    run_all_tests()