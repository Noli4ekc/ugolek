#!/usr/bin/env python3
"""
Sign an IPA using free Apple ID provisioning.
Uses Apple Developer Portal API to create certificates and provisioning profiles,
then signs with zsign.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import shutil
import requests
import time
import hashlib
import base64
from pathlib import Path

def run(cmd, **kwargs):
    """Run a command and return output."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, **kwargs)
    return result.stdout.strip(), result.stderr.strip(), result.returncode

def get_anisette():
    """Get anisette data from local provider or public server."""
    # Try public anisette servers
    servers = [
        "https://ani.knoyd.com",
        "https://anisette.ervikasn.de",
        "https://anisette.sidestore.io",
    ]
    for url in servers:
        try:
            r = requests.get(f"{url}/v3/", timeout=5)
            if r.status_code == 200:
                return r.json()
        except:
            continue
    return None

def apple_auth(email, password, anisette):
    """Authenticate with Apple ID using GrandSlam protocol."""
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "Xcode",
        "X-Apple-Client-App-Name": "Xcode",
        "X-Apple-I-Client-Time": anisette.get("X-Apple-I-Client-Time", ""),
        "X-Apple-I-MD": anisette.get("X-Apple-I-MD", ""),
        "X-Apple-I-MD-LU": anisette.get("X-Apple-I-MD-LU", ""),
        "X-Apple-I-MD-M": anisette.get("X-Apple-I-MD-M", ""),
        "X-Apple-I-MD-RINFO": anisette.get("X-Apple-I-MD-RINFO", ""),
        "X-Apple-I-SRL-NO": anisette.get("X-Apple-I-SRL-NO", ""),
        "X-Apple-I-TimeZone": anisette.get("X-Apple-I-TimeZone", "UTC"),
        "X-Apple-Locale": anisette.get("X-Apple-Locale", "en_US"),
        "X-Mme-Client-Info": anisette.get("X-Mme-Client-Info", ""),
        "X-Mme-Device-Id": anisette.get("X-Mme-Device-Id", ""),
    }
    
    # Step 1: Initiate auth
    payload = {
        "appleId": email,
        "password": password,
        "rememberMe": False,
    }
    
    r = requests.post(
        "https://idmsa.apple.com/appleauth/auth/signin",
        headers=headers,
        json=payload,
        verify=False
    )
    
    if r.status_code == 200:
        return headers, r.cookies
    elif r.status_code == 409:
        # 2FA required
        print("2FA required. Enter code from your device:", file=sys.stderr)
        code = input().strip()
        headers["X-Apple-Code"] = code
        
        r = requests.post(
            "https://idmsa.apple.com/appleauth/auth/signin",
            headers=headers,
            json={**payload, "verificationCode": {"code": code, "type": "phone"}},
            verify=False
        )
        if r.status_code == 200:
            return headers, r.cookies
    
    raise Exception(f"Auth failed: {r.status_code} - {r.text[:200]}")

def get_team_id(headers, cookies):
    """Get Personal Team ID."""
    r = requests.get(
        "https://developer.apple.com/services-account/QB06785263/ws/account/listTeams",
        headers=headers,
        cookies=cookies,
        verify=False
    )
    data = r.json()
    teams = data.get("teams", [])
    for team in teams:
        if team.get("type") == "Person":
            return team["teamId"]
    if teams:
        return teams[0]["teamId"]
    raise Exception("No team found")

def create_certificate(headers, cookies, team_id):
    """Create iOS Development certificate."""
    r = requests.post(
        f"https://developer.apple.com/services-account/QB06785263/ws/account/ios/certificate/submitCertificateRequest",
        headers=headers,
        cookies=cookies,
        json={
            "teamId": team_id,
            "type": "IOS_DEVELOPMENT",
            "csrContent": generate_csr(),
            "machineId": "",
            "machineName": "Ugolek"
        },
        verify=False
    )
    data = r.json()
    if data.get("certificate"):
        return data["certificate"]["certificateId"], data["certificate"]["certificateBase64"]
    raise Exception(f"Certificate creation failed: {data}")

def generate_csr():
    """Generate CSR for certificate."""
    from Crypto.PublicKey import RSA
    from Crypto.Signature import pkcs1_15
    from Crypto.Hash import SHA256
    
    key = RSA.generate(2048)
    with open("/tmp/key.pem", "wb") as f:
        f.write(key.export_key())
    
    # Generate CSR using OpenSSL
    run("openssl req -new -key /tmp/key.pem -out /tmp/csr.pem -subj '/CN=Ugolek Developer/C=US'")
    
    with open("/tmp/csr.pem", "r") as f:
        csr = f.read()
    
    # Extract base64 content
    lines = csr.split("\n")
    base64_content = "".join(lines[1:-2])
    return base64_content

