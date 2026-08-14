#!/usr/bin/env python3
"""
Run automated validation on all generated candidates.
Executes Checkov, Trivy, and LocalStack (Terraform) for each candidate.
"""

import json
import subprocess
import sys
from pathlib import Path

# =============================================================================
# Configuration
# =============================================================================

GENERATED_DIR = Path("data/generated")
VALIDATION_DIR = Path("data/validation")
VALIDATION_DIR.mkdir(parents=True, exist_ok=True)


# =============================================================================
# Validation Functions
# =============================================================================

def run_checkov(candidate_dir: Path) -> dict:
    """
    Run Checkov static analysis on a Terraform directory.
    Returns a dict with findings count and raw output.
    """
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
    """
    Run Trivy vulnerability scanning on a Terraform directory.
    Returns a dict with findings count and raw output.
    """
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


def run_localstack(candidate_dir: Path) -> dict:
    """
    Run Terraform apply on a candidate directory using LocalStack.
    Returns a dict with execution status and details.
    """
    result = {
        "status": "success",
        "steps": {},
        "error": None,
    }

    terraform_commands = [
        ("init", ["tflocal", "init"], 60),
        ("validate", ["tflocal", "validate"], 60),
        ("plan", ["tflocal", "plan"], 120),
        ("apply", ["tflocal", "apply", "-auto-approve"], 180),
    ]

    for step_name, cmd, timeout in terraform_commands:
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(candidate_dir),
                capture_output=True,
                text=True,
                timeout=timeout,
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
            result["steps"][step_name] = {
                "status": "timeout",
                "returncode": None,
                "stdout": "",
                "stderr": "",
            }
            break
        except FileNotFoundError:
            result["status"] = "error"
            result["error"] = "Terraform not found. Please install it."
            result["steps"][step_name] = {
                "status": "error",
                "returncode": None,
                "stdout": "",
                "stderr": "",
            }
            break
        except Exception as e:
            result["status"] = "error"
            result["error"] = str(e)
            result["steps"][step_name] = {
                "status": "error",
                "returncode": None,
                "stdout": "",
                "stderr": "",
            }
            break

    return result


def save_validation_results_nested(relative_path: Path, checkov_result: dict, trivy_result: dict, localstack_result: dict) -> None:
    """
    Save validation results to JSON files, preserving the nested directory structure.
    """
    candidate_dir = VALIDATION_DIR / relative_path
    candidate_dir.mkdir(parents=True, exist_ok=True)

    with open(candidate_dir / "checkov.json", "w") as f:
        json.dump(checkov_result, f, indent=2)

    with open(candidate_dir / "trivy.json", "w") as f:
        json.dump(trivy_result, f, indent=2)

    with open(candidate_dir / "localstack.json", "w") as f:
        json.dump(localstack_result, f, indent=2)

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
        "localstack": {
            "status": localstack_result["status"],
        },
    }
    with open(candidate_dir / "summary.json", "w") as f:
        json.dump(summary, f, indent=2)


# =============================================================================
# Main
# =============================================================================
def main():
    print("DEBUG: main() started")
    print(f"Looking for candidates in: {GENERATED_DIR}")

    # Get all candidate directories (recursively)
    candidate_dirs = sorted(GENERATED_DIR.glob("**/*_c*"))

    print(f"Found {len(candidate_dirs)} candidate directories")

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

        localstack_result = run_localstack(candidate_dir)
        print(f"  LocalStack: {localstack_result['status']}")

        save_validation_results_nested(relative_path, checkov_result, trivy_result, localstack_result)

        print(f"  Results saved to data/validation/{relative_path}/\n")

    print("All validations complete.")
    print("Results stored in data/validation/")


if __name__ == "__main__":
    main()