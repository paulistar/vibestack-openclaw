"""Testes unitários do core web_research (SSRF + parsing) — sem rede."""
from __future__ import annotations

import ipaddress
import os
import unittest
from unittest.mock import patch

# Import relativo ao pacote middleware
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from web_research_lib import (  # noqa: E402
    html_to_text,
    is_blocked_ip,
    validate_url,
    web_fetch,
    web_search,
)


class TestBlockedIP(unittest.TestCase):
    def test_private_v4(self):
        self.assertTrue(is_blocked_ip(ipaddress.ip_address("10.0.0.1")))
        self.assertTrue(is_blocked_ip(ipaddress.ip_address("192.168.1.1")))
        self.assertTrue(is_blocked_ip(ipaddress.ip_address("127.0.0.1")))
        self.assertTrue(is_blocked_ip(ipaddress.ip_address("169.254.169.254")))

    def test_public_v4(self):
        self.assertFalse(is_blocked_ip(ipaddress.ip_address("8.8.8.8")))
        self.assertFalse(is_blocked_ip(ipaddress.ip_address("1.1.1.1")))


class TestValidateUrl(unittest.TestCase):
    def test_rejects_file_scheme(self):
        ok, reason = validate_url("file:///etc/passwd")
        self.assertFalse(ok)
        self.assertIn("scheme", reason)

    def test_rejects_localhost(self):
        ok, _ = validate_url("http://localhost/admin")
        self.assertFalse(ok)

    def test_rejects_metadata_ip(self):
        ok, reason = validate_url("http://169.254.169.254/latest/meta-data/")
        self.assertFalse(ok)
        self.assertTrue("IP" in reason or "metadata" in reason.lower() or "público" in reason)

    def test_rejects_credentials_in_url(self):
        ok, reason = validate_url("https://user:pass@example.com/")
        self.assertFalse(ok)
        self.assertIn("credenciais", reason)

    def test_denylist(self):
        cfg = {
            "allowlist": [],
            "denylist": ["evil.example"],
            "timeout_sec": 5,
            "max_bytes": 1000,
            "max_results": 5,
            "max_redirects": 2,
            "user_agent": "test",
            "provider": "ddg",
            "exa_key": "",
            "tavily_key": "",
            "brave_key": "",
        }
        with patch("web_research_lib.resolve_and_check_host", return_value=(True, "ok")):
            ok, reason = validate_url("https://sub.evil.example/x", cfg=cfg)
            self.assertFalse(ok)
            self.assertIn("denylist", reason)

    def test_allowlist(self):
        cfg = {
            "allowlist": ["martstudiosbr.com.br"],
            "denylist": [],
            "timeout_sec": 5,
            "max_bytes": 1000,
            "max_results": 5,
            "max_redirects": 2,
            "user_agent": "test",
            "provider": "ddg",
            "exa_key": "",
            "tavily_key": "",
            "brave_key": "",
        }
        with patch("web_research_lib.resolve_and_check_host", return_value=(True, "ok")):
            ok, _ = validate_url("https://www.martstudiosbr.com.br/sobre", cfg=cfg)
            self.assertTrue(ok)
            ok2, reason = validate_url("https://other.com/", cfg=cfg)
            self.assertFalse(ok2)
            self.assertIn("allowlist", reason)


class TestHtmlToText(unittest.TestCase):
    def test_strips_script_and_keeps_title(self):
        html = """<!doctype html><html><head><title>Mart</title>
        <script>alert(1)</script></head>
        <body><h1>Olá</h1><p>Agência de marketing.</p>
        <style>.x{}</style></body></html>"""
        out = html_to_text(html)
        self.assertIn("Mart", out["title"])
        self.assertIn("Agência", out["text"])
        self.assertNotIn("alert", out["text"])


class TestWebSearchEmpty(unittest.TestCase):
    def test_empty_query(self):
        r = web_search("  ")
        self.assertIn("error", r)


class TestWebFetchBlocked(unittest.TestCase):
    def test_ssrf_before_request(self):
        r = web_fetch("http://127.0.0.1/")
        self.assertIn("error", r)
        self.assertEqual(r.get("code"), "ssrf_blocked")


if __name__ == "__main__":
    unittest.main()
