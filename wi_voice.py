#!/usr/bin/env python3
"""WiVoice Python streamer. macOS system-output capture requires BlackHole."""
import argparse
import asyncio
import ipaddress
import socket
import sys
from http import HTTPStatus
from pathlib import Path

try:
    import sounddevice as sd
    import websockets
except ImportError as exc:
    print(f"Missing dependency: {exc.name}. Install with: python3 -m pip install -r requirements.txt", file=sys.stderr)
    raise SystemExit(1)

HOST = "0.0.0.0"
PORT = 8765
RATE = 48_000
CHANNELS = 2
PAGE = Path(__file__).parent / "receiver" / "index.html"
clients = set()
loop = None


def local_ip():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("192.0.2.1", 9))
        candidate = sock.getsockname()[0]
        return candidate if ipaddress.ip_address(candidate).is_private else "127.0.0.1"
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


async def process_request(path, headers):
    # websockets calls this for regular HTTP requests as well as upgrades.
    if headers.get("Upgrade", "").lower() == "websocket":
        return None
    try:
        body = PAGE.read_bytes()
    except OSError as exc:
        body = f"Receiver page unavailable: {exc}".encode()
        return HTTPStatus.INTERNAL_SERVER_ERROR, [("Content-Type", "text/plain")], body
    return HTTPStatus.OK, [("Content-Type", "text/html; charset=utf-8"), ("Content-Length", str(len(body)))], body


async def client_connected(websocket, path=None):
    clients.add(websocket)
    try:
        await websocket.wait_closed()
    finally:
        clients.discard(websocket)


async def broadcast(packet):
    if clients:
        await asyncio.gather(*(client.send(packet) for client in tuple(clients)), return_exceptions=True)


def audio_callback(indata, frames, time_info, status):
    if status:
        print(f"Audio warning: {status}", file=sys.stderr)
    packet = bytes(indata)  # raw little-endian Float32 stereo, matching receiver/index.html
    loop.call_soon_threadsafe(lambda: asyncio.create_task(broadcast(packet)))


def find_blackhole():
    devices = sd.query_devices()
    for index, device in enumerate(devices):
        if device["max_input_channels"] >= CHANNELS and "blackhole" in device["name"].lower():
            return index, device
    return None, None


async def serve(device_index):
    global loop
    loop = asyncio.get_running_loop()
    async with websockets.serve(
        client_connected,
        HOST,
        PORT,
        process_request=process_request,
        max_size=None,
        ping_interval=20,
        ping_timeout=20,
    ):
        with sd.RawInputStream(
            device=device_index,
            samplerate=RATE,
            blocksize=1024,
            channels=CHANNELS,
            dtype="float32",
            callback=audio_callback,
        ):
            print(f"WiVoice is streaming. Open http://{local_ip()}:{PORT} on your other device.")
            print("Press Ctrl+C to stop.")
            await asyncio.Future()


def main():
    parser = argparse.ArgumentParser(description="Stream Mac system audio to a browser on your local network")
    parser.add_argument("--list-devices", action="store_true", help="list available audio devices")
    args = parser.parse_args()
    if args.list_devices:
        print(sd.query_devices())
        return
    index, device = find_blackhole()
    if device is None:
        print("BlackHole input device not found. Install BlackHole 2ch and route Mac output to it; see README.md.", file=sys.stderr)
        raise SystemExit(2)
    try:
        asyncio.run(serve(index))
    except KeyboardInterrupt:
        print("\nWiVoice stopped.")
    except Exception as exc:
        print(f"Could not start audio stream: {exc}", file=sys.stderr)
        print("Check that BlackHole is selected as system output and supports 48 kHz stereo.", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
