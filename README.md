# IaC Threshold Calibration

![Python Version](https://img.shields.io/badge/python-3.11+-blue)
![Status](https://img.shields.io/badge/status-experimental-yellow)

This project implements an experimental pipeline to calibrate confidence thresholds for LLM-generated Infrastructure-as-Code (Terraform). It uses **Gemini 3.1 Pro** for code generation, **UQLM (CodeGenUQ)** for uncertainty quantification, **Checkov/Trivy** for static analysis, and **LocalStack** for dynamic validation.

## Pipeline Overview

The pipeline follows five phases, as defined in the methodology:

1. **Dataset and Prompts** – 60 prompts balanced across 5 complexity levels (stored in `data/prompts/prompts.json`).
2. **Code Generation and Confidence Estimation** – 5 candidate Terraform scripts generated per prompt; confidence scores computed using UQLM (`cosine_sim` and `functional_equivalence_rate`).
3. **Validation and Reference Standard** – Candidates validated with Checkov, Trivy, and LocalStack (`tflocal`); human review assigns binary labels (Trusted/Untrusted).
4. **Threshold Calibration** – Systematic sweep of τ from 0.0 to 1.0 (step 0.1); Precision, Recall, and F1-Score calculated from the contingency matrix.
5. **Analysis and Trade-off Curves** – Performance curves generated per complexity stratum.

## Repository Structure
.
├── configs/
│ └── default.yaml # Pipeline configuration
├── data/
│ ├── prompts/
│ │ └── prompts.json # 60 instructional prompts
│ ├── generated/ # Generated scripts (ignored by Git)
│ ├── validation/ # Validation reports (ignored by Git)
│ ├── calibration/ # Calibration metrics (ignored by Git)
│ └── plots/ # Generated plots (ignored by Git)
├── src/
│ ├── main.py # Main orchestration script
│ ├── generate_candidates.py # Phase 2: code generation
│ ├── run_validation.py # Phase 3: automated validation
│ ├── consolidate_results.py # Phase 3: consolidate validation
│ ├── build_reference_standard.py # Phase 3: build reference standard
│ ├── check_threshold.py # Phase 4: data integrity check
│ ├── calibrate.py # Phase 4: threshold calibration
│ └── plot_curves.py # Phase 5: trade-off curves
├── infra/
│ └── docker-compose.yml # LocalStack container definition
├── .env.example # Environment variables template
├── .gitignore
├── requirements.txt # Python dependencies
├── Makefile # Convenience commands
└── README.md


## Setup

### 1. Clone the repository

```bash
git clone https://github.com/L00188348/iac-llm-threshold.git
cd iac-llm-threshold

### 2. Create a virtual environment and install dependencies
python3 -m venv venv
source venv/bin/activate  # On macOS/Linux
# or `venv\Scripts\activate` on Windows
pip install -r requirements.txt

### 3. Install external CLI tools
# On macOS (using Homebrew)
brew install checkov trivy terraform

# Install tflocal (wrapper for LocalStack)
pip install terraform-local

### 4. Configure environment variables
cp .env.example .env
# Edit .env and set GOOGLE_API_KEY=your_key_here

### 5. Start LocalStack
cd infra
docker-compose up -d

### 6. Run the pipeline
make run

# Or manually:
python src/main.py

## Outputs

After running the pipeline, the following artefacts are generated:

data/validation/validation_summary.csv – Validation results summary (Checkov, Trivy, LocalStack)

data/validation/consolidated_report.csv – Confidence scores + manual labels (reference standard)

data/calibration/calibration_total.csv – Performance metrics for all thresholds

data/calibration/calibration_level_*.csv – Performance metrics per complexity level

data/plots/ – Trade-off curves (Precision/Recall vs τ, F1 vs τ, PR curves)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.