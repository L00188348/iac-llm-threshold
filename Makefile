.PHONY: setup clean

setup:
	pip install -r requirements.txt
	@if [ ! -f .env ]; then cp .env.example .env; fi
	@echo "Please edit .env with your GOOGLE_API_KEY"

clean:
	rm -rf data/runs/*
	rm -rf data/candidates/raw/*
	rm -rf logs/*
	rm -rf __pycache__ src/__pycache__ src/utils/__pycache__