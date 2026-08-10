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
OUTPUT_FILE = Path("data/validation/consolidated_report.csv")


# =============================================================================
# Main
# =============================================================================

def main():
    # Get all candidate summary files
    summary_files = sorted(VALIDATION_DIR.glob("*/summary.json"))

    if not summary_files:
        print(f"No summary files found in {VALIDATION_DIR}")
        print("Run run_validation.py first.")
        return

    print(f"Found {len(summary_files)} summary files")

    # Collect data from each summary
    rows = []

    for summary_file in summary_files:
        candidate_id = summary_file.parent.name

        with open(summary_file, "r") as f:
            data = json.load(f)

        row = {
            "candidate_id": candidate_id,
            "checkov_status": data.get("checkov", {}).get("status", "unknown"),
            "checkov_findings": data.get("checkov", {}).get("findings_count", 0),
            "trivy_status": data.get("trivy", {}).get("status", "unknown"),
            "trivy_findings": data.get("trivy", {}).get("findings_count", 0),
            "localstack_status": data.get("localstack", {}).get("status", "unknown"),
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
    print(f"  Checkov - issues found: {len(df[df['checkov_status'] == 'issues_found'])} candidates")
    print(f"  Trivy - issues found: {len(df[df['trivy_status'] == 'issues_found'])} candidates")
    print(f"  LocalStack - success: {len(df[df['localstack_status'] == 'success'])} candidates")
    print(f"  LocalStack - failed: {len(df[df['localstack_status'].str.startswith('failed')])} candidates")


if __name__ == "__main__":
    main()