import os
import yaml
import logging
import secrets
from typing import Dict, Optional
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

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
        
        # Database configuration - point to watcher's database
        # Use absolute path to avoid issues with working directory
        default_db = os.path.join(
            os.path.dirname(__file__),
            '../watcher-service/watcher.db'
        )
        self.db_path = os.getenv('SENTINEL_DB_PATH', default_db)
        
        # Tenant configuration file location
        self.tenant_config_path = os.getenv(
            'TENANT_CONFIG_PATH',
            '../watcher-service/config/tenants.yaml'  # Default to watcher-service location
        )
        
        # IPFS connection settings
        self.ipfs_host = os.getenv('IPFS_HOST', 'localhost')
        try:
            self.ipfs_port = int(os.getenv('IPFS_PORT', '5001'))
        except ValueError:
            logger.warning("Invalid IPFS_PORT, using default 5001")
            self.ipfs_port = 5001
        
        # API server settings
        self.api_host = os.getenv('API_HOST', '0.0.0.0')
        try:
            self.api_port = int(os.getenv('API_PORT', '8006'))
        except ValueError:
            logger.warning("Invalid API_PORT, using default 8006")
            self.api_port = 8006
        
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
        
        Supports TWO formats:
        
        Format 1 (List with 'id' field):
          tenants:
            - id: alpha
              api_key: key123
              watch_addresses: [...]
        
        Format 2 (Dict with tenant_id as key):
          tenants:
            alpha:
              api_key: key123
              watch_addresses: [...]
        
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
            
            # Handle empty file
            if not config_data:
                logger.error("Tenant config file is empty")
                return {}
            
            # Extract tenants
            tenants_data = config_data.get('tenants', {})
            
            if not tenants_data:
                logger.warning("No tenants found in configuration file")
                return {}
            
            # Determine format and process accordingly
            tenant_dict = {}
            
            # Format 1: List of dicts with 'id' field
            if isinstance(tenants_data, list):
                logger.debug("Processing tenants as list format")
                for tenant in tenants_data:
                    if not isinstance(tenant, dict):
                        logger.warning(f"Invalid tenant entry (not a dict): {tenant}")
                        continue
                        
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
            
            # Format 2: Dict with tenant_id as key
            elif isinstance(tenants_data, dict):
                logger.debug("Processing tenants as dict format")
                for tenant_id, tenant_config in tenants_data.items():
                    if not isinstance(tenant_config, dict):
                        logger.warning(f"Invalid config for tenant {tenant_id}: {tenant_config}")
                        continue
                    
                    # Add the 'id' field if it doesn't exist
                    if 'id' not in tenant_config:
                        tenant_config['id'] = tenant_id
                    
                    # Validate required fields
                    if not tenant_config.get('api_key'):
                        # Check environment for API key
                        env_key = os.getenv(f'TENANT_{tenant_id.upper().replace("-", "_")}_API_KEY')
                        if env_key:
                            tenant_config['api_key'] = env_key
                            logger.info(f"Loaded API key for {tenant_id} from environment")
                        else:
                            logger.error(f"Tenant {tenant_id} missing 'api_key', skipping")
                            continue
                    
                    # Store in dictionary
                    tenant_dict[tenant_id] = tenant_config
                    logger.debug(f"Loaded tenant: {tenant_id}")
            
            else:
                logger.error(f"Invalid tenants data type: {type(tenants_data)}")
                return {}
            
            logger.info(f"Successfully loaded {len(tenant_dict)} tenants")
            return tenant_dict
            
        except yaml.YAMLError as e:
            logger.error(f"Failed to parse YAML file: {e}")
            return {}
        except Exception as e:
            logger.error(f"Unexpected error loading tenants: {e}", exc_info=True)
            return {}
    
    def get_tenant(self, tenant_id: str) -> Optional[dict]:
        """
        Get configuration for a specific tenant.
        """
        return self.tenants.get(tenant_id)
    
    def get_tenant_by_api_key(self, api_key: str) -> Optional[str]:
        """
        Find which tenant owns this API key.
        
        Uses constant-time comparison to prevent timing attacks.
        
        This is the CORE of authentication:
        1. User sends API key in header
        2. We search through all tenants to find who has this key
        3. Return their tenant_id
        """
        if not api_key:
            return None
            
        for tenant_id, tenant_config in self.tenants.items():
            stored_key = tenant_config.get('api_key', '')
            if stored_key and secrets.compare_digest(stored_key, api_key):
                return tenant_id
        return None
    
    def reload_tenants(self):
        """Reload tenant configuration from file."""
        logger.info("Reloading tenant configuration")
        new_tenants = self._load_tenants()
        
        # Only replace if we successfully loaded tenants
        if new_tenants:
            self.tenants = new_tenants
            logger.info(f"Successfully reloaded {len(new_tenants)} tenants")
        else:
            logger.error("Failed to reload tenants - keeping existing configuration")
    
    def validate(self) -> bool:
        """Validate the configuration."""
        errors = []
        
        # Check database path is accessible
        db_dir = os.path.dirname(self.db_path)
        if db_dir and not os.path.exists(db_dir):
            # Try to create it
            try:
                os.makedirs(db_dir, exist_ok=True)
                logger.info(f"Created database directory: {db_dir}")
            except Exception as e:
                errors.append(f"Database directory doesn't exist and can't be created: {db_dir} - {e}")
        
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



settings = Config()


# Helper function for easy import
def get_config() -> Config:
    """Get the global configuration instance."""
    return settings