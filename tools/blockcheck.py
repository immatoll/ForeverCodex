# Poor man's block check for the Lua files (no luacheck needed): every function/if/do/for/while/repeat closed?
# Usage: python tools/blockcheck.py Core.lua Tooltip.lua ...   (paths relative to the addon folder)
import re, sys, os
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def tokens(src):
    i, n = 0, len(src)
    out = []
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i)
                i = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
            continue
        if c in "\"'":
            q = c
            j = i + 1
            while j < n and src[j] != q:
                if src[j] == "\\": j += 1
                if src[j] == "\n": break
                j += 1
            i = j + 1
            out.append(("str", "", src.count("\n", 0, i) + 1))
            continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            j = src.find(close, i)
            i = n if j < 0 else j + len(close)
            out.append(("str", "", 0))
            continue
        m = re.match(r"[A-Za-z_]\w*", src[i:])
        if m:
            out.append(("id", m.group(0), src.count("\n", 0, i) + 1))
            i += len(m.group(0))
            continue
        i += 1
    return out

def check(path):
    src = open(path, encoding="utf-8").read()
    stack = []
    prev = None
    for kind, val, line in tokens(src):
        if kind != "id":
            prev = None
            continue
        if val in ("function", "if", "do", "repeat"):
            if val == "do" and stack and stack[-1][0] in ("for", "while"):
                stack[-1] = (stack[-1][0] + "_do", stack[-1][1])
            else:
                stack.append((val, line))
        elif val in ("for", "while"):
            stack.append((val, line))
        elif val == "end":
            if not stack:
                return "extra end at line %d" % line
            stack.pop()
        elif val == "until":
            if not stack or stack[-1][0] != "repeat":
                return "bad until at %d" % line
            stack.pop()
        prev = val
    if stack:
        return "unclosed %s at line %d" % (stack[-1][0], stack[-1][1])
    return "ok"

for f in sys.argv[1:]:
    print(f, check(os.path.join(base, f)))
