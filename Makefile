.PHONY: setup clean run

# Setup environment
setup:
	pip install -r requirements.txt
	@if [ ! -f .env ]; then cp .env.example .env; fi
	@echo "Please edit .env with your GOOGLE_API_KEY"

# Run the full pipeline
run:
	python src/main.py

# Clean generated artefacts (preserves prompts and manual labels)
clean:
	rm -rf data/generated/*
	rm -rf data/validation/checkov.json
	rm -rf data/validation/trivy.json
	rm -rf data/validation/localstack.json
	rm -rf data/validation/summary.json
	rm -rf data/validation/consolidated_report.csv
	rm -rf data/validation/validation_summary.csv
	rm -rf data/calibration/*
	rm -rf data/plots/*
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleaned generated artefacts. Kept: data/prompts/ and data/validation/reference_labels.csv"

# Clean everything including reference labels (use with caution)
clean-all: clean
	rm -f data/validation/reference_labels.csv
	@echo "Cleaned everything, including reference_labels.csv"