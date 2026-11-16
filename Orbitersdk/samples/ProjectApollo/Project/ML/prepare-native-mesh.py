"""Keep the original launcher mesh groups and remap duplicate vertices for 16-bit indices."""
from pathlib import Path
import re
import sys


def prepare(original: bytes) -> bytes:
    lines = original.splitlines(keepends=True)
    result = []
    line = 0
    while line < len(lines):
        record = lines[line]
        line += 1
        match = re.fullmatch(rb"GEOM\s+(\d+)\s+(\d+)\s*", record)
        if match is None or int(match[1]) <= 65536:
            result.append(record)
            continue
        vertex_count, face_count = (int(value) for value in match.groups())
        vertices = lines[line:line + vertex_count]
        line += vertex_count
        faces = lines[line:line + face_count]
        line += face_count
        if len(vertices) != vertex_count or len(faces) != face_count:
            raise ValueError("Truncated launch platform geometry")
        index_by_vertex = {}
        remap = [index_by_vertex.setdefault(vertex, len(index_by_vertex)) for vertex in vertices]
        if len(index_by_vertex) > 65536:
            raise ValueError("Launch platform mesh still exceeds the 16-bit index range")
        eol = b"\r\n" if record.endswith(b"\r\n") else b"\n"
        result.append(f"GEOM {len(index_by_vertex)} {face_count}".encode() + eol)
        result.extend(index_by_vertex)
        for face in faces:
            indices = [int(item) for item in face.split()]
            if len(indices) != 3 or any(index < 0 or index >= vertex_count for index in indices):
                raise ValueError("Invalid face in launch platform mesh")
            result.append(" ".join(str(remap[index]) for index in indices).encode() + eol)
    return b"".join(result)


if __name__ == "__main__":
    source, destination = map(Path, sys.argv[1:])
    destination.write_bytes(prepare(source.read_bytes()))
