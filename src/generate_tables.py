#!/usr/bin/env python3
"""
Generate tables for the dissertation from consolidated_report.csv.
Creates:
1. Contingency matrix for each tau
2. Metrics summary (Precision, Recall, F1)
3. Best threshold per level
"""

import pandas as pd
from pathlib import Path

# =============================================================================
# Configuration
# =============================================================================

INPUT_FILE = Path("data/validation/consolidated_report.csv")
OUTPUT_DIR = Path("data/tables")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

THRESHOLDS = [round(i/10, 1) for i in range(0, 11)]  # [0.0, 0.1, ..., 1.0]


# =============================================================================
# Helper Functions
# =============================================================================

def compute_metrics(df, tau):
    """Compute contingency matrix and metrics for a given threshold."""
    df_pred = df.copy()
    df_pred["predicted"] = df_pred["mean_confidence"] >= tau

    HCST = len(df_pred[(df_pred["predicted"] == True) & (df_pred["label"] == "Trusted")])
    HCSU = len(df_pred[(df_pred["predicted"] == True) & (df_pred["label"] == "Untrusted")])
    LCST = len(df_pred[(df_pred["predicted"] == False) & (df_pred["label"] == "Trusted")])
    LCSU = len(df_pred[(df_pred["predicted"] == False) & (df_pred["label"] == "Untrusted")])

    precision = HCST / (HCST + HCSU) if (HCST + HCSU) > 0 else 0
    recall = HCST / (HCST + LCST) if (HCST + LCST) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

    return {
        "tau": tau,
        "HCST": HCST,
        "HCSU": HCSU,
        "LCST": LCST,
        "LCSU": LCSU,
        "precision": precision,
        "recall": recall,
        "f1": f1,
    }


def format_metrics_table(results_df):
    """Format metrics for display."""
    df = results_df.copy()
    df["precision"] = df["precision"].map("{:.3f}".format)
    df["recall"] = df["recall"].map("{:.3f}".format)
    df["f1"] = df["f1"].map("{:.3f}".format)
    return df


# =============================================================================
# Main
# =============================================================================

def main():
    # Load data
    if not INPUT_FILE.exists():
        print(f"Error: {INPUT_FILE} not found.")
        print("Please run build_reference_standard.py first.")
        return

    df = pd.read_csv(INPUT_FILE)
    print(f"Loaded {len(df)} candidates from {INPUT_FILE}")

    # Compute metrics for all thresholds
    all_results = []
    for tau in THRESHOLDS:
        all_results.append(compute_metrics(df, tau))

    results_df = pd.DataFrame(all_results)

    # ========================================================================
    # 1. Contingency Matrix Table (for each tau)
    # ========================================================================
    print("\n" + "="*60)
    print("TABLE 1: Contingency Matrix per Threshold")
    print("="*60)

    contingency_table = results_df[["tau", "HCST", "HCSU", "LCST", "LCSU"]].copy()
    print(contingency_table.to_string(index=False))

    # Save as CSV
    contingency_table.to_csv(OUTPUT_DIR / "contingency_matrix.csv", index=False)
    print(f"\nSaved to: {OUTPUT_DIR / 'contingency_matrix.csv'}")

    # ========================================================================
    # 2. Metrics Table (Precision, Recall, F1)
    # ========================================================================
    print("\n" + "="*60)
    print("TABLE 2: Performance Metrics per Threshold")
    print("="*60)

    metrics_table = results_df[["tau", "precision", "recall", "f1"]].copy()
    metrics_table["precision"] = metrics_table["precision"].map("{:.3f}".format)
    metrics_table["recall"] = metrics_table["recall"].map("{:.3f}".format)
    metrics_table["f1"] = metrics_table["f1"].map("{:.3f}".format)
    print(metrics_table.to_string(index=False))

    # Save as CSV
    metrics_table.to_csv(OUTPUT_DIR / "performance_metrics.csv", index=False)
    print(f"\nSaved to: {OUTPUT_DIR / 'performance_metrics.csv'}")

    # ========================================================================
    # 3. Best F1 per threshold
    # ========================================================================
    print("\n" + "="*60)
    print("TABLE 3: Best Performance")
    print("="*60)

    best_idx = results_df["f1"].idxmax()
    best_tau = results_df.loc[best_idx, "tau"]
    best_f1 = results_df.loc[best_idx, "f1"]
    best_precision = results_df.loc[best_idx, "precision"]
    best_recall = results_df.loc[best_idx, "recall"]

    print(f"Best F1-Score: {best_f1:.3f}")
    print(f"Threshold (τ): {best_tau}")
    print(f"Precision: {best_precision:.3f}")
    print(f"Recall: {best_recall:.3f}")

    # ========================================================================
    # 4. Markdown table for LaTeX (copy to dissertation)
    # ========================================================================
    print("\n" + "="*60)
    print("MARKDOWN TABLE (copy to dissertation)")
    print("="*60)

    print("\n### Contingency Matrix\n")
    print("| τ | HCST | HCSU | LCST | LCSU |")
    print("| :---: | :---: | :---: | :---: | :---: |")
    for _, row in contingency_table.iterrows():
        print(f"| {row['tau']:.1f} | {row['HCST']} | {row['HCSU']} | {row['LCST']} | {row['LCSU']} |")

    print("\n### Performance Metrics\n")
    print("| τ | Precision | Recall | F1-Score |")
    print("| :---: | :---: | :---: | :---: |")
    for _, row in metrics_table.iterrows():
        print(f"| {row['tau']:.1f} | {row['precision']} | {row['recall']} | {row['f1']} |")


if __name__ == "__main__":
    main()