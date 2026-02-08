import os
import yaml
import re
from typing import List, Optional, Dict, Any
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
    def __init__(self, config_path: Optional[str] = None):
        self.config_path = config_path or self._resolve_tenant_config_path()
        self.tenants: List[Tenant] = []

    def _interpolate_env(self, value):
        if isinstance(value, str):
            def replacer(match):
                var_name = match.group(1)
                return os.getenv(var_name, match.group(0))
            return re.sub(r"\$\{([^}]+)\}", replacer, value)
        if isinstance(value, dict):
            return {k: self._interpolate_env(v) for k, v in value.items()}
        if isinstance(value, list):
            return [self._interpolate_env(v) for v in value]
        return value

    def _load_services_config(self) -> Dict[str, Any]:
        default_path = os.path.join(os.path.dirname(__file__), "../config/services.yaml")
        config_path = os.getenv("SERVICE_CONFIG_PATH", default_path)
        if not os.path.exists(config_path):
            return {}
        with open(config_path, "r") as f:
            data = yaml.safe_load(f) or {}
        return self._interpolate_env(data)

    def _resolve_tenant_config_path(self) -> str:
        env_path = os.getenv("TENANT_CONFIG_PATH")
        if env_path:
            return env_path

        services_cfg = self._load_services_config()
        watcher_cfg = services_cfg.get("watcher", {})
        paths_cfg = services_cfg.get("paths", {})

        return (
            watcher_cfg.get("tenant_config_path")
            or paths_cfg.get("tenant_config")
            or "config/tenants.yaml"
        )

    def load(self) -> List[Tenant]:
        """
        Load tenants from the YAML configuration file
        """
        if not os.path.exists(self.config_path):
            raise FileNotFoundError(f"Config file not found: {self.config_path}")

        with open(self.config_path, "r") as file:
            config_data = yaml.safe_load(file)
        config_data = self._interpolate_env(config_data or {})

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
                    print(f"Invalid address for {tenant.id}: {address}")
                    return False

        print("All addresses validated")
        return True
    
    
