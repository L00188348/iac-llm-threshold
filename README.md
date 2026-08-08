# IaC Threshold Calibration
![Python Version](https://img.shields.io/badge/python-3.14-blue)
![Status](https://img.shields.io/badge/status-experimental-yellow)

This project implements an experimental pipeline to calibrate confidence thresholds for LLM-generated Infrastructure-as-Code (Terraform). It uses **Gemini 3.1 Pro** for code generation, **UQLM (CodeGenUQ)** for uncertainty quantification, **Checkov/Trivy** for static analysis, and **LocalStack** for dynamic validation.

## Pipeline Overview

The pipeline follows five phases, as defined in the methodology:

1. **Dataset and Prompts** – 60 prompts balanced across 5 complexity levels (stored in `data/prompts/prompts.json`).
2. **Code Generation and Confidence Estimation** – 5 candidate Terraform scripts generated per prompt; confidence scores computed using UQLM (`cosine_sim` scorer).
3. **Validation and Reference Standard** – Candidates validated with Checkov, Trivy, and LocalStack; human review assigns binary labels (Trusted/Untrusted).
4. **Threshold Calibration** – Systematic sweep of τ from 0.0 to 1.0 (step 0.1); Precision, Recall, and F1-Score calculated from the contingency matrix.
5. **Analysis and Trade-off Curves** – Performance curves generated per complexity stratum.

## Repository Structure
.
├── configs/
│ └── default.yaml # Pipeline configuration
├── data/
│ └── prompts/
│ └── prompts.json # 60 instructional prompts
├── src/
│ └── main.py # Main orchestration script
├── infra/
│ └── docker-compose.yml # LocalStack container definition
├── .env.example # Environment variables template
├── .gitignore
├── requirements.txt # Python dependencies
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
brew install checkov trivy terraform

### 4. Configure environment variables
cp .env.example .env
# Edit .env and set GOOGLE_API_KEY=your_key_here

### 5. Start LocalStack
cd infra
docker-compose up -d

### 6. Run the pipeline
python src/main.py --config configs/default.yaml

## Outputs

After running the pipeline, the following artefacts are generated in the `data/outputs/` directory:

- `metrics_per_threshold.csv` – Precision, Recall, F1 for each τ
- `tradeoff_curves/` – Plots for each complexity level
- `reference_labels.csv` – Trusted/Untrusted labels for all candidates

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.