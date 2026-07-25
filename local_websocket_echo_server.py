"""
Local WebSocket echo server for Severe's isolated WebsocketClient test.

Install once:
    py -m pip install websockets

Run:
    py local_websocket_echo_server.py

"""

import asyncio
import sys

try:
    import websockets
except ImportError:
    print("Missing dependency: websockets")
    print("Install it with: py -m pip install websockets")
    sys.exit(1)


async def echo(websocket):
    async for message in websocket:
        await websocket.send(message)


async def main() -> None:
    host = "127.0.0.1"
    port = 8765

    async with websockets.serve(echo, host, port):
        print(f"Local WebSocket echo server listening on ws://{host}:{port}")
        print("Keep this window open while running the Severe test.")
        await asyncio.Future()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer stopped.")
