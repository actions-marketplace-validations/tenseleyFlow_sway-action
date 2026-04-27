"""Build a tiny random LoRA on SmolLM2-135M for the self-test workflow.

Mirrors the helper in sway's own integration tests so the smoke
action runs against the same shape of adapter sway tests itself
against. Single-file CLI:

    python tests/build_adapter.py ./adapter
"""

from __future__ import annotations

import sys
from pathlib import Path

import torch
from peft import LoraConfig, get_peft_model
from transformers import AutoModelForCausalLM, AutoTokenizer


def main(out: Path) -> None:
    torch.manual_seed(0)
    base = "HuggingFaceTB/SmolLM2-135M-Instruct"
    tok = AutoTokenizer.from_pretrained(base)
    if tok.pad_token_id is None:
        tok.pad_token = tok.eos_token
    model = AutoModelForCausalLM.from_pretrained(base, torch_dtype=torch.float32)
    cfg = LoraConfig(
        r=8,
        lora_alpha=16,
        target_modules=["q_proj", "v_proj"],
        lora_dropout=0.0,
        bias="none",
        task_type="CAUSAL_LM",
    )
    peft = get_peft_model(model, cfg)
    with torch.no_grad():
        for n, p in peft.named_parameters():
            if "lora_B" in n:
                # Tiny perturbation — enough that base != ft, small
                # enough that generations stay sane.
                p.copy_(torch.randn_like(p) * 0.05)
    out.mkdir(parents=True, exist_ok=True)
    peft.save_pretrained(str(out))
    tok.save_pretrained(str(out))
    print(f"wrote adapter to {out}")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
