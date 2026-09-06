#!/usr/bin/env python3
"""Rebuild the unmodified, separately licensed T-REX integration input.
Run with Python 3.12+ and Foundry on Linux/WSL from the repository root.
No upstream lifecycle scripts or package installers are executed.
"""
import hashlib
import io
import json
from pathlib import Path
import subprocess
import shutil
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "out" / "trust12" / "trex"
PACKAGES = [
    ("https://codeload.github.com/TokenySolutions/T-REX/tar.gz/0fa344b761cf861bb9e8e1c8e472ba72815316c2",
     "34577a6d43717943741577c917bb57a0f4ce077b86a9115ea5ea2e837b35fa79", ""),
    ("https://registry.npmjs.org/@openzeppelin/contracts/-/contracts-4.9.3.tgz",
     "00d83cdf0802dd4d1eb8e146e7046a72eb7bbb8f8aeda1243d9d7d48584cb1c0", "node_modules/@openzeppelin/contracts"),
    ("https://registry.npmjs.org/@openzeppelin/contracts-upgradeable/-/contracts-upgradeable-4.9.3.tgz",
     "62ea1421cd0eecb4efe62a906d5754fae5854f1ce3bb8d38236d65b8f6a679a0", "node_modules/@openzeppelin/contracts-upgradeable"),
    ("https://registry.npmjs.org/@onchain-id/solidity/-/solidity-2.1.0.tgz",
     "3dee35394a5110edd604bb2d50a79ddadc74c6b7cd311f7432b61705cbb2fd9e", "node_modules/@onchain-id/solidity"),
]
CONFIG = '''[profile.default]
src = "contracts/token"
out = "out"
cache_path = "cache"
solc_version = "0.8.17"
evm_version = "london"
optimizer = true
optimizer_runs = 200
via_ir = false
bytecode_hash = "none"
cbor_metadata = false
remappings = ["@openzeppelin/=node_modules/@openzeppelin/", "@onchain-id/=node_modules/@onchain-id/"]
'''
def extract_verified(url, digest, directory):
    archive = ROOT / "out" / "trust12" / (digest + ".tar.gz")
    archive.parent.mkdir(parents=True, exist_ok=True)
    data = archive.read_bytes() if archive.exists() else urllib.request.urlopen(url, timeout=60).read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError("archive digest mismatch: " + url)
    archive.write_bytes(data)
    destination = WORK / directory
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        for member in tar:
            if not member.isfile():
                continue
            relative = Path(*Path(member.name).parts[1:])
            target = (destination / relative).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise RuntimeError("archive path escapes destination")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(tar.extractfile(member).read())

def main():
    for item in PACKAGES:
        extract_verified(*item)
    (WORK / "foundry.toml").write_text(CONFIG, encoding="utf8")
    subprocess.run(["forge", "build"], cwd=WORK, check=True)
    artifact = json.loads((WORK / "out/Token.sol/Token.json").read_text())
    creation = artifact["bytecode"]["object"]
    runtime = artifact["deployedBytecode"]["object"]
    creation_hash = subprocess.check_output(["cast", "keccak", creation], text=True).strip()
    runtime_hash = subprocess.check_output(["cast", "keccak", runtime], text=True).strip()
    if creation_hash != "0x1278126a159c0439e8defb9b59f26ae2ad6790cb0c99d81a0722a0bb23ab9438":
        raise RuntimeError("creation bytecode differs from the factory pin")
    if runtime_hash != "0x62d82077b0b4b127a9f788f8482841166e1e9f788d760d24c4d698cf7d517931":
        raise RuntimeError("runtime differs from the pinned integration input")
    seeded=ROOT / "out/trust12/trex-seeded"
    for directory in ("contracts","node_modules"):
        shutil.copytree(WORK/directory,seeded/directory,dirs_exist_ok=True)
    (seeded/"foundry.toml").write_text(CONFIG,encoding="utf8")
    token_source=seeded/"contracts/token/Token.sol"
    body=token_source.read_text()
    anchor="contract Token is IToken, AgentRoleUpgradeable, TokenStorage {"
    if body.count(anchor)!=1: raise RuntimeError("upstream constructor anchor drift")
    token_source.write_text(body.replace(anchor,anchor+"\n    constructor() { _frozen[address(0xbad)] = true; }\n"))
    subprocess.run(["forge","build"],cwd=seeded,check=True)
    print(json.dumps({"status":"PASS", "sourceCommit":"0fa344b761cf861bb9e8e1c8e472ba72815316c2",
        "license":"GPL-3.0 (upstream source notice also permits later GPL versions)",
        "creationKeccak256":creation_hash, "runtimeKeccak256":runtime_hash,
        "compiler":"0.8.17", "evm":"london", "optimizerRuns":200, "viaIR":False}, indent=2))

if __name__ == "__main__":
    main()
