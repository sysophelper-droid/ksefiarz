#!/usr/bin/env python3
"""Pozyskuje token KSeF dla środowiska TESTOWEGO (api-test.ksef.mf.gov.pl).

Środowisko testowe KSeF akceptuje podpisy XAdES wykonane certyfikatem
self-signed — skrypt generuje taki certyfikat („pieczęć" z VATPL-{NIP}),
przechodzi pełny przepływ uwierzytelnienia i generuje token KSeF
z uprawnieniami do odczytu i wystawiania faktur.

NIGDY nie działa na produkcji — host jest zaszyty na api-test.

Wymagania (venv):
    python3 -m venv /tmp/ksef-venv
    /tmp/ksef-venv/bin/pip install signxml requests cryptography lxml
Użycie:
    /tmp/ksef-venv/bin/python Scripts/get-test-token.py --nip <NIP>
"""

import argparse
import json
import sys
import time
from datetime import datetime, timedelta, timezone

import requests
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID, ObjectIdentifier
from lxml import etree
from signxml import SignatureMethod, methods
from signxml.xades import XAdESSigner

BASE = "https://api-test.ksef.mf.gov.pl/api/v2"
AUTH_NS = "http://ksef.mf.gov.pl/auth/token/2.0"
ORGANIZATION_IDENTIFIER = ObjectIdentifier("2.5.4.97")  # organizationIdentifier


def api(method, path, *, bearer=None, body=None, content_type=None):
    headers = {"Accept": "application/json"}
    if bearer:
        headers["Authorization"] = f"Bearer {bearer}"
    if content_type:
        headers["Content-Type"] = content_type
    data = body if isinstance(body, (bytes, str)) else None
    response = requests.request(
        method, f"{BASE}{path}", headers=headers, data=data,
        json=body if data is None and body is not None else None, timeout=30,
    )
    if response.status_code >= 400:
        sys.exit(f"BŁĄD {method} {path}: HTTP {response.status_code}\n{response.text}")
    return response.json() if response.text else {}


def make_self_signed_seal(nip: str):
    """Certyfikat „pieczęci" (RSA-2048) z organizationIdentifier=VATPL-{NIP}."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "PL"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, f"Ksefiarz Test {nip}"),
        x509.NameAttribute(NameOID.COMMON_NAME, f"Ksefiarz Test {nip}"),
        x509.NameAttribute(ORGANIZATION_IDENTIFIER, f"VATPL-{nip}"),
    ])
    now = datetime.now(timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(days=30))
        .sign(key, hashes.SHA256())
    )
    return key, cert


def build_auth_token_request(challenge: str, nip: str) -> etree._Element:
    root = etree.Element(f"{{{AUTH_NS}}}AuthTokenRequest", nsmap={None: AUTH_NS})
    etree.SubElement(root, f"{{{AUTH_NS}}}Challenge").text = challenge
    context = etree.SubElement(root, f"{{{AUTH_NS}}}ContextIdentifier")
    etree.SubElement(context, f"{{{AUTH_NS}}}Nip").text = nip
    etree.SubElement(root, f"{{{AUTH_NS}}}SubjectIdentifierType").text = "certificateSubject"
    return root


def main():
    parser = argparse.ArgumentParser(description="Token KSeF dla środowiska testowego")
    parser.add_argument("--nip", required=True, help="NIP kontekstu (10 cyfr)")
    parser.add_argument("--description", default="Token testowy Ksefiarz (auto)")
    args = parser.parse_args()

    print("1/6 Challenge…", file=sys.stderr)
    challenge = api("POST", "/auth/challenge")["challenge"]

    print("2/6 Certyfikat self-signed…", file=sys.stderr)
    key, cert = make_self_signed_seal(args.nip)

    print("3/6 Podpis XAdES (enveloped)…", file=sys.stderr)
    request_xml = build_auth_token_request(challenge, args.nip)
    signer = XAdESSigner(
        method=methods.enveloped,
        signature_algorithm=SignatureMethod.RSA_SHA256,
        digest_algorithm="sha256",
    )
    signed = signer.sign(
        request_xml,
        key=key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ),
        cert=cert.public_bytes(serialization.Encoding.PEM).decode(),
    )
    signed_xml = etree.tostring(signed, xml_declaration=True, encoding="UTF-8")

    print("4/6 /auth/xades-signature…", file=sys.stderr)
    init = api("POST", "/auth/xades-signature", body=signed_xml,
               content_type="application/xml")
    reference = init["referenceNumber"]
    temp_token = init["authenticationToken"]["token"]

    print("5/6 Status uwierzytelnienia…", file=sys.stderr)
    for _ in range(30):
        status = api("GET", f"/auth/{reference}", bearer=temp_token)["status"]
        if status["code"] == 200:
            break
        if status["code"] >= 400:
            sys.exit(f"Uwierzytelnienie odrzucone: {json.dumps(status, ensure_ascii=False)}")
        time.sleep(1)
    else:
        sys.exit("Przekroczono czas oczekiwania na uwierzytelnienie.")

    access = api("POST", "/auth/token/redeem", bearer=temp_token)["accessToken"]["token"]

    print("6/6 Generowanie tokenu KSeF…", file=sys.stderr)
    token = api("POST", "/tokens", bearer=access, body={
        "permissions": ["InvoiceRead", "InvoiceWrite"],
        "description": args.description,
    })["token"]

    print(token)


if __name__ == "__main__":
    main()
