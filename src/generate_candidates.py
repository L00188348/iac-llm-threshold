#!/usr/bin/env python3
"""
Generate Terraform candidates and confidence scores using UQLM.
Saves each candidate to a separate directory for validation.
"""

import asyncio
import json
from pathlib import Path

from langchain_google_genai import ChatGoogleGenerativeAI
from uqlm import CodeGenUQ

# =============================================================================
# Configuration
# =============================================================================

PROMPTS_FILE = Path("data/prompts/prompts.json")
OUTPUT_DIR = Path("data/generated")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Uses default LangChain parameters for Gemini 3.1 Pro
llm = ChatGoogleGenerativeAI(
    model="gemini-3.1-pro",
)

# Uses default UQLM configuration
uq = CodeGenUQ(
    llm=llm,
    scorers=["functional_equivalence_rate", "cosine_sim"],
)


# =============================================================================
# Main
# =============================================================================

async def main():
    # Load prompts
    with open(PROMPTS_FILE, "r") as f:
        prompts_data = json.load(f)

    print(f"Loaded {len(prompts_data)} prompts from {PROMPTS_FILE}")

    # Extract prompt texts
    prompt_texts = [p["prompt_text"] for p in prompts_data]

    # Generate candidates and confidence scores
    print("Generating candidates with UQLM...")
    results = await uq.generate_and_score(prompts=prompt_texts, num_responses=5)
    df = results.to_df()

    print(f"Generated {len(df)} candidates")

    # Add identification columns
    prompt_ids = []
    candidate_nums = []

    for prompt in prompts_data:
        for candidate in range(1, 6):
            prompt_ids.append(prompt["id"])
            candidate_nums.append(candidate)

    df["prompt_id"] = prompt_ids
    df["candidate_num"] = candidate_nums

    # Save each candidate
    print("Saving scripts and confidence scores...")

    for _, row in df.iterrows():
        prompt_id = row["prompt_id"]
        candidate_num = row["candidate_num"]
        script_content = row["response"]

        candidate_dir = OUTPUT_DIR / f"{prompt_id}_c{candidate_num}"
        candidate_dir.mkdir(parents=True, exist_ok=True)

        # Save Terraform script
        with open(candidate_dir / "main.tf", "w") as f:
            f.write(script_content)

        # Save confidence scores
        scores = {
            "cosine_sim": row["cosine_sim"],
            "functional_equivalence_rate": row["functional_equivalence_rate"],
            "mean_confidence": (row["cosine_sim"] + row["functional_equivalence_rate"]) / 2,
        }
        with open(candidate_dir / "confidence_score.json", "w") as f:
            json.dump(scores, f, indent=2)

    print(f"Saved {len(df)} candidates to {OUTPUT_DIR}")

    # Statistics
    print("\nStatistics:")
    print(f"  Total candidates: {len(df)}")
    print(f"  Mean cosine_sim: {df['cosine_sim'].mean():.3f}")
    print(f"  Mean functional equivalence: {df['functional_equivalence_rate'].mean():.3f}")
    print(f"  Overall mean: {df[['cosine_sim', 'functional_equivalence_rate']].mean().mean():.3f}")


if __name__ == "__main__":
    asyncio.run(main())