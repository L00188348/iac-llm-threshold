#!/usr/bin/env python3
"""
Run automated validation on all generated candidates.
Executes Checkov, Trivy, and Terraform plan for each candidate.
Uses LocalStack endpoints via environment variables to avoid real AWS calls.
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# =============================================================================
# Configuration
# =============================================================================

BASE_DIR = Path(__file__).resolve().parent.parent   
GENERATED_DIR = BASE_DIR / "data" / "generated"
VALIDATION_DIR = BASE_DIR / "data" / "validation"
VALIDATION_DIR.mkdir(parents=True, exist_ok=True)

# =============================================================================
# Helper Functions
# =============================================================================

def load_env_file():
    """Load environment variables from .env file if it exists."""
    env_file = BASE_DIR / ".env"
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    key, value = line.split("=", 1)
                    os.environ[key] = value.strip('"').strip("'")
        print("DEBUG: Loaded .env file")
    else:
        print("DEBUG: No .env file found; relying on existing environment variables")


def get_variable_block(tf_content: str, var_name: str) -> str | None:
    """
    Extract a variable's body by counting brace depth.
    This correctly handles nested braces inside type definitions
    like object({...}) or list(object({...})).
    """
    # Use re.escape to safely match the variable name
    pattern = rf'variable\s+"{re.escape(var_name)}"\s*\{{'
    match = re.search(pattern, tf_content)
    if not match:
        return None

    start = match.end()          # position after the opening '{'
    depth = 1                    # we are inside one block now
    i = start
    while i < len(tf_content) and depth > 0:
        if tf_content[i] == '{':
            depth += 1
        elif tf_content[i] == '}':
            depth -= 1
        i += 1

    if depth != 0:
        # Unbalanced braces – return None to signal failure
        return None

    # Return the content between the outer braces (excluding them)
    return tf_content[start:i-1]


def detect_variables(candidate_dir: Path) -> list:
    """Detect all variables defined in main.tf."""
    tf_file = candidate_dir / "main.tf"
    if not tf_file.exists():
        return []
    
    tf_content = tf_file.read_text()
    vars_list = []
    for line in tf_content.splitlines():
        if 'variable "' in line:
            name = line.split('"')[1]
            vars_list.append(name)
    return vars_list


def get_variable_type(tf_content: str, var_name: str) -> str:
    """Extract the type of a variable from main.tf."""
    block = get_variable_block(tf_content, var_name)
    if block is None:
        return 'unknown'
    
    type_match = re.search(r'type\s*=\s*(\S+)', block)
    if type_match:
        type_str = type_match.group(1).strip()
        if 'string' in type_str:
            return 'string'
        elif 'number' in type_str:
            return 'number'
        elif 'bool' in type_str:
            return 'bool'
        elif 'list' in type_str:
            return 'list'
        elif 'map' in type_str:
            return 'map'
        elif 'object' in type_str:
            return 'object'
    return 'unknown'


def get_variable_default(tf_content: str, var_name: str) -> str | None:
    """
    Return a truthy string if the variable has a default assignment,
    or None otherwise.
    """
    block = get_variable_block(tf_content, var_name)
    if block is None:
        return None

    # We only need to know if "default" exists inside the block.
    # The regex below matches the start of the default assignment.
    default_match = re.search(r'default\s*=\s*', block)
    return default_match.group(0).strip() if default_match else None


def create_tfvars(candidate_dir: Path) -> None:
    """
    Create terraform.tfvars with type-aware default values ONLY for variables
    that do NOT already have a default in main.tf.
    """
    tf_file = candidate_dir / "main.tf"
    if not tf_file.exists():
        return
    
    tf_content = tf_file.read_text()
    var_names = detect_variables(candidate_dir)
    if not var_names:
        return
    
    tfvars_lines = []
    for var in var_names:
        var_type = get_variable_type(tf_content, var)
        default_val = get_variable_default(tf_content, var)

        # If the variable already has a default, skip creating a tfvars entry
        if default_val is not None:
            continue

        # ------------------------------------------------------------------
        # Generate a placeholder value for variables without default
        # ------------------------------------------------------------------
        if var_type == 'number':
            # Some variables require specific ranges; use sensible fallbacks
            if var == "message_retention_seconds":
                tfvars_lines.append(f'{var} = 1209600')
            elif var == "delay_seconds":
                tfvars_lines.append(f'{var} = 5')
            elif var == "retention_days":
                tfvars_lines.append(f'{var} = 90')
            elif var == "volume_size":
                tfvars_lines.append(f'{var} = 100')
            elif var == "threshold":
                tfvars_lines.append(f'{var} = 80')
            elif var == "evaluation_periods":
                tfvars_lines.append(f'{var} = 2')
            elif var == "period":
                tfvars_lines.append(f'{var} = 300')
            elif var == "min_size":
                tfvars_lines.append(f'{var} = 1')
            elif var == "max_size":
                tfvars_lines.append(f'{var} = 3')
            elif var == "desired_capacity":
                tfvars_lines.append(f'{var} = 2')
            else:
                tfvars_lines.append(f'{var} = 30')
        elif var_type == 'bool':
            tfvars_lines.append(f'{var} = true')
        elif var_type == 'list':
            tfvars_lines.append(f'{var} = []')
        elif var_type in ('map', 'object'):
            tfvars_lines.append(f'{var} = {{}}')
        else:  # string or unknown
            if var == "vpc_id":
                tfvars_lines.append(f'{var} = "vpc-12345678"')
            elif var == "subnet_ids":
                tfvars_lines.append(f'{var} = ["subnet-12345678", "subnet-87654321"]')
            elif var == "ami_id":
                tfvars_lines.append(f'{var} = "ami-0c55b159cbfafe1f0"')
            elif var == "bucket_name":
                tfvars_lines.append(f'{var} = "test-bucket"')
            elif var == "queue_name":
                tfvars_lines.append(f'{var} = "test-queue"')
            elif var == "topic_name":
                tfvars_lines.append(f'{var} = "test-topic.fifo"')
            elif var == "table_name":
                tfvars_lines.append(f'{var} = "test-table"')
            elif var == "role_name":
                tfvars_lines.append(f'{var} = "test-role"')
            elif var == "function_name":
                tfvars_lines.append(f'{var} = "test-function"')
            elif var == "log_group_name":
                tfvars_lines.append(f'{var} = "/aws/test"')
            elif var == "key_name":
                tfvars_lines.append(f'{var} = "test-key"')
            elif var == "key_alias":
                tfvars_lines.append(f'{var} = "alias/test-key"')
            elif "arn" in var:
                tfvars_lines.append(f'{var} = "arn:aws:iam::000000000000:role/test-role"')
            else:
                tfvars_lines.append(f'{var} = "test-value"')
    
    tfvars_path = candidate_dir / "terraform.tfvars"
    if tfvars_lines:
        with open(tfvars_path, "w") as f:
            f.write("\n".join(tfvars_lines))
    else:
        # Remove any stale terraform.tfvars from previous runs
        if tfvars_path.exists():
            tfvars_path.unlink()


def create_dummy_files(candidate_dir: Path) -> None:
    """
    Create dummy files that may be referenced by Lambda/archive_file/local_file.
    This prevents Terraform plan from failing due to missing local files.
    """
    main_tf = candidate_dir / "main.tf"
    if not main_tf.exists():
        return

    content = main_tf.read_text()

    # Create directory/file for archive_file if source_dir is referenced
    for m in re.finditer(r'source_dir\s*=\s*"([^"]+)"', content):
        source_dir = candidate_dir / m.group(1)
        source_dir.mkdir(parents=True, exist_ok=True)
        dummy_file = source_dir / "index.py"
        if not dummy_file.exists():
            dummy_file.write_text("def handler(event, context):\n    return {}\n")

    # Create zip files/filenames commonly referenced if they are referenced
    for m in re.finditer(r'filename\s*=\s*"([^"]+\.zip)"', content):
        zip_path = candidate_dir / m.group(1)
        if not zip_path.exists():
            zip_path.write_bytes(b"PK\x05\x06" + b"\x00" * 18)  # zip vazio

    # Create local JSON if referenced by jsondecode
    for m in re.finditer(r'jsondecode\(file\("([^"]+\.json)"\)\)', content):
        json_path = candidate_dir / m.group(1)
        if not json_path.exists():
            json_path.write_text("{}")


# =============================================================================
# Validation Functions
# =============================================================================

def run_checkov(candidate_dir: Path) -> dict:
    """Run Checkov static analysis on a Terraform directory."""
    result = {
        "status": "success",
        "findings_count": 0,
        "raw_output": "",
        "error": None,
    }
    try:
        cmd = ["checkov", "-d", str(candidate_dir), "--output", "json"]
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
            env=os.environ,
        )
        if proc.returncode != 0:
            result["status"] = "issues_found"
        try:
            data = json.loads(proc.stdout)
            failed_checks = data.get("results", {}).get("failed_checks", [])
            result["findings_count"] = len(failed_checks)
        except json.JSONDecodeError:
            result["findings_count"] = 0
        result["raw_output"] = proc.stdout
    except subprocess.TimeoutExpired:
        result["status"] = "timeout"
        result["error"] = "Checkov execution timed out"
    except FileNotFoundError:
        result["status"] = "error"
        result["error"] = "Checkov not found. Please install it."
    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)
    return result


def run_trivy(candidate_dir: Path) -> dict:
    """Run Trivy vulnerability scanning on a Terraform directory."""
    result = {
        "status": "success",
        "findings_count": 0,
        "raw_output": "",
        "error": None,
    }
    try:
        cmd = ["trivy", "config", "--format", "json", str(candidate_dir)]
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
            env=os.environ,
        )
        if proc.returncode != 0:
            result["status"] = "issues_found"
        try:
            data = json.loads(proc.stdout)
            results = data.get("Results", [])
            total_findings = 0
            for res in results:
                total_findings += len(res.get("Vulnerabilities", []))
            result["findings_count"] = total_findings
        except json.JSONDecodeError:
            result["findings_count"] = 0
        result["raw_output"] = proc.stdout
    except subprocess.TimeoutExpired:
        result["status"] = "timeout"
        result["error"] = "Trivy execution timed out"
    except FileNotFoundError:
        result["status"] = "error"
        result["error"] = "Trivy not found. Please install it."
    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)
    return result


def run_terraform_validation(candidate_dir: Path) -> dict:
    """
    Run terraform init and plan to validate the configuration.
    Uses environment variables to point AWS to LocalStack.
    """
    result = {"status": "success", "steps": {}, "error": None}

    # Create tfvars only for variables without a default.
    create_tfvars(candidate_dir)

    # Create dummy files needed for archive_file/local_file
    create_dummy_files(candidate_dir)

    # Do not create provider.tf — use env vars to avoid duplication
    env = os.environ.copy()
    env.update({
        "AWS_ACCESS_KEY_ID": "test",
        "AWS_SECRET_ACCESS_KEY": "test",
        "AWS_DEFAULT_REGION": "us-east-1",
        "AWS_SKIP_CREDENTIALS_VALIDATION": "true",
        "AWS_SKIP_REQUESTING_ACCOUNT_ID": "true",
        "AWS_SKIP_METADATA_API_CHECK": "true",
        "AWS_ENDPOINT_URL": "http://localhost:4566",
        "AWS_ENDPOINT_URL_STS": "http://localhost:4566",
        "AWS_ENDPOINT_URL_S3": "http://localhost:4566",
        "AWS_ENDPOINT_URL_SQS": "http://localhost:4566",
        "AWS_ENDPOINT_URL_SNS": "http://localhost:4566",
        "AWS_ENDPOINT_URL_DYNAMODB": "http://localhost:4566",
        "AWS_ENDPOINT_URL_IAM": "http://localhost:4566",
        "AWS_ENDPOINT_URL_EC2": "http://localhost:4566",
        "AWS_ENDPOINT_URL_LAMBDA": "http://localhost:4566",
        "AWS_ENDPOINT_URL_CLOUDWATCH": "http://localhost:4566",
        "AWS_ENDPOINT_URL_LOGS": "http://localhost:4566",
        "AWS_ENDPOINT_URL_KMS": "http://localhost:4566",
        "AWS_ENDPOINT_URL_ECS": "http://localhost:4566",
        "AWS_ENDPOINT_URL_ELBV2": "http://localhost:4566",
        "AWS_ENDPOINT_URL_APIGATEWAYV2": "http://localhost:4566",
    })

    terraform_commands = [
        ("init", ["terraform", "init"], 120),
        ("plan", ["terraform", "plan"], 120),
    ]

    for step_name, cmd, timeout in terraform_commands:
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(candidate_dir),
                capture_output=True,
                text=True,
                timeout=timeout,
                env=env,
            )
            result["steps"][step_name] = {
                "status": "success" if proc.returncode == 0 else "failed",
                "returncode": proc.returncode,
                "stdout": proc.stdout,
                "stderr": proc.stderr,
            }
            if proc.returncode != 0:
                result["status"] = f"failed_at_{step_name}"
                result["error"] = f"Terraform {step_name} failed"
                break
        except subprocess.TimeoutExpired:
            result["status"] = f"timeout_at_{step_name}"
            result["error"] = f"Terraform {step_name} timed out"
            break
        except Exception as e:
            result["status"] = "error"
            result["error"] = str(e)
            break

    return result


def save_validation_results_nested(
    relative_path: Path,
    checkov_result: dict,
    trivy_result: dict,
    terraform_result: dict
) -> None:
    """Save validation results to JSON files, preserving nested structure."""
    candidate_dir = VALIDATION_DIR / relative_path
    candidate_dir.mkdir(parents=True, exist_ok=True)

    with open(candidate_dir / "checkov.json", "w") as f:
        json.dump(checkov_result, f, indent=2)

    with open(candidate_dir / "trivy.json", "w") as f:
        json.dump(trivy_result, f, indent=2)

    with open(candidate_dir / "terraform.json", "w") as f:
        json.dump(terraform_result, f, indent=2)

    summary = {
        "candidate_id": relative_path.name,
        "level": relative_path.parent.parent.name,
        "prompt_id": relative_path.parent.name,
        "checkov": {
            "status": checkov_result["status"],
            "findings_count": checkov_result["findings_count"],
        },
        "trivy": {
            "status": trivy_result["status"],
            "findings_count": trivy_result["findings_count"],
        },
        "terraform": {
            "status": terraform_result["status"],
        },
    }
    with open(candidate_dir / "summary.json", "w") as f:
        json.dump(summary, f, indent=2)


def configure_terraform_plugin_cache():
    cache_dir = Path.home() / ".terraform.d" / "plugin-cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    os.environ["TF_PLUGIN_CACHE_DIR"] = str(cache_dir)


# =============================================================================
# Main
# =============================================================================

def main():
    print("DEBUG: main() started")
    load_env_file()
    configure_terraform_plugin_cache()
    print(f"Looking for candidates in: {GENERATED_DIR}")

    candidate_dirs = sorted(GENERATED_DIR.glob("**/*_c*"))
    print(f"Found {len(candidate_dirs)} candidate directories")

    # For testing: optional limit 
    # LIMIT = 10 
    # candidate_dirs = candidate_dirs[:LIMIT]

    if not candidate_dirs:
        print("No candidate directories found in", GENERATED_DIR)
        print("Run generate_candidates.py first.")
        sys.exit(1)

    print("Running validations...\n")

    for candidate_dir in candidate_dirs:
        relative_path = candidate_dir.relative_to(GENERATED_DIR)
        print(f"Processing {relative_path}...")

        checkov_result = run_checkov(candidate_dir)
        print(f"  Checkov: {checkov_result['status']} (findings: {checkov_result['findings_count']})")

        trivy_result = run_trivy(candidate_dir)
        print(f"  Trivy: {trivy_result['status']} (findings: {trivy_result['findings_count']})")

        terraform_result = run_terraform_validation(candidate_dir)
        print(f"  Terraform: {terraform_result['status']}")

        save_validation_results_nested(
            relative_path,
            checkov_result,
            trivy_result,
            terraform_result
        )
        print(f"  Results saved to data/validation/{relative_path}/\n")

    print("All validations complete.")
    print("Results stored in data/validation/")


if __name__ == "__main__":
    main()