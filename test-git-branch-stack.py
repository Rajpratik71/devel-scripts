#!/usr/bin/python3
"""Runs all.bash against each commit on a git development branch.

For a given development branch, do an all.bash test for each commit on the
branch, storing results in. Example from git log --oneline for hypothetical
development branch 'mybranch':

  ca3b66ca8d (HEAD -> mybranch) finalthing
  51df6b49da anotherthing
  2b3ddf5180 firstthing
  7fa195c1b9 (origin/master, origin/HEAD, master) unrelated

This script will produce the following dumps:

  /tmp/item=1.branch=mybranch.commit=ca3b66ca8d.txt
  /tmp/item=2.branch=mybranch.commit=51df6b49da.txt
  /tmp/item=3.branch=mybranch.commit=2b3ddf5180.txt
  /tmp/item=4.branch=mybranch.index.txt

where each 'commit' file contains the output from an all.bash run
on that commit.
"""

import getopt
import os
import re
import sys
import tempfile

import script_utils as u

# Echo command before executing
flag_echo = True

# Dry run mode
flag_dryrun = False

# Tag to apply to output files.
flag_tag = None

# Script to run
flag_script_to_run = "all.bash"

# Package tests to run
flag_pkgtests = []

# Files emitted
files_emitted = []

# Failures
num_failures = 0


def docmd(cmd):
  """Execute a command."""
  if flag_echo:
    sys.stderr.write("executing: " + cmd + "\n")
  if flag_dryrun:
    return
  u.docmd(cmd)


def doscmd(cmd):
  """Execute a command."""
  if flag_echo:
    sys.stderr.write("executing: " + cmd + "\n")
  if flag_dryrun:
    return
  u.doscmd(cmd)


def docmdout(cmd, outfile):
  """Execute a command to an output file."""
  if flag_echo:
    sys.stderr.write("executing: " + cmd + "\n")
  if flag_dryrun:
    return
  u.docmdout(cmd, outfile)


def docmdinout(cmd, infile, outfile):
  """Execute a command reading from input file and writing to output file."""
  if flag_echo:
    sys.stderr.write("executing: %s < %s > %s\n" % (cmd, infile, outfile))
  if flag_dryrun:
    return
  u.docmdinout(cmd, infile, outfile)


def process_commit(idx, branchname, githash, comment, summaryf):
  """Process a commit by hash."""
  tag = ""
  if flag_tag:
    tag = ".tag=%s" % flag_tag
  fn = "/tmp/item%d.branch%s%s.commit%s.txt" % (idx, branchname, tag, githash)
  if flag_dryrun:
    u.verbose(0, "<dryrun: run %s for %s to %s>" % (flag_script_to_run,
                                                    githash, fn))
    return
  files_emitted.append(fn)
  doscmd("git checkout %s" % githash)
  try:
    outf = open(fn, "w")
  except IOError as e:
    u.error("unable to open %s: %s" % (fn, e.strerror))
  outf.write("// comment: %s\n" % comment)
  outf.write("//\n")
  lines = u.docmdlines("git log --name-only -1 %s" % githash)
  if not lines:
    u.error("empty output from 'git log --name-only -1 %s'" % githash)
  for line in lines:
    outf.write(line)
    outf.write("\n")
  outf.write("--------------------------------------------------------------\n")
  lines = u.docmdlines("git diff %s^ %s" % (githash, githash))
  if not lines:
    u.error("empty output from 'git diff %s^ %s'" % (githash, githash))
  for line in lines:
    outf.write(line)
    outf.write("\n")
  u.verbose(1, "wrote %d diff lines to %s" % (len(lines), fn))
  if flag_script_to_run:
    dotestaction("bash %s" % flag_script_to_run, githash, outf, idx, summaryf)
  for pk in flag_pkgtests:
    dotestaction("go test %s" % pk, githash, outf, idx, summaryf)
  outf.close()


def dotestaction(action, githash, outf, idx, summaryf):
  """Perform a test action, writing results to outf."""
  global num_failures
  u.verbose(0, "starting %s run for %s" % (action, githash))
  tf = tempfile.NamedTemporaryFile(mode="w", delete=True)
  status = u.docmderrout(action, tf.name, True)
  if status != 0:
    u.verbose(0, "warning: '%s' run failed for commit %s" % (action, githash))
    summaryf.write("%d: failed action: %s\n" % (idx, action))
    num_failures += 1
  try:
    with open(tf.name, "r") as rf:
      lines = rf.readlines()
      for line in lines:
        outf.write(line)
      u.verbose(1, "wrote %d test output lines to %s" % (len(lines), outf.name))
  except IOError:
    u.error("open failed for %s temp output %s" % (action, tf.name))