def get_device_udid():
    """Get connected device UDID."""
    stdout, _, code = run("idevice_id -l")
    if code == 0 and stdout:
        return stdout.split("\n")[0].strip()
    return None

def register_device(headers, cookies, team_id, udid, device_name="iPhone"):
    """Register device for development."""
    r = requests.post(
        f"https://developer.apple.com/services-account/QB06785263/ws/account/ios/device/addDevice",
        headers=headers,
        cookies=cookies,
        json={
            "teamId": team_id,
            "deviceNumber": udid,
            "name": device_name,
            "deviceType": "phone"
        },
        verify=False
    )
    return r.status_code == 200

def create_app_id(headers, cookies, team_id, bundle_id="com.ugolek.app"):
    """Create App ID."""
    r = requests.post(
        f"https://developer.apple.com/services-account/QB06785263/ws/account/ios/identifiers/addAppId",
        headers=headers,
        cookies=cookies,
        json={
            "teamId": team_id,
            "name": "Ugolek",
            "identifier": bundle_id,
            "platform": "IOS",
            "configuration": {}
        },
        verify=False
    )
    return r.status_code == 200

def create_provisioning_profile(headers, cookies, team_id, app_id, cert_id, device_udid):
    """Create provisioning profile."""
    r = requests.post(
        f"https://developer.apple.com/services-account/QB06785263/ws/account/ios/profile/createProvisioningProfile",
        headers=headers,
        cookies=cookies,
        json={
            "teamId": team_id,
            "type": "IOS_DEVELOPMENT",
            "name": "Ugolek Development",
            "appIdId": app_id,
            "certificateIds": [cert_id],
            "deviceIds": [device_udid]
        },
        verify=False
    )
    data = r.json()
    if data.get("provisioningProfile"):
        return data["provisioningProfile"]["provisioningProfileBase64"]
    raise Exception(f"Profile creation failed: {data}")

def sign_ipa(ipa_path, p12_path, profile_path, output_path):
    """Sign IPA using zsign."""
    cmd = f"zsign -k {p12_path} -m {profile_path} -o {output_path} {ipa_path}"
    stdout, stderr, code = run(cmd)
    if code != 0:
        raise Exception(f"Signing failed: {stderr}")
    return output_path

def main():
    parser = argparse.ArgumentParser(description="Sign IPA with free Apple ID")
    parser.add_argument("ipa", help="Path to unsigned IPA")
    parser.add_argument("--apple-id", required=True, help="Apple ID email")
    parser.add_argument("--apple-password", required=True, help="Apple ID password")
    parser.add_argument("--output", required=True, help="Output path for signed IPA")
    parser.add_argument("--udid", help="Device UDID")
    
    args = parser.parse_args()
    
    print("[1/6] Getting anisette data...")
    anisette = get_anisette()
    if not anisette:
        print("ERROR: Could not get anisette data", file=sys.stderr)
        sys.exit(1)
    print("  OK")
    
    print("[2/6] Authenticating with Apple...")
    headers, cookies = apple_auth(args.apple_id, args.apple_password, anisette)
    print("  OK")
    
    print("[3/6] Getting team ID...")
    team_id = get_team_id(headers, cookies)
    print(f"  Team: {team_id}")
    
    print("[4/6] Creating certificate...")
    cert_id, cert_pem = create_certificate(headers, cookies, team_id)
    print(f"  Cert: {cert_id}")
    
    # Convert cert to PEM and create P12
    with open("/tmp/cert.pem", "wb") as f:
        f.write(base64.b64decode(cert_pem))
    
    # Export key
    run("openssl pkcs12 -export -out /tmp/cert.p12 -inkey /tmp/key.pem -in /tmp/cert.pem -passout pass:ugolek")
    
    print("[5/6] Getting device UDID...")
    udid = args.udid or get_device_udid()
    if not udid:
        print("ERROR: No device connected", file=sys.stderr)
        sys.exit(1)
    print(f"  UDID: {udid}")
    
    # Register device
    register_device(headers, cookies, team_id, udid)
    
    # Create App ID
    create_app_id(headers, cookies, team_id)
    
    # Create provisioning profile
    print("[6/6] Creating provisioning profile and signing...")
    profile_b64 = create_provisioning_profile(headers, cookies, team_id, "com.ugolek.app", cert_id, udid)
    
    # Save profile
    with open("/tmp/profile.mobileprovision", "wb") as f:
        f.write(base64.b64decode(profile_b64))
    
    # Sign IPA
    sign_ipa(args.ipa, "/tmp/cert.p12", "/tmp/profile.mobileprovision", args.output)
    
    print(f"\nSigned IPA saved to: {args.output}")

if __name__ == "__main__":
    main()
