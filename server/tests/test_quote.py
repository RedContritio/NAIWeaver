from __future__ import annotations

import tests  # noqa: F401  # isolates the data directories before app imports

import copy
import json
from pathlib import Path
import unittest

from fastapi import HTTPException

from app import billing


FIXTURE_PATH = Path(__file__).resolve().parents[2] / "test" / "fixtures" / "quote_cases.json"


def load_fixture() -> dict:
    return json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))


def fixture_rules(fixture: dict, case: dict) -> dict:
    rules = copy.deepcopy(fixture["base_rules"])
    rules["green_point_discount"] = case.get("green_point_discount", 0)
    rules["free_allowance_exhausted"] = case.get("free_allowance_exhausted", False)
    return rules


def fixture_request(case: dict) -> dict:
    request = {
        "input": "golden case",
        "model": "nai-diffusion-4-5-full",
        "parameters": copy.deepcopy(case["parameters"]),
    }
    if case.get("action") is not None:
        request["action"] = case["action"]
    return request


class GoldenQuoteCaseTests(unittest.TestCase):
    """The shared golden cases; the Flutter estimate runs the same file."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.fixture = load_fixture()

    def test_every_golden_case_produces_the_expected_quote(self) -> None:
        for case in self.fixture["cases"]:
            with self.subTest(case["name"]):
                _, quote = billing.classify_and_quote(
                    fixture_request(case),
                    fixture_rules(self.fixture, case),
                    images=case["seeds"],
                )
                self.assertEqual(quote.to_dict(), case["expected"])

    def test_every_invalid_case_is_rejected_with_its_field(self) -> None:
        for case in self.fixture["invalid_cases"]:
            with self.subTest(case["name"]):
                with self.assertRaises(HTTPException) as raised:
                    billing.classify_and_quote(
                        fixture_request(case), fixture_rules(self.fixture, case)
                    )
                self.assertEqual(raised.exception.status_code, 400)
                detail = raised.exception.detail
                self.assertEqual(detail["code"], case["expected_error"]["code"])
                self.assertEqual(detail["field"], case["expected_error"]["field"])

    def test_cases_cover_every_generation_reason(self) -> None:
        covered = {
            reason
            for case in self.fixture["cases"]
            for reason in case["expected"]["reasons"]
        }
        self.assertEqual(covered, set(billing.REASON_ORDER) - {"paid_tool"})

    def test_base_rules_are_the_rules_served_to_a_paid_user(self) -> None:
        rules = billing.build_image_rules(
            is_admin=False,
            can_generate_paid=True,
            green_point_discount=0,
            allowance_exhausted=False,
        )
        self.assertEqual(rules, self.fixture["base_rules"])


class StrictParsingTests(unittest.TestCase):
    rules = billing.build_image_rules(
        is_admin=False,
        can_generate_paid=True,
        green_point_discount=0,
        allowance_exhausted=False,
    )

    def request(self, **parameters) -> dict:
        params = {
            "width": 832,
            "height": 1216,
            "steps": 28,
            "scale": 5.0,
            "sampler": "k_euler_ancestral",
        }
        params.update(parameters)
        return {"input": "1girl", "model": "nai-diffusion-4-5-full", "parameters": params}

    def test_dimensions_and_steps_reject_bool_float_and_string(self) -> None:
        for field in ("width", "height", "steps"):
            valid = self.request()["parameters"][field]
            for bad in (float(valid), True, str(valid), None):
                with self.subTest(field=field, value=bad):
                    with self.assertRaises(HTTPException) as raised:
                        billing.classify_and_quote(self.request(**{field: bad}), self.rules)
                    self.assertEqual(raised.exception.detail["code"], "invalid_parameters")
                    self.assertEqual(raised.exception.detail["field"], field)

    def test_priced_values_are_written_back_into_the_forwarded_body(self) -> None:
        original = self.request(
            params_version=3, n_samples=4, sm=None, sm_dyn=False, seed=5
        )
        snapshot = copy.deepcopy(original)

        forwarded, quote = billing.classify_and_quote(original, self.rules)

        params = forwarded["parameters"]
        self.assertEqual(
            (params["width"], params["height"], params["steps"]), (832, 1216, 28)
        )
        self.assertIs(type(params["width"]), int)
        self.assertIs(params["sm"], False)
        self.assertEqual(params["params_version"], 4)
        self.assertEqual(params["n_samples"], 1)
        self.assertEqual(forwarded["model"], billing.NAI_V5_FULL_MODEL)
        self.assertEqual((quote.mode, quote.points), ("free", 20))
        # The caller's request is never mutated.
        self.assertEqual(original, snapshot)

    def test_reference_lists_must_be_lists(self) -> None:
        for field in ("director_reference_images", "reference_image_multiple"):
            with self.subTest(field):
                with self.assertRaises(HTTPException) as raised:
                    billing.classify_and_quote(self.request(**{field: "one-image"}), self.rules)
                self.assertEqual(raised.exception.detail["field"], field)

    def test_free_user_rules_cap_steps_at_the_free_limit(self) -> None:
        free_rules = billing.build_image_rules(
            is_admin=False,
            can_generate_paid=False,
            green_point_discount=0,
            allowance_exhausted=False,
        )
        with self.assertRaises(HTTPException) as raised:
            billing.classify_and_quote(self.request(steps=29), free_rules)
        self.assertEqual(raised.exception.detail["field"], "steps")
        self.assertEqual(raised.exception.detail["limit"], 28)


class ToolQuoteAndSettlementTests(unittest.TestCase):
    def test_tool_quotes_are_the_configured_caps(self) -> None:
        self.assertEqual(billing.TOOL_CAPS, {"upscale": 10, "augment": 80, "encode_vibe": 2})
        quote = billing.tool_quote("augment").to_dict()
        self.assertEqual(
            (quote["mode"], quote["points"], quote["reasons"]), ("paid", 80, ["paid_tool"])
        )

    def test_settlement_charges_the_measured_delta_capped_by_the_reservation(self) -> None:
        cases = {
            "below_quote": (33, 25, (25, False)),
            "equal_to_quote": (33, 33, (33, False)),
            "zero_delta": (33, 0, (0, False)),
            "unavailable": (33, None, (33, False)),
            "negative": (33, -7, (33, False)),
            "above_quote": (33, 40, (33, True)),
        }
        for name, (reserved, delta, expected) in cases.items():
            with self.subTest(name):
                self.assertEqual(billing.settle_amount(reserved, delta), expected)


if __name__ == "__main__":
    unittest.main()
