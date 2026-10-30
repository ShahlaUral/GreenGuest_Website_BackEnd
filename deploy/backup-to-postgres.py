#!/usr/bin/env python3
"""SQL Server backup skriptindəki sətirləri PostgreSQL INSERT-lərinə çevirir.

İstifadə: python3 backup-to-postgres.py websitedb.sql > data.sql
Hesabat stderr-ə yazılır, gözlənilməyən cədvəl və ya dəyərdə skript dayanır.
"""
import re
import sys

TABLES = ("CategoryItems", "FaqItems", "Settings", "Sliders")
IGNORED = ("__EFMigrationsHistory",)  # Postgres miqrasiya tarixçəsi schema.sql-dədir
BOOLEAN_COLUMNS = ("IsDeleted",)

INSERT = re.compile(r"^INSERT \[dbo\]\.\[(\w+)\] \(([^)]*)\) VALUES \(", re.M)


def read_backup(path):
    raw = open(path, "rb").read()
    encoding = "utf-16" if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8-sig"
    return raw.decode(encoding).replace("\r\n", "\n")


def parse_values(text, pos):
    """pos VALUES-dan sonrakı simvoldur. Dəyərlər siyahısını qaytarır."""
    values = []
    while True:
        while text[pos] in " \n":
            pos += 1
        if text.startswith("N'", pos) or text[pos] == "'":
            pos = text.index("'", pos) + 1
            chunk = []
            while True:
                end = text.index("'", pos)
                chunk.append(text[pos:end])
                if text.startswith("''", end):
                    chunk.append("'")
                    pos = end + 2
                else:
                    pos = end + 1
                    break
            values.append("".join(chunk))
        else:
            token = re.compile(r"[^,)\s]+").match(text, pos)
            if token is None:
                raise ValueError(f"Naməlum dəyər: {text[pos:pos + 40]!r}")
            raw = token.group()
            if raw != "NULL" and not re.fullmatch(r"-?\d+", raw):
                raise ValueError(f"Naməlum dəyər: {raw!r}")
            values.append(None if raw == "NULL" else int(raw))
            pos = token.end()
        while text[pos] in " \n":
            pos += 1
        if text[pos] == ")":
            return values
        if text[pos] != ",":
            raise ValueError(f"Gözlənilməz simvol: {text[pos:pos + 40]!r}")
        pos += 1


def to_sql(column, value):
    if value is None:
        return "NULL"
    if column in BOOLEAN_COLUMNS:
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return "'" + value.replace("'", "''") + "'"


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    text = read_backup(sys.argv[1])
    counts = dict.fromkeys(TABLES, 0)
    print("BEGIN;")
    for match in INSERT.finditer(text):
        table = match.group(1)
        if table in IGNORED:
            continue
        if table not in TABLES:
            raise ValueError(f"Gözlənilməz cədvəl: {table}")
        columns = re.findall(r"\[(\w+)\]", match.group(2))
        values = parse_values(text, match.end())
        if len(columns) != len(values):
            raise ValueError(f"{table}: sütun və dəyər sayı fərqlidir")
        names = ", ".join(f'"{c}"' for c in columns)
        literals = ", ".join(to_sql(c, v) for c, v in zip(columns, values))
        print(f'INSERT INTO "{table}" ({names}) VALUES ({literals});')
        counts[table] += 1
    # Id-lər əl ilə yazıldığı üçün yeni sətirlər toqquşmasın
    for table in TABLES:
        print(f"""SELECT setval(pg_get_serial_sequence('"{table}"', 'Id'), COALESCE(MAX("Id"), 0) + 1, false) FROM "{table}";""")
    print("COMMIT;")
    print("Sətirlər: " + ", ".join(f"{t}={n}" for t, n in counts.items()), file=sys.stderr)


if __name__ == "__main__":
    main()
