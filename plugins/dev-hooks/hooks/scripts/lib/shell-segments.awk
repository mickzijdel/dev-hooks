# shell-segments.awk — split a bash command line into the simple commands it runs, for
# dangerous-command-guard.sh. POSIX awk (mawk, gawk, BSD awk); reads the command on stdin.
#
# Output: one simple command per line. Words are separated by \037 with their quotes
# removed; leading assignments, wrappers (sudo, env, xargs, timeout, …) and reserved
# words ({, !, if, then, …) are dropped, so the first word is the command itself. Each
# redirection is one word starting with \035 (`\0352>&1`, `\035>/dev/null`), placed after
# the command's other words.
#
# Quoting decides what is code: single quotes and quoted heredoc bodies are data, so
# `rg "fnox get|bws secret get"` is one command, not two. What the shell would *run* is
# emitted as commands of its own: $(…), `…` and <(…) (also inside double quotes and
# unquoted heredocs), the string given to `bash -c`/`sh -c`/`eval`/`ssh host`, and a
# heredoc body fed to a shell (`bash <<EOF`).
#
# A command whose output is captured into a variable (`v=$(fnox get X)`,
# `KEY="$(cat master.key)" bin/rails …`, `export T=$(…)`) prints nothing, so its line
# carries an extra `\035=captured` word, as do the commands nested inside it.
#
# On an unbalanced quote or substitution it prints the old quote-blind split instead
# (split on ; & | and newlines, then on blanks), so a parse failure never hides a command.

BEGIN {
  US = "\037"
  RD = "\035"
  D = 0
  ERR = 0
  OUT = ""
  split("bash sh zsh dash ksh fish", tmp, " ")
  for (t in tmp) SHELLS[tmp[t]] = 1
  split("sudo doas command builtin nohup time env xargs exec nice ionice stdbuf timeout", tmp, " ")
  for (t in tmp) WRAPPERS[tmp[t]] = 1
  split("{ } ! if then do else elif while until", tmp, " ")
  for (t in tmp) KEYWORDS[tmp[t]] = 1
  split("export local declare typeset readonly", tmp, " ")
  for (t in tmp) DECLARERS[tmp[t]] = 1
  CAPNEXT = 0
}

{ SRC = (NR == 1) ? $0 : SRC "\n" $0 }

END {
  tokenize(SRC)
  if (ERR) printf "%s", naive(SRC)
  else printf "%s", OUT
}

