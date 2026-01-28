import os
import yaml
from typing import List, Optional
from dataclasses import dataclass


# -----------------------------
# Data model for a Tenant
# -----------------------------
@dataclass
class Tenant:
    id: str
    watch_addresses: List[str]
    alert_threshold_eth: float


# -----------------------------
# Config loader class
# -----------------------------
class ConfigLoader:
    def __init__(self, config_path: str = "config/tenants.yaml"):
        self.config_path = config_path
        self.tenants: List[Tenant] = []

    def load(self) -> List[Tenant]:
        """
        Load tenants from the YAML configuration file
        """
        if not os.path.exists(self.config_path):
            raise FileNotFoundError(f"Config file not found: {self.config_path}")

        with open(self.config_path, "r") as file:
            config_data = yaml.safe_load(file)

        tenants_data = config_data.get("tenants", {})

        self.tenants = []
        # Handle both list and dict formats
        if isinstance(tenants_data, list):
            # If it's a list, iterate normally
            for tenant_dict in tenants_data:
                tenant = Tenant(
                    id=tenant_dict["id"],
                    watch_addresses=tenant_dict["watch_addresses"],
                    alert_threshold_eth=tenant_dict["alert_threshold_eth"],
                )
                self.tenants.append(tenant)
        elif isinstance(tenants_data, dict):
            # If it's a dict, extract id from key and merge with values
            for tenant_id, tenant_config in tenants_data.items():
                tenant = Tenant(
                    id=tenant_id,
                    watch_addresses=tenant_config["watch_addresses"],
                    alert_threshold_eth=tenant_config["alert_threshold_eth"],
                )
                self.tenants.append(tenant)

        print(f"Loaded {len(self.tenants)} tenants from config")
        return self.tenants

    def get_tenant_by_id(self, tenant_id: str) -> Optional[Tenant]:
        """
        Find and return a tenant by its ID
        """
        for tenant in self.tenants:
            if tenant.id == tenant_id:
                return tenant
        return None

    def validate(self) -> bool:
        """
        Validate Ethereum addresses for all tenants
        """
        for tenant in self.tenants:
            for address in tenant.watch_addresses:
                if not address.startswith("0x") or len(address) != 42:
                    print(f"✗ Invalid address for {tenant.id}: {address}")
                    return False

        print("All addresses validated")
        return True
    
    
