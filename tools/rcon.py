#!/usr/bin/env python3
"""Send a console command to the headless server over RCON and print the reply.

    python3 tools/rcon.py /f3d-status
    python3 tools/rcon.py "/sc rcon.print(game.tick)"

The server scripts start Factorio with --rcon-port 34198 and a random password kept in
server/data/rcon-password.txt, which this reads by default.
"""

import argparse
import pathlib
import socket
import struct

AUTH, EXEC = 3, 2
DEFAULT_PASSWORD_FILE = pathlib.Path(__file__).resolve().parent.parent / "server" / "data" / "rcon-password.txt"
# run()'s default port; live_check.py --rcon-port changes it for a second server instance.
PORT = 34198


def packet(req_id, kind, body):
    payload = struct.pack("<ii", req_id, kind) + body.encode() + b"\x00\x00"
    return struct.pack("<i", len(payload)) + payload


def read_packet(sock):
    def exactly(n):
        data = b""
        while len(data) < n:
            chunk = sock.recv(n - len(data))
            if not chunk:
                raise ConnectionError("RCON connection closed")
            data += chunk
        return data

    (size,) = struct.unpack("<i", exactly(4))
    data = exactly(size)
    req_id, kind = struct.unpack("<ii", data[:8])
    return req_id, kind, data[8:-2].decode(errors="replace")


def run(command, host="127.0.0.1", port=None, password=None, timeout=10.0):
    port = port or PORT
    if password is None:
        password = DEFAULT_PASSWORD_FILE.read_text().strip()
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.sendall(packet(1, AUTH, password))
        while True:
            req_id, kind, _ = read_packet(sock)
            if kind == 2:  # auth response
                if req_id == -1:
                    raise PermissionError("RCON password rejected")
                break
        sock.sendall(packet(2, EXEC, command))
        _, _, body = read_packet(sock)
        return body


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", nargs="+")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--password", help=f"default: contents of {DEFAULT_PASSWORD_FILE}")
    args = parser.parse_args()
    print(run(" ".join(args.command), args.host, args.port, args.password))


if __name__ == "__main__":
    main()
