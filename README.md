# IaC Threshold Calibration

This project implements an experimental pipeline to calibrate confidence thresholds for LLM‑generated Infrastructure‑as‑Code (Terraform).  
It uses **Gemini 3.1 Pro** for code generation, **CodeGenUQ** for uncertainty quantification, **Checkov/Trivy** for static analysis, and **LocalStack** for dynamic validation.

## Overview

The pipeline follows four phases:
1. Generate 5 candidate Terraform scripts per prompt.
2. Compute confidence scores using CodeGenUQ (`cosine_sim` scorer).
3. Validate candidates with Checkov, Trivy, and LocalStack `apply`.
4. Build a reference standard via human review and simulate threshold‑based decisions.

## Setup

1. Clone this repository.
2. Create a virtual environment and install dependencies:
   ```bash
   python -m venv venv
   source venv/bin/activate  # or `venv\Scripts\activate` on Windows
   pip install -r requirements.txt