function basename(w) {
  sub(/.*\//, "", w)
  return w
}

# Does a wrapper take the next word as its option's value?
function takes_value(wrapper, opt) {
  if (wrapper == "sudo" || wrapper == "doas") return opt ~ /^-[ugCDhprtUT]$/
  if (wrapper == "env") return opt ~ /^-[uCS]$/
  if (wrapper == "nice") return opt == "-n"
  if (wrapper == "ionice") return opt ~ /^-[cnp]$/
  if (wrapper == "timeout") return opt ~ /^-[sk]$/
  if (wrapper == "xargs") return opt ~ /^-[IndPLsEa]$/
  return 0
}

# Drop assignments, wrappers and reserved words in front of the command; move the
# redirections to the end. Returns "" when no command word is left.
function finish(seg,    a, n, i, w, words, redirs, wrapper, cw) {
  n = split(seg, a, US)
  words = ""
  redirs = ""
  wrapper = ""
  cw = 0
  for (i = 1; i <= n; i++) {
    w = a[i]
    if (substr(w, 1, 1) == RD) {
      redirs = redirs US w
      continue
    }
    if (!cw) {
      if (w ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/ || (w in KEYWORDS)) continue
      if (basename(w) in WRAPPERS) {
        wrapper = basename(w)
        continue
      }
      if (wrapper != "" && substr(w, 1, 1) == "-") {
        if (takes_value(wrapper, w)) i++
        continue
      }
      # timeout's duration
      if (wrapper == "timeout" && w ~ /^[0-9.]+[smhd]?$/) continue
      cw = 1
      words = w
      continue
    }
    words = words US w
  }
  if (!cw) return ""
  return words redirs
}

# The quote-blind fallback: what the guard did before it honoured quoting.
function naive(s,    out, lines, n, i, ws, m, j, seg, f) {
  gsub(/[;&|]/, "\n", s)
  n = split(s, lines, "\n")
  out = ""
  for (i = 1; i <= n; i++) {
    m = split(lines[i], ws, /[ \t]+/)
    seg = ""
    for (j = 1; j <= m; j++)
      if (ws[j] != "") seg = (seg == "") ? ws[j] : seg US ws[j]
    f = finish(seg)
    if (f != "") out = out f "\n"
  }
  return out
}

function add(x) {
  gsub(/\n/, " ", x)
  SG[D] = (NWD[D]++) ? SG[D] US x : x
}

function flushw(    f, a) {
  if (!INW[D]) return
  if (PH[D] != "") {
    NH[D]++
    HDL[D, NH[D]] = WB[D]
    HDQ[D, NH[D]] = WQ[D]
    HDS[D, NH[D]] = (PH[D] == "<<-")
    f = finish(SG[D])
    split(f, a, US)
    HDO[D, NH[D]] = basename(a[1])
    PH[D] = ""
  } else if (PR[D] != "") {
    add(RD PR[D] WB[D])
    PR[D] = ""
  } else {
    add(WB[D])
  }
  WB[D] = ""
  INW[D] = 0
  WQ[D] = 0
  ASSIGN[D] = 0
}

function flushseg() {
  flushw()
  if (NWD[D] > 0) emit(SG[D])
  SG[D] = ""
  NWD[D] = 0
  PR[D] = ""
}

# Record one simple command, then tokenize any command string it hands to a shell.
function emit(seg,    f, a, n, name, k, host, rest) {
  f = finish(seg)
  if (f == "") return
  OUT = OUT f (CAP[D] ? US RD "=captured" : "") "\n"
  if (D > 8) return
  n = split(f, a, US)
  while (n > 0 && substr(a[n], 1, 1) == RD) n--
  name = basename(a[1])
  if (name in SHELLS) {
    for (k = 2; k < n; k++)
      if (a[k] ~ /^-[A-Za-z]*c[A-Za-z]*$/) {
        CAPNEXT = CAP[D]
        tokenize(a[k + 1])
        return
      }
  } else if (name == "eval") {
    rest = ""
    for (k = 2; k <= n; k++) rest = rest " " a[k]
    CAPNEXT = CAP[D]
    tokenize(rest)
  } else if (name == "ssh") {
    host = 0
    rest = ""
    for (k = 2; k <= n; k++) {
      if (!host) {
        if (a[k] ~ /^-[bcDEeFIiJLlmOopQRSWw]$/) k++
        else if (substr(a[k], 1, 1) != "-") host = 1
        continue
      }
      rest = rest " " a[k]
    }
    CAPNEXT = CAP[D]
    if (rest != "") tokenize(rest)
  }
}

# Index of the ")" matching the "(" at p, skipping quoted text; 0 if unbalanced.
function mparen(s, p,    n, depth, i, c, j) {
  n = length(s)
  depth = 0
  for (i = p; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\") {
      i++
    } else if (c == "'") {
      j = index(substr(s, i + 1), "'")
      if (!j) return 0
      i += j
    } else if (c == "\"") {
      for (i++; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") i++
        else if (c == "\"") break
      }
      if (i > n) return 0
    } else if (c == "(") {
      depth++
    } else if (c == ")") {
      if (--depth == 0) return i
    }
  }
  return 0
}

# Index of the next unescaped backtick after i; 0 if none.
function mbacktick(s, i,    n, c) {
  n = length(s)
  for (i++; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\") i++
    else if (c == "`") return i
  }
  return 0
}

