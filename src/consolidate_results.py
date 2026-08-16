#!/usr/bin/env python3
"""
Consolidate validation results into a single table.
Reads all summary.json files from data/validation/ and generates a CSV report.
"""

import json
import pandas as pd
from pathlib import Path

# =============================================================================
# Configuration
# =============================================================================

VALIDATION_DIR = Path("data/validation")
OUTPUT_FILE = Path("data/validation/validation_summary.csv")


# =============================================================================
# Main
# =============================================================================

def main():
    # Get all candidate summary files (recursively)
    summary_files = sorted(VALIDATION_DIR.glob("**/summary.json"))

    if not summary_files:
        print(f"No summary files found in {VALIDATION_DIR}")
        print("Run run_validation.py first.")
        return

    print(f"Found {len(summary_files)} summary files")

    # Collect data from each summary
    rows = []

    for summary_file in summary_files:
        # Extract candidate ID from the path
        # Example: level_1/p001/p001_c1 -> p001_c1
        candidate_id = summary_file.parent.name

        with open(summary_file, "r") as f:
            data = json.load(f)

        row = {
            "candidate_id": candidate_id,
            "level": data.get("level", "unknown"),
            "prompt_id": data.get("prompt_id", "unknown"),
            "checkov_status": data.get("checkov", {}).get("status", "unknown"),
            "checkov_findings": data.get("checkov", {}).get("findings_count", 0),
            "trivy_status": data.get("trivy", {}).get("status", "unknown"),
            "trivy_findings": data.get("trivy", {}).get("findings_count", 0),
            "terraform_status": data.get("terraform", {}).get("status", "unknown"),
        }

        rows.append(row)

    # Create DataFrame
    df = pd.DataFrame(rows)

    # Sort by candidate ID
    df = df.sort_values("candidate_id").reset_index(drop=True)

    # Save to CSV
    df.to_csv(OUTPUT_FILE, index=False)

    print(f"\nConsolidated report saved to {OUTPUT_FILE}")
    print(f"Total candidates: {len(df)}")

    # Statistics
    print("\nStatistics:")
    print(f"  Checkov - issues found: {len(df[df['checkov_findings'] > 0])} candidates")
    print(f"  Trivy - issues found: {len(df[df['trivy_status'] == 'issues_found'])} candidates")

    # Safely count Terraform statuses (handle potential missing column)
    if "terraform_status" in df.columns:
        terraform_success = len(df[df['terraform_status'] == 'success'])
        terraform_failed = len(df[df['terraform_status'].str.startswith('failed_')])
        terraform_timeout = len(df[df['terraform_status'].str.startswith('timeout_')])
        terraform_error = len(df[df['terraform_status'] == 'error'])

        print(f"  Terraform - success: {terraform_success} candidates")
        print(f"  Terraform - failed: {terraform_failed} candidates")
        print(f"  Terraform - timeout: {terraform_timeout} candidates")
        print(f"  Terraform - error: {terraform_error} candidates")
    else:
        print("  Terraform: no status data found")


if __name__ == "__main__":
    main()