#!/usr/bin/env python3
"""
Build the reference standard by combining confidence scores and manual labels.

Reads:
- Confidence scores from data/generated/**/confidence_score.json
- Manual labels from data/validation/reference_labels.csv

Writes:
- Consolidated report to data/validation/consolidated_report.csv
"""

import json
import pandas as pd
from pathlib import Path

# =============================================================================
# Configuration
# =============================================================================

GENERATED_DIR = Path("data/generated")
VALIDATION_DIR = Path("data/validation")
LABELS_FILE = VALIDATION_DIR / "reference_labels.csv"
OUTPUT_FILE = VALIDATION_DIR / "consolidated_report.csv"


# =============================================================================
# Main
# =============================================================================

def main():
    # 1. Check if labels file exists
    if not LABELS_FILE.exists():
        print(f"Error: {LABELS_FILE} not found.")
        print("Please ensure the human reviewer has created the reference_labels.csv file.")
        print("Expected format: candidate_id,label (Trusted/Untrusted)")
        return

    # 2. Load manual labels
    labels_df = pd.read_csv(LABELS_FILE)
    print(f"Loaded {len(labels_df)} labels from {LABELS_FILE}")

    # 3. Load confidence scores from all generated candidates (recursively)
    scores = []
    # Find all confidence_score.json files in any subdirectory
    score_files = sorted(GENERATED_DIR.glob("**/confidence_score.json"))

    for score_file in score_files:
        # Extract candidate_id from the parent directory name
        # Example: .../level_1/p001/p001_c1/confidence_score.json -> p001_c1
        candidate_id = score_file.parent.name

        with open(score_file, "r") as f:
            data = json.load(f)
            scores.append({
                "candidate_id": candidate_id,
                "cosine_sim": data.get("cosine_sim"),
                "functional_equivalence_rate": data.get("functional_equivalence_rate"),
                "mean_confidence": data.get("mean_confidence"),
            })

    scores_df = pd.DataFrame(scores)
    print(f"Loaded {len(scores_df)} confidence scores from {GENERATED_DIR}")

    if scores_df.empty:
        print("No confidence scores found. Please run generate_candidates.py first.")
        return

    # 4. Merge scores with labels
    consolidated = scores_df.merge(labels_df, on="candidate_id", how="inner")
    print(f"Merged {len(consolidated)} candidates with labels")

    # 5. Check for missing candidates
    missing_scores = set(labels_df["candidate_id"]) - set(scores_df["candidate_id"])
    if missing_scores:
        print(f"Warning: {len(missing_scores)} candidates have labels but no confidence scores:")
        for candidate in sorted(missing_scores):
            print(f"  - {candidate}")

    missing_labels = set(scores_df["candidate_id"]) - set(labels_df["candidate_id"])
    if missing_labels:
        print(f"Warning: {len(missing_labels)} candidates have scores but no labels:")
        for candidate in sorted(missing_labels):
            print(f"  - {candidate}")

    # 6. Save consolidated report
    consolidated.to_csv(OUTPUT_FILE, index=False)
    print(f"\nConsolidated report saved to {OUTPUT_FILE}")
    print(f"Total candidates: {len(consolidated)}")
    print(f"Trusted: {len(consolidated[consolidated['label'] == 'Trusted'])}")
    print(f"Untrusted: {len(consolidated[consolidated['label'] == 'Untrusted'])}")


if __name__ == "__main__":
    main()