#!/usr/bin/env python3
"""
Test OpenRouter connection.
"""

import os
from dotenv import load_dotenv
from langchain_openai import ChatOpenAI

load_dotenv()

api_key = os.getenv("OPENROUTER_API_KEY")

if not api_key:
    print("❌ OPENROUTER_API_KEY not found in .env")
    print("Please add: OPENROUTER_API_KEY=sk-or-v1-...")
    exit(1)

print("✅ OPENROUTER_API_KEY found")

llm = ChatOpenAI(
    base_url="https://openrouter.ai/api/v1",
    api_key=api_key,
    model="openrouter/free",
    temperature=0.7,
)

print("⏳ Sending test prompt...")
response = llm.invoke("Write a simple Terraform configuration for an S3 bucket.")
print("\n✅ Response received:")
print("-" * 40)
print(response.content)
print("-" * 40)