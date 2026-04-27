"""Stub dlm_sway package for smoke-testing the action.

The smoke workflow drops this onto PYTHONPATH ahead of any real
``dlm-sway`` install so ``python -m dlm_sway gate / report`` returns
canned output. That lets us validate the action's bash + JS plumbing
without paying the cost of a real model load on every PR.

Real test coverage of the gate / report commands lives in
tenseleyFlow/sway's own integration suite.
"""
