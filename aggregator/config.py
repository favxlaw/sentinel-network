import os
import yaml
import logging
from typing import Dict, Optional
from pathlib import Path

logger = logging.getLogger(__name__)


class Config:
    """
    Configuration container.
    """
    
    def __init__(self):
        """
        Initialize configuration by loading from files and environment.
        
        This runs when you create a Config object: config = Config()
        """
        self._load_environment()
        self.tenants = self._load_tenants()
        
        logger.info(f"Configuration loaded: {len(self.tenants)} tenants, DB: {self.db_path}")
    
    def _load_environment(self):
        """
        Load configuration from environment variables.
        """
        
        # Database configuration
        self.db_path = os.getenv(
            'SENTINEL_DB_PATH',
            '/var/lib/sentinel/sentinel.db'
        )
        
        # Tenant configuration file location
        self.tenant_config_path = os.getenv(
            'TENANT_CONFIG_PATH',
            '/etc/sentinel/tenants.yaml'
        )
        
        # IPFS connection settings
        self.ipfs_host = os.getenv('IPFS_HOST', 'localhost')
        self.ipfs_port = int(os.getenv('IPFS_PORT'))
        
        # API server settings
        self.api_host = os.getenv('API_HOST')
        self.api_port = int(os.getenv('API_PORT'))
        
        # Logging level
        self.log_level = os.getenv('LOG_LEVEL', 'INFO')
        
        # Environment type (development, staging, production)
        self.environment = os.getenv('ENVIRONMENT', 'development')
        
        # Optional: CloudWatch configuration (for AWS monitoring)
        self.cloudwatch_enabled = os.getenv('CLOUDWATCH_ENABLED', 'false').lower() == 'true'
        self.cloudwatch_log_group = os.getenv('CLOUDWATCH_LOG_GROUP', '/sentinel/aggregator')
    
    def _load_tenants(self) -> Dict[str, dict]:
        """
        Load tenant configuration from YAML file.
        Returns:
            Dictionary mapping tenant_id to tenant configuration dict.
        """
        try:
            # Check if file exists
            if not os.path.exists(self.tenant_config_path):
                logger.error(f"Tenant config file not found: {self.tenant_config_path}")
                return {}
            
            # Read YAML file
            with open(self.tenant_config_path, 'r') as f:
                config_data = yaml.safe_load(f)
            
            # Extract tenants list
            tenant_list = config_data.get('tenants', [])
            
            if not tenant_list:
                logger.warning("No tenants found in configuration file")
                return {}
            
            # Convert list to dictionary
            tenant_dict = {}
            for tenant in tenant_list:
                tenant_id = tenant.get('id')
                if not tenant_id:
                    logger.warning(f"Tenant missing 'id' field, skipping: {tenant}")
                    continue
                
                # Validate required fields
                if not tenant.get('api_key'):
                    logger.error(f"Tenant {tenant_id} missing 'api_key', skipping")
                    continue
                
                # Store in dictionary
                tenant_dict[tenant_id] = tenant
                logger.debug(f"Loaded tenant: {tenant_id}")
            
            logger.info(f"Successfully loaded {len(tenant_dict)} tenants")
            return tenant_dict
            
        except yaml.YAMLError as e:
            logger.error(f"Failed to parse YAML file: {e}")
            return {}
        except Exception as e:
            logger.error(f"Unexpected error loading tenants: {e}")
            return {}
    
    def get_tenant(self, tenant_id: str) -> Optional[dict]:
        """
        Get configuration for a specific tenant.
        """
        return self.tenants.get(tenant_id)
    
    def get_tenant_by_api_key(self, api_key: str) -> Optional[str]:
        """
        Find which tenant owns this API key.
        
        This is the CORE of authentication:
        1. User sends API key in header
        2. We search through all tenants to find who has this key
        3. Return their tenant_id
        
        """
        for tenant_id, tenant_config in self.tenants.items():
            if tenant_config.get('api_key') == api_key:
                return tenant_id
        return None
    
    def reload_tenants(self):
        logger.info("Reloading tenant configuration")
        self.tenants = self._load_tenants()
    
    def validate(self) -> bool:
        errors = []
        
        # Check database path is accessible
        db_dir = os.path.dirname(self.db_path)
        if not os.path.exists(db_dir):
            errors.append(f"Database directory doesn't exist: {db_dir}")
        
        # Check tenant config exists
        if not os.path.exists(self.tenant_config_path):
            errors.append(f"Tenant config file not found: {self.tenant_config_path}")
        
        # Check at least one tenant
        if not self.tenants:
            errors.append("No tenants configured")
        
        # Validate each tenant
        for tenant_id, tenant_config in self.tenants.items():
            # Check required fields
            required_fields = ['id', 'api_key', 'watch_addresses', 'alert_threshold_eth']
            for field in required_fields:
                if field not in tenant_config:
                    errors.append(f"Tenant {tenant_id} missing required field: {field}")
            
            # Check API key is not default/weak
            api_key = tenant_config.get('api_key', '')
            if 'CHANGE_THIS' in api_key or len(api_key) < 20:
                errors.append(f"Tenant {tenant_id} has weak/default API key")
        
        # Log errors
        if errors:
            for error in errors:
                logger.error(f"Configuration validation error: {error}")
            return False
        
        logger.info("Configuration validation passed")
        return True


# Create a global config instance
# This allows other modules to import and use: from config import settings
settings = Config()


# Helper function for easy import
def get_config() -> Config:
    return settings