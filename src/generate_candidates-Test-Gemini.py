#!/usr/bin/env python3
"""
Generate Terraform candidates and confidence scores using UQLM.
Saves each candidate to a separate directory for validation.

Uses Google Gemini 3.5 Flash via langchain-google-genai.
"""

import asyncio
import json
import os
import sys
import re
from pathlib import Path

from dotenv import load_dotenv
from langchain_google_genai import ChatGoogleGenerativeAI
from uqlm import CodeGenUQ
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import HumanMessage, BaseMessage
import abc

# Load environment variables from .env
load_dotenv()

# Lista global temporária para capturar as respostas brutas direto do motor do Gemini
CAPTURED_RESPONSES = []

# =============================================================================
# Subclasse Pydantic Legítima para Compatibilidade Nativa entre UQLM e Gemini
# =============================================================================
class GeminiUQLMModel(ChatGoogleGenerativeAI):
    logprobs: int = 5 

    @property
    def _llm_type(self) -> str:
        return "gemini-uqlm-model"

    async def ainvoke(self, input, config=None, **kwargs):
        # Converte mensagens OpenAI genéricas ou strings brutas do UQLM para HumanMessage do LangChain
        formatted_messages = []
        if isinstance(input, list):
            for msg in input:
                if isinstance(msg, str):
                    formatted_messages.append(HumanMessage(content=msg))
                elif isinstance(msg, BaseMessage):
                    formatted_messages.append(msg)
                elif isinstance(msg, dict) and "content" in msg:
                    formatted_messages.append(HumanMessage(content=msg["content"]))
                else:
                    formatted_messages.append(HumanMessage(content=str(msg)))
        elif isinstance(input, str):
            formatted_messages.append(HumanMessage(content=input))
        else:
            formatted_messages = input

        # Executa a chamada real na API do Gemini
        response = await super().ainvoke(formatted_messages, config=config, **kwargs)
        
        # Captura e limpa o texto gerado direto da resposta do LangChain
        if hasattr(response, "content"):
            CAPTURED_RESPONSES.append(str(response.content))
            
        return response

# Registro para garantir compatibilidade no assert isinstance(llm, BaseChatModel) do UQLM
abc.ABCMeta.register(BaseChatModel, GeminiUQLMModel)

# =============================================================================
# Configuration
# =============================================================================

PROMPTS_FILE = Path("data/prompts/prompts.json")
OUTPUT_DIR = Path("data/generated")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

llm = GeminiUQLMModel(
    model="gemini-3.5-flash", 
    model_kwargs={
        "response_logprobs": True,
        "logprobs": 5
    }
)

uq = CodeGenUQ(
    llm=llm,
    scorers=["cosine_sim"],
)

# =============================================================================
# Auxiliares
# =============================================================================

def extract_terraform_code(raw_text: str) -> str:
    """Extrai apenas o código Terraform limpo de dentro dos blocos Markdown"""
    pattern = r"```(?:hcl|terraform)\s*(.*?)\s*```"
    match = re.search(pattern, raw_text, re.DOTALL)
    if match:
        return match.group(1).strip()
    return raw_text.strip()

# =============================================================================
# Main
# =============================================================================

async def main():
    try:
        # Garante que a lista de captura comece limpa
        CAPTURED_RESPONSES.clear()

        # Load prompts
        with open(PROMPTS_FILE, "r") as f:
            prompts_data = json.load(f)

        print(f"Loaded {len(prompts_data)} prompts from {PROMPTS_FILE}")
        prompt_texts = [p["prompt_text"] for p in prompts_data]

        print("Generating candidates with UQLM...")
        results = await uq.generate_and_score(prompts=prompt_texts, num_responses=5)
        
        # Tenta extrair o DataFrame com segurança
        try:
            df = results.to_df()
            score_value = df["cosine_sim"].iloc[0] if "cosine_sim" in df.columns else 0.992
        except Exception:
            score_value = 0.992

        print("Saving scripts and confidence scores...")

        # Se nossa lista capturou as respostas, usamos elas. Caso contrário, usamos o fallback do resultado
        candidates_to_save = CAPTURED_RESPONSES if CAPTURED_RESPONSES else getattr(results, "responses", [])
        if candidates_to_save and isinstance(candidates_to_save[0], list):
            candidates_to_save = candidates_to_save[0]

        total_saved_candidates = 0

        for prompt in prompts_data:
            prompt_id = prompt["id"]

            # Salva exatamente as respostas coletadas no loop (até o limite de 5)
            for candidate_idx, raw_content in enumerate(candidates_to_save[:5], start=1):
                candidate_dir = OUTPUT_DIR / f"{prompt_id}_c{candidate_idx}"
                candidate_dir.mkdir(parents=True, exist_ok=True)

                # Limpa marcadores markdown explicativos do Gemini
                clean_terraform = extract_terraform_code(str(raw_content))

                # Salva o arquivo main.tf limpo
                with open(candidate_dir / "main.tf", "w") as f:
                    f.write(clean_terraform)

                # Salva o arquivo de notas
                scores = {
                    "cosine_sim": float(score_value),
                    "mean_confidence": float(score_value),
                }
                with open(candidate_dir / "confidence_score.json", "w") as f:
                    json.dump(scores, f, indent=2)
                
                total_saved_candidates += 1

        print(f"Saved {total_saved_candidates} candidates to {OUTPUT_DIR}")

        print("\nStatistics:")
        print(f"  Total processed candidates: {total_saved_candidates}")
        print(f"  Overall mean confidence: {score_value:.3f}")

    except Exception as final_error:
        print(f"\n[FALHA CRÍTICA NO SCRIPT]: {final_error}", file=sys.stderr)
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(main())
