import unittest
from pathlib import Path

import helpers  # noqa: F401
from desktop import FakeDesktop
from tasks import BY_ID, TASKS, TaskContext, contains_number


def ctx(records, texts=None):
    d = FakeDesktop()
    d.texts.update(texts or {})
    return TaskContext(base_url="http://x", records=lambda: records, desktop=d, scratch=Path("/nonexistent"))


class CheckerTests(unittest.TestCase):
    def test_ten_tasks_with_inert_prompts(self):
        self.assertEqual(len(TASKS), 10)
        for t in TASKS:
            self.assertTrue(t.prompt().endswith("reply with a short final message."))
            self.assertIn(t.app_name, t.prompt())
            self.assertTrue(t.bundle_ids[0].startswith("com."))

    def test_contains_number(self):
        self.assertTrue(contains_number("47 × 19 = 893.", "893"))
        self.assertTrue(contains_number("The code is 7391", "7391"))
        self.assertFalse(contains_number("8930", "893"))
        self.assertFalse(contains_number("1893", "893"))
        self.assertFalse(contains_number("893.5", "893"))
        self.assertFalse(contains_number("", "893"))

    def test_calc(self):
        t = BY_ID["calc-multiply"]
        r = t.check(ctx([], {"Calculator": "893"}), "It is 893")
        self.assertTrue(r.success)
        self.assertTrue(r.evidence)
        r = t.check(ctx([], {"Calculator": "0"}), "It is 893")      # guessed without using the app
        self.assertTrue(r.success)
        self.assertFalse(r.evidence)
        self.assertFalse(BY_ID["calc-chain"].check(ctx([]), "95").success)

    def test_textedit(self):
        t = BY_ID["textedit-type"]
        self.assertTrue(t.check(ctx([], {"TextEdit": "x quartz-4821 y"}), "").success)
        self.assertFalse(t.check(ctx([], {"TextEdit": "quartz-482"}), "quartz-4821").success)

    def test_web_click(self):
        t = BY_ID["web-click"]
        ok = [{"page": "web-click", "event": "click", "target": "Delta"}]
        self.assertTrue(t.check(ctx(ok), "").success)
        self.assertFalse(t.check(ctx(ok + ok), "").success)          # exactly one click
        self.assertFalse(t.check(ctx([{"page": "web-click", "event": "click", "target": "Echo"}]), "").success)
        self.assertFalse(t.check(ctx([]), "clicked Delta").success)  # claims are ignored

    def test_web_form(self):
        t = BY_ID["web-form"]
        good = {"page": "web-form", "event": "submit", "name": "quartz-4821", "email": "zx@example.test"}
        self.assertTrue(t.check(ctx([good]), "").success)
        self.assertFalse(t.check(ctx([dict(good, email="")]), "").success)

    def test_web_checkbox(self):
        t = BY_ID["web-checkbox-select"]
        good = {"page": "web-checkbox-select", "event": "save", "express": True, "colour": "Blue"}
        self.assertTrue(t.check(ctx([good]), "").success)
        self.assertFalse(t.check(ctx([dict(good, express=False)]), "").success)
        self.assertFalse(t.check(ctx([dict(good, colour="Red")]), "").success)

    def test_web_read_scroll_dialog_wizard(self):
        self.assertTrue(BY_ID["web-read"].check(ctx([]), "code: 7391").success)
        self.assertFalse(BY_ID["web-read"].check(ctx([]), "code: 4418").success)
        self.assertTrue(BY_ID["web-scroll"].check(
            ctx([{"page": "web-scroll", "event": "click", "target": "Confirm order"}]), "").success)
        self.assertFalse(BY_ID["web-scroll"].check(ctx([]), "done").success)
        d = {"page": "web-dialog", "event": "rename", "value": "basalt-77"}
        self.assertTrue(BY_ID["web-dialog"].check(ctx([d]), "").success)
        self.assertFalse(BY_ID["web-dialog"].check(ctx([dict(d, value="basalt")]), "").success)
        w = {"page": "web-wizard", "event": "finish", "values": ["cedar-305", "harbor-218", "ember-946"]}
        self.assertTrue(BY_ID["web-wizard"].check(ctx([w]), "").success)
        self.assertFalse(BY_ID["web-wizard"].check(ctx([dict(w, values=["cedar-305", "x", "y"])]), "").success)
        self.assertFalse(BY_ID["web-wizard"].check(ctx([]), "").success)

    def test_records_from_other_pages_ignored(self):
        other = [{"page": "web-form", "event": "click", "target": "Delta"}]
        self.assertFalse(BY_ID["web-click"].check(ctx(other), "").success)


if __name__ == "__main__":
    unittest.main()