# A substitution starting at i ($( , <( , >( or `): tokenize its body as commands and
# return the index of its last character, or 0 if it never closes.
function subst(s, i,    c, j, inner, f, a) {
  c = substr(s, i, 1)
  if (c == "`") {
    j = mbacktick(s, i)
    if (!j) return 0
    inner = substr(s, i + 1, j - i - 1)
    gsub(/\\`/, "`", inner)
  } else {
    j = mparen(s, i + 1)
    if (!j) return 0
    inner = substr(s, i + 2, j - i - 2)
  }
  # Captured when the substitution is an assignment's value: the word began with an
  # unquoted `NAME=` and the segment has no command yet, or only a declarer (`export`).
  CAPNEXT = CAP[D]
  if (ASSIGN[D] && c != "<" && c != ">") {
    f = finish(SG[D])
    split(f, a, US)
    if (f == "" || a[1] in DECLARERS) CAPNEXT = 1
  }
  tokenize(inner)
  return j
}

# Double-quoted text from i (just past the opening quote) — or a whole unquoted heredoc
# body when body is set. Appends the literal text to the current word, tokenizes the
# substitutions inside, and returns the index of the closing quote (0 if unclosed).
function dquote(s, i, body,    n, c, nx, j) {
  n = length(s)
  for (; i <= n; i++) {
    c = substr(s, i, 1)
    nx = substr(s, i + 1, 1)
    if (c == "\\") {
      WB[D] = WB[D] nx
      i++
    } else if (c == "\"" && !body) {
      return i
    } else if ((c == "$" && nx == "(") || c == "`") {
      j = subst(s, i)
      if (!j) return 0
      WB[D] = WB[D] substr(s, i, j - i + 1)
      i = j
    } else {
      WB[D] = WB[D] c
    }
  }
  return body ? n : 0
}

# After a newline: read the pending heredoc bodies starting at p; return the index just
# past the last delimiter line.
function heredocs(s, p,    n, h, lend, line, t, body, savewb) {
  n = length(s)
  for (h = 1; h <= NH[D]; h++) {
    body = ""
    while (p <= n) {
      lend = index(substr(s, p), "\n")
      line = lend ? substr(s, p, lend - 1) : substr(s, p)
      p = lend ? p + lend : n + 1
      t = line
      if (HDS[D, h]) sub(/^\t+/, "", t)
      if (t == HDL[D, h]) break
      body = body line "\n"
    }
    if (HDO[D, h] in SHELLS || HDO[D, h] == "ssh") {
      CAPNEXT = CAP[D]
      tokenize(body)
    } else if (!HDQ[D, h]) {
      savewb = WB[D]
      dquote(body, 1, 1)
      WB[D] = savewb
    }
  }
  NH[D] = 0
  return p
}

function tokenize(s,    n, i, c, nx, j, op, fd) {
  D++
  CAP[D] = CAPNEXT
  CAPNEXT = 0
  WB[D] = ""
  INW[D] = 0
  WQ[D] = 0
  ASSIGN[D] = 0
  SG[D] = ""
  NWD[D] = 0
  PR[D] = ""
  PH[D] = ""
  NH[D] = 0
  n = length(s)
  i = 1
  while (i <= n && !ERR) {
    c = substr(s, i, 1)
    nx = substr(s, i + 1, 1)
    if (c == "\\") {
      if (nx != "\n") {
        WB[D] = WB[D] nx
        INW[D] = 1
        WQ[D] = 1
      }
      i += 2
    } else if (c == "'" || (c == "$" && nx == "'")) {
      if (c == "$") i++
      j = index(substr(s, i + 1), "'")
      if (!j) {
        ERR = 1
        break
      }
      WB[D] = WB[D] substr(s, i + 1, j - 1)
      INW[D] = 1
      WQ[D] = 1
      i += j + 1
    } else if (c == "\"") {
      INW[D] = 1
      WQ[D] = 1
      j = dquote(s, i + 1, 0)
      if (!j) {
        ERR = 1
        break
      }
      i = j + 1
    } else if ((c == "$" && nx == "(") || c == "`" || ((c == "<" || c == ">") && nx == "(")) {
      j = subst(s, i)
      if (!j) {
        ERR = 1
        break
      }
      WB[D] = WB[D] substr(s, i, j - i + 1)
      INW[D] = 1
      i = j + 1
    } else if (c == "$" && nx == "{") {
      j = index(substr(s, i), "}")
      if (!j) {
        ERR = 1
        break
      }
      WB[D] = WB[D] substr(s, i, j)
      INW[D] = 1
      i += j
    } else if (c == "#" && !INW[D]) {
      j = index(substr(s, i), "\n")
      i = j ? i + j - 1 : n + 1
    } else if (c == ">" || c == "<" || (c == "&" && nx == ">")) {
      fd = ""
      if (c != "&" && INW[D] && !WQ[D] && WB[D] ~ /^[0-9]+$/) {
        fd = WB[D]
        WB[D] = ""
        INW[D] = 0
      } else {
        flushw()
      }
      op = c
      for (i++; i <= n && length(op) < 3; i++) {
        c = substr(s, i, 1)
        if (c == ">" || c == "<" || c == "&" || c == "|" || (c == "-" && op == "<<")) op = op c
        else break
      }
      if (op == "<<" || op == "<<-") PH[D] = op
      else PR[D] = fd op
    } else if (c == " " || c == "\t") {
      flushw()
      i++
    } else if (c == "\n") {
      flushseg()
      i = (NH[D] > 0) ? heredocs(s, i + 1) : i + 1
    } else if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")") {
      flushseg()
      i++
    } else {
      if (c == "=" && !WQ[D] && WB[D] ~ /^[A-Za-z_][A-Za-z0-9_]*\+?$/) ASSIGN[D] = 1
      WB[D] = WB[D] c
      INW[D] = 1
      i++
    }
  }
  flushseg()
  D--
}
