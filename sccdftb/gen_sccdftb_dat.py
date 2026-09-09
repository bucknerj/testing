#!/usr/bin/env python3
"""Generate the per-element SCC-DFTB parameter index files the testcases ask for.

    usage: gen_sccdftb_dat.py [SKF_DIR] [OUT_DIR]

    SKF_DIR  directory holding the 3ob .skf files  (default $SCCDFTB_DATA/skf)
    OUT_DIR  where to write sccdftb_<ELEMENTS>.dat (default $SCCDFTB_DATA)

Why this is generated rather than checked in
--------------------------------------------
Each file names its .skf files by ABSOLUTE path, so a checked-in copy is only
correct on the machine it was made on.  That is not hypothetical: the copy that
shipped in sccdftb_data/ pointed at /opt/jenkins_data/skf, which exists on the
Jenkins host and nowhere else, so every sccdftb testcase on the cluster failed
to find its parameters.  Generating per host removes that whole class of
breakage.  The .skf set itself is third-party and is NOT redistributed here --
see README.md.

File format (as CHARMM's SCCDFTB reader expects it)
---------------------------------------------------
    '<skf_dir>/X-Y.skf'     one line per ordered element pair, row-major over
    ...                     the element list, so N*N lines for N elements
    'X' <hubbard>           one line per element, in the SAME order
    ...
    <zeta>                  gamma^h exponent

ELEMENT ORDER IS SIGNIFICANT.  It must match the WMAIN numbering the testcase
assigns to its QM atoms, because CHARMM uses WMAIN as an index into this list.
c43test/malon_mcec.inp sets WMAIN 1=C, 2=H, 3=O and asks for sccdftb_CHO.dat;
the order in the filename is therefore the order in the file.  Get this wrong
and the run still completes, having silently assigned the wrong element to
every atom.

Hubbard derivatives and zeta below are transcribed from the skf set's own
README ("List of all atomic Hubbard derivatives (atomic units)" and
"zeta = 4.00").  If you point this at a different parameter set, these are
wrong -- check them against that set's documentation.
"""
import os
import sys

# Verbatim from the 3ob skf README.
HUBBARD = {
    "Br": -0.0573, "C": -0.1492, "Ca": -0.0340, "Cl": -0.0697, "F": -0.1623,
    "H": -0.1857, "I": -0.0433, "K": -0.0339, "Mg": -0.02, "N": -0.1535,
    "Na": -0.0454, "O": -0.1575, "P": -0.14, "S": -0.11, "Zn": -0.03,
}
ZETA = "4.00"

# Element order as the testcases spell it in the filename.  Only sets whose
# elements are all in HUBBARD and whose .skf pairs are all present get written.
WANTED = {
    "sccdftb_ONCH.dat": ["O", "N", "C", "H"],
    "sccdftb_CHO.dat":  ["C", "H", "O"],
    "sccdftb_OH.dat":   ["O", "H"],
    "sccdftb_CH.dat":   ["C", "H"],
    "sccdftb_SCH.dat":  ["S", "C", "H"],
    "sccdftb_OCPH.dat": ["O", "C", "P", "H"],
}

# Needed by testcases we cannot generate for; see README.md.
UNSUPPORTED = {
    "sccdftb_CHQ.dat": "needs a Q species for QQ* link atoms",
    "sccdftb_CH_spin.dat": "needs mio-1-1 plus spin constants",
}


def main():
    default_root = os.environ.get(
        "SCCDFTB_DATA", os.path.expanduser("~/testing/sccdftb_data"))
    skf = sys.argv[1] if len(sys.argv) > 1 else os.path.join(default_root, "skf")
    out = sys.argv[2] if len(sys.argv) > 2 else default_root

    if not os.path.isdir(skf):
        print(f"gen_sccdftb_dat: no skf directory at {skf}", file=sys.stderr)
        return 1
    os.makedirs(out, exist_ok=True)

    wrote = skipped = 0
    for name, elems in sorted(WANTED.items()):
        pairs, missing = [], []
        for a in elems:
            for b in elems:
                path = os.path.join(skf, f"{a}-{b}.skf")
                if not os.path.isfile(path):
                    missing.append(f"{a}-{b}.skf")
                pairs.append(f"'{path}'")
        absent = [e for e in elems if e not in HUBBARD]
        if missing or absent:
            why = []
            if missing:
                why.append("missing skf: " + " ".join(missing))
            if absent:
                why.append("no Hubbard derivative for: " + " ".join(absent))
            print(f"  skip  {name}  ({'; '.join(why)})")
            skipped += 1
            continue
        body = pairs + [f"'{e}' {HUBBARD[e]}" for e in elems] + [ZETA]
        with open(os.path.join(out, name), "w") as fh:
            fh.write("\n".join(body) + "\n")
        print(f"  write {name}  ({len(elems)} elements, {len(elems) ** 2} pairs)")
        wrote += 1

    for name, why in sorted(UNSUPPORTED.items()):
        print(f"  n/a   {name}  ({why})")

    print(f"gen_sccdftb_dat: {wrote} written, {skipped} skipped, "
          f"{len(UNSUPPORTED)} unsupported, in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
