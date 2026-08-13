#!/usr/bin/env python3
"""
Main orchestration script for the IaC threshold calibration pipeline.
Executes the full pipeline: generation, validation, consolidation,
reference standard, calibration, and plotting.
"""

import subprocess
import sys
from pathlib import Path

# =============================================================================
# Configuration
# =============================================================================

SCRIPTS_DIR = Path("src")

# Script paths
GENERATE_SCRIPT = SCRIPTS_DIR / "generate_candidates.py"
VALIDATE_SCRIPT = SCRIPTS_DIR / "run_validation.py"
CONSOLIDATE_VALIDATION_SCRIPT = SCRIPTS_DIR / "consolidate_results.py"
BUILD_REFERENCE_SCRIPT = SCRIPTS_DIR / "build_reference_standard.py"
CHECK_THRESHOLD_SCRIPT = SCRIPTS_DIR / "check_threshold.py"
CALIBRATE_SCRIPT = SCRIPTS_DIR / "calibrate.py"
PLOT_SCRIPT = SCRIPTS_DIR / "plot_curves.py"


# =============================================================================
# Helper Functions
# =============================================================================

def run_script(script_path: Path) -> bool:
    """
    Run a Python script and return True if successful.
    """
    if not script_path.exists():
        print(f"Error: {script_path} not found.")
        return False

    print(f"\n{'='*60}")
    print(f"Running: {script_path.name}")
    print(f"{'='*60}")

    try:
        result = subprocess.run(
            [sys.executable, str(script_path)],
            capture_output=False,
            text=True,
        )
        return result.returncode == 0
    except Exception as e:
        print(f"Error running {script_path.name}: {e}")
        return False


def check_prerequisites() -> bool:
    """
    Check that all required directories and files exist.
    """
    # Check prompts file
    prompts_file = Path("data/prompts/prompts.json")
    if not prompts_file.exists():
        print(f"Error: {prompts_file} not found.")
        print("Please ensure the dataset is in place.")
        return False

    # Check that all scripts exist
    scripts = [
        GENERATE_SCRIPT,
        VALIDATE_SCRIPT,
        CONSOLIDATE_VALIDATION_SCRIPT,
        BUILD_REFERENCE_SCRIPT,
        CHECK_THRESHOLD_SCRIPT,
        CALIBRATE_SCRIPT,
        PLOT_SCRIPT,
    ]
    for script in scripts:
        if not script.exists():
            print(f"Error: {script} not found.")
            print("Please ensure all scripts are in place.")
            return False

    return True


# =============================================================================
# Main
# =============================================================================

def main():
    print("=" * 60)
    print("IaC Threshold Calibration Pipeline")
    print("=" * 60)

    # Check prerequisites
    if not check_prerequisites():
        print("\nPipeline aborted.")
        sys.exit(1)

    # Step 1: Generate candidates
    print("\n[Step 1/7] Generating candidates and confidence scores...")
    if not run_script(GENERATE_SCRIPT):
        print("\nPipeline aborted at generation phase.")
        sys.exit(1)

    # Step 2: Run validation
    print("\n[Step 2/7] Running automated validation...")
    if not run_script(VALIDATE_SCRIPT):
        print("\nPipeline aborted at validation phase.")
        sys.exit(1)

    # Step 3: Consolidate validation results
    print("\n[Step 3/7] Consolidating validation results...")
    if not run_script(CONSOLIDATE_VALIDATION_SCRIPT):
        print("\nPipeline aborted at consolidation phase.")
        sys.exit(1)

    # Step 4: Build reference standard (requires human labels)
    print("\n[Step 4/7] Building reference standard...")
    print("  Note: Ensure reference_labels.csv is populated before running this step.")
    if not run_script(BUILD_REFERENCE_SCRIPT):
        print("\nPipeline aborted at reference standard phase.")
        sys.exit(1)

    # Step 5: Check threshold data integrity
    print("\n[Step 5/7] Checking threshold data integrity...")
    if not run_script(CHECK_THRESHOLD_SCRIPT):
        print("\nPipeline aborted at check threshold phase.")
        sys.exit(1)

    # Step 6: Calibration
    print("\n[Step 6/7] Running threshold calibration...")
    if not run_script(CALIBRATE_SCRIPT):
        print("\nPipeline aborted at calibration phase.")
        sys.exit(1)

    # Step 7: Generate plots
    print("\n[Step 7/7] Generating trade-off curves...")
    if not run_script(PLOT_SCRIPT):
        print("\nPipeline aborted at plotting phase.")
        sys.exit(1)

    # Success
    print("\n" + "=" * 60)
    print("Pipeline completed successfully.")
    print("=" * 60)

    print("\nOutputs:")
    print(f"  - Generated candidates: data/generated/")
    print(f"  - Validation results: data/validation/")
    print(f"  - Validation summary: data/validation/validation_summary.csv")
    print(f"  - Consolidated report: data/validation/consolidated_report.csv")
    print(f"  - Calibration metrics: data/calibration/")
    print(f"  - Trade-off plots: data/plots/")


if __name__ == "__main__":
    main()