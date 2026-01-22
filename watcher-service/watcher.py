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

        tenant_list = config_data.get("tenants", [])

        self.tenants = []
        for tenant_dict in tenant_list:
            tenant = Tenant(
                id=tenant_dict["id"],
                watch_addresses=tenant_dict["watch_addresses"],
                alert_threshold_eth=tenant_dict["alert_threshold_eth"],
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
    
    
