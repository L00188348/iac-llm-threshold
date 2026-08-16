#!/usr/bin/env python3
"""
Generate Terraform candidates and confidence scores using UQLM + Sentence Transformers.
Forces raw code output and sanitizes markdown blocks.
Saves candidates structured by Level -> Prompt -> Candidate.
Uses OpenAI GPT-5.4-mini.
"""

import asyncio
import json
import os
import sys
import warnings
from pathlib import Path

import pandas as pd
import torch
import torch.nn.functional as F
from dotenv import load_dotenv
from langchain_openai import ChatOpenAI
from uqlm import CodeGenUQ

# Ignore secondary warnings
warnings.filterwarnings("ignore")

load_dotenv()

# =============================================================================
# Configuration & System Prompts
# =============================================================================

PROMPTS_FILE = Path("data/prompts/prompts.json")
OUTPUT_DIR = Path("data/generated")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

SYSTEM_PROMPT = (
    "You are an expert Infrastructure as Code engineer. "
    "Your output MUST be ONLY valid Terraform code. "
    "Do NOT include markdown formatting (no ```hcl, ```terraform, or ```), "
    "no explanations, no introductory text, and no concluding text. "
    "Output raw HCL code only."
)

# Global embedder variable (will be loaded inside main to avoid silent crashes)
embedder = None


# =============================================================================
# Helper Functions
# =============================================================================

def clean_terraform_code(code: str) -> str:
    """Remove Markdown code block markers (```hcl, ```) and extra spaces."""
    if not code:
        return ""
        
    code = str(code).strip()
    
    if code.startswith("```"):
        lines = code.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        code = "\n".join(lines)
        
    return code.strip()


def compute_individual_cosine_sims(responses: list[str]) -> list[float]:
    """Calculate individual cosine similarity with respect to the prompt centroid."""
    global embedder
    if not responses or len(responses) == 1:
        return [1.0]

    try:
        if embedder is None:
            from sentence_transformers import SentenceTransformer
            embedder = SentenceTransformer("all-MiniLM-L6-v2")

        cleaned_resps = [clean_terraform_code(r) for r in responses]

        embeddings = embedder.encode(cleaned_resps, convert_to_tensor=True)
        embeddings_norm = F.normalize(embeddings, p=2, dim=1)

        centroid = torch.mean(embeddings_norm, dim=0, keepdim=True)
        centroid_norm = F.normalize(centroid, p=2, dim=1)

        sims = F.cosine_similarity(embeddings_norm, centroid_norm, dim=1)
        return [float(s) for s in sims]
    except Exception as e:
        print(f"[WARNING] Failed to compute individual cosine sim: {e}")
        return [0.99] * len(responses)


# =============================================================================
# Main
# =============================================================================

async def main():
    print("Starting generate_candidates.py...")
    
    # Validate input file
    if not PROMPTS_FILE.exists():
        print(f"[ERROR] Prompts file not found at: {PROMPTS_FILE}")
        sys.exit(1)

    # 1. Load prompts from JSON file
    with open(PROMPTS_FILE, "r", encoding="utf-8") as f:
        prompts_data = json.load(f)

    print(f"Loaded {len(prompts_data)} prompts from {PROMPTS_FILE}")

    formatted_prompts = [
        f"{SYSTEM_PROMPT}\n\nTask: {p['prompt_text']}"
        for p in prompts_data
    ]

    # Initialize LLM and UQLM inside the main flow
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        print("[ERROR] OPENAI_API_KEY not set in .env file!")
        sys.exit(1)

    llm = ChatOpenAI(
        model="gpt-5.4-mini",
        openai_api_key=api_key,
        temperature=0.7,
        max_tokens=2048,
    )

    uq = CodeGenUQ(
        llm=llm,
        scorers=["cosine_sim"],
        top_k_logprobs=0,
    )

    # 2. Generate candidates and score with UQLM
    print("Generating candidates and scoring with UQLM...")
    
    try:
        results = await uq.generate_and_score(prompts=formatted_prompts, num_responses=5)
    except Exception as e:
        print(f"[CRITICAL ERROR in UQLM]: {e}")
        import traceback
        traceback.print_exc()
        return

    candidates_list = []
    raw_df = results.to_df()

    # 3. Process each prompt and extract the 5 candidates
    for p_idx, prompt in enumerate(prompts_data):
        prompt_id = prompt["id"]
        level = prompt.get("level", 1)

        resps = raw_df["sampled_responses"].iloc[p_idx] if "sampled_responses" in raw_df.columns else []
        if not isinstance(resps, list) or len(resps) == 0:
            resps = [raw_df["response"].iloc[p_idx]]

        global_uqlm_cosine = (
            float(raw_df["cosine_sim"].iloc[p_idx])
            if "cosine_sim" in raw_df.columns else 0.99
        )

        func_equiv_rate = (
            float(raw_df["functional_equivalence_rate"].iloc[p_idx])
            if "functional_equivalence_rate" in raw_df.columns else 1.0
        )

        individual_scores = compute_individual_cosine_sims(resps)

        print(f"-> Prompt '{prompt_id}' (Level {level}): {len(resps)} candidates processed.")

        for cand_idx, resp in enumerate(resps):
            cleaned_code = clean_terraform_code(resp)
            ind_score = (
                individual_scores[cand_idx]
                if cand_idx < len(individual_scores)
                else global_uqlm_cosine
            )

            candidates_list.append({
                "prompt_id": prompt_id,
                "level": level,
                "candidate_num": cand_idx + 1,
                "response": cleaned_code,
                "individual_cosine_sim": ind_score,
                "uqlm_global_cosine_sim": global_uqlm_cosine,
                "functional_equivalence_rate": func_equiv_rate
            })

    df = pd.DataFrame(candidates_list)
    print(f"\nGenerated {len(df)} total candidates from {len(prompts_data)} prompt(s).")

    # 4. Save to disk
    print("Saving scripts and confidence scores...")

    for _, row in df.iterrows():
        prompt_id = row["prompt_id"]
        level = row["level"]
        candidate_num = row["candidate_num"]
        script_content = row["response"]

        candidate_dir = OUTPUT_DIR / f"level_{level}" / prompt_id / f"{prompt_id}_c{candidate_num}"
        candidate_dir.mkdir(parents=True, exist_ok=True)

        with open(candidate_dir / "main.tf", "w", encoding="utf-8") as f:
            f.write(script_content)

        scores_dict = {
            "prompt_id": prompt_id,
            "level": level,
            "candidate_num": candidate_num,
            "cosine_sim": row["individual_cosine_sim"],
            "uqlm_global_cosine_sim": row["uqlm_global_cosine_sim"],
            "functional_equivalence_rate": row["functional_equivalence_rate"],
            "mean_confidence": row["individual_cosine_sim"],
        }
        
        with open(candidate_dir / "confidence_score.json", "w", encoding="utf-8") as f:
            json.dump(scores_dict, f, indent=2)

    print(f"Saved {len(df)} candidates to {OUTPUT_DIR}")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as e:
        print(f"[ERROR IN MAIN]: {e}")
        import traceback
        traceback.print_exc()