def perform():
  """Main driver routine."""
  if flag_script_to_run and not os.path.exists(flag_script_to_run):
    u.error("no %s here, can't proceed" % flag_script_to_run)
  lines = u.docmdlines("git status -sb")
  if not lines:
    u.error("empty output from git status -sb")
  brnreg = re.compile(r"^## (\S+)\.\.(\S+) \[ahead (\d+)\]\s*$")
  m = brnreg.match(lines[0])
  if not m:
    u.error("can't pattern match output of git status -sb: %s" % lines[0])
  branchname = m.group(1).strip(".")
  commits = int(m.group(3))
  u.verbose(1, "branch is: %s commits: %d" % (branchname, commits))

  # Grab info on commits
  lines = u.docmdlines("git log --oneline -%d" % commits)
  if not lines:
    u.error("empty output from 'git log --oneline'")

  # Open index file for output
  fn = "/tmp/branch=%s.index.txt" % branchname
  try:
    outf = open(fn, "w")
  except IOError as e:
    u.error("unable to open %s: %s" % (fn, e.strerror))

  # Process commits in reverse order
  firsthash = None
  lasthash = None
  creg = re.compile(r"^(\S+) (\S.+)$")
  lines.reverse()
  idx = 0
  for cl in lines:
    idx += 1
    m = creg.match(cl)
    if not m:
      u.error("can't pattern match git log output: %s" % cl)
    githash = m.group(1)
    lasthash = githash
    if not firsthash:
      firsthash = githash
    comment = m.group(2)
    u.verbose(0, "processing hash %s comment %s" % (githash, comment))
    process_commit(idx, branchname, githash, comment, outf)
  doscmd("git checkout %s" % branchname)

  # Emit index file
  n = len(files_emitted) + 1
  outf.write("Files emitted:\n\n")
  outf.write(" ".join(files_emitted))
  outf.write("\n\nBranch log:\n\n")
  u.verbose(1, "index diff cmd hashes: %s %s" % (firsthash, lasthash))
  outf.write("\n")
  lines = u.docmdlines("git log --name-only -%d HEAD" % len(files_emitted))
  for line in lines:
    outf.write(line)
    outf.write("\n")
  outf.close()
  u.verbose(0, "... index file emitted to %s\n" % fn)
  u.verbose(0, "... total failures: %d\n" % num_failures)


def usage(msgarg):
  """Print usage and exit."""
  me = os.path.basename(sys.argv[0])
  if msgarg:
    sys.stderr.write("error: %s\n" % msgarg)
  print("""\
    usage:  %s [options]

    options:
    -t T  tag output files with tag T
    -e    echo commands before executing
    -d    increase debug msg verbosity level
    -m    run make.bash instead of all.bash
    -n    don't run make.bash or all.bash
    -p P  run 'go test P' for package P at each commit
    -D    dryrun mode (echo commands but do not execute)

    This program walks the stack of commits for a given git
    development branch and runs all.bash for each commit
    into /tmp.

    Example usage:

    %s

    """ % (me, me))

  sys.exit(1)


def parse_args():
  """Command line argument parsing."""
  global flag_echo, flag_dryrun, flag_tag, flag_script_to_run, flag_pkgtests

  try:
    optlist, args = getopt.getopt(sys.argv[1:], "dmneDp:t:")
  except getopt.GetoptError as err:
    # unrecognized option
    usage(str(err))

  if args:
    usage("unknown extra args: %s" % " ".join(args))

  for opt, arg in optlist:
    if opt == "-d":
      u.increment_verbosity()
    elif opt == "-m":
      flag_script_to_run = "make.bash"
    elif opt == "-n":
      flag_script_to_run = None
    elif opt == "-D":
      u.verbose(0, "+++ dry run mode")
      flag_dryrun = True
      flag_echo = True
    elif opt == "-e":
      flag_echo = True
    elif opt == "-t":
      flag_tag = arg
    elif opt == "-p":
      if not os.path.exists(arg):
        u.warning("can't access package %s, ignored for -p" % arg)
      flag_pkgtests.append(arg)


#......................................................................
#
# Main portion of script
#
parse_args()
u.setdeflanglocale()
perform()
exit(0)
