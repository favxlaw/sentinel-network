#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: ./scripts/deploy.sh [deploy|destroy|reprovision <instance>]"
}

check_prereqs() {
  if ! command -v terraform >/dev/null 2>&1; then
    echo "Error: terraform is not installed or not in PATH."
    exit 1
  fi

  if ! command -v aws >/dev/null 2>&1; then
    echo "Error: aws CLI is not installed or not in PATH."
    exit 1
  fi

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "Error: AWS credentials are not configured or are invalid."
    exit 1
  fi
}

print_outputs() {
  echo
  echo "Terraform outputs:"
  for output_name in bastion_public_ip nginx_public_ip nat_public_ip backend_private_ip; do
    if terraform output -raw "${output_name}" >/dev/null 2>&1; then
      echo "  ${output_name}: $(terraform output -raw "${output_name}")"
    fi
  done

  if terraform output -raw nginx_public_ip >/dev/null 2>&1; then
    local nginx_ip
    nginx_ip="$(terraform output -raw nginx_public_ip)"
    echo
    echo "Reminder: update /etc/hosts for sentinel.local subdomains using NGINX IP ${nginx_ip}."
  else
    echo
    echo "Reminder: update /etc/hosts for sentinel.local subdomains using the NGINX public IP."
  fi
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
INSTANCE="${2:-}"

check_prereqs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}/infra"

case "${COMMAND}" in
  deploy)
    terraform init
    terraform plan -out=tfplan
    terraform apply tfplan
    rm -f tfplan
    print_outputs
    ;;
  destroy)
    read -r -p "Are you sure you want to destroy all infrastructure? Type 'yes' to continue: " confirm
    if [[ "${confirm}" != "yes" ]]; then
      echo "Destroy cancelled."
      exit 0
    fi
    terraform init
    terraform destroy
    ;;
  reprovision)
    if [[ -z "${INSTANCE}" ]]; then
      usage
      exit 1
    fi
    case "${INSTANCE}" in
      nat|bastion|nginx|backend) ;;
      *)
        echo "Error: invalid instance '${INSTANCE}'. Valid values: nat, bastion, nginx, backend."
        exit 1
        ;;
    esac
    terraform init
    terraform apply -replace="aws_instance.${INSTANCE}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
