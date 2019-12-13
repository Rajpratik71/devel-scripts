#!/usr/bin/python3
"""Utility functions for scripts in my bin diretory.

This module contains common utilities such as wrappers for
error/warning reporting, executing shell commands in a controlled way,
etc. These functions are shared by a number of helper scripts.

"""

import calendar
import locale
import os
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import time

# Debugging verbosity level (0 -> no output)
flag_debug = 0

# Unit testing mode. If set to 1, throw exception instead of calling exit()
flag_unittest = 0

hrszre = re.compile(r"^([\d\.]+)(\S)$")
factors = {"K": 1024.0, "M": 1048576.0, "G": 1073741824.0}
rfactors = [("GiB", 1073741824.0), ("MB", 1048576.0), ("KB", 1024.0)]


def verbose(level, msg):
  """Print debug trace output of verbosity level is >= value in 'level'."""
  if level <= flag_debug:
    sys.stderr.write(msg + "\n")


def verbosity_level():
  """Return debug trace level."""
  return flag_debug


def increment_verbosity():
  """Increment debug trace level by 1."""
  global flag_debug
  flag_debug += 1


def decrement_verbosity():
  """Lower debug trace level by 1."""
  global flag_debug
  flag_debug -= 1


def unit_test_enable():
  """Set unit testing mode."""
  global flag_unittest
  sys.stderr.write("+++ unit testing mode enabled +++\n")
  flag_unittest = 1


def warning(msg):
  """Issue a warning to stderr."""
  sys.stderr.write("warning: " + msg + "\n")


def error(msg):
  """Issue an error to stderr, then exit."""
  errm = "error: " + msg + "\n"
  sys.stderr.write(errm)
  if flag_unittest:
    raise Exception(errm)
  else:
    exit(1)


def docmd(cmd):
  """Run a command via subprocess, issuing fatal error if cmd fails."""
  args = shlex.split(cmd)
  verbose(2, "+ docmd executing: %s" % cmd)
  rc = subprocess.call(args)
  if rc != 0:
    error("command failed (rc=%d): %s" % (rc, cmd))


# Similar to docmd, but return status after issuing failure message
def docmdnf(cmd):
  """Run a command via subprocess, returning exit status."""
  args = shlex.split(cmd)
  verbose(2, "+ docmd executing: %s" % cmd)
  rc = subprocess.call(args)
  return rc


# Similar to docmd, but suppress output
def doscmd(cmd, nf=None, suppressErr=False):
  """Run a command via subprocess, suppressing output unless error."""
  verbose(2, "+ doscmd executing: %s" % cmd)
  args = shlex.split(cmd)
  cmdtf = tempfile.NamedTemporaryFile(mode="w", delete=True)
  rc = subprocess.call(args, stdout=cmdtf, stderr=cmdtf)
  if rc != 0:
    if suppressErr:
      return None
    warning("error: command failed (rc=%d) cmd: %s" % (rc, cmd))
    warning("output from failing command:")
    subprocess.call(["cat", cmdtf.name])
    if nf:
      return None
    error("")
  cmdtf.close()
  return True


# invoke command, writing output to file
def docmdout(cmd, outfile, nf=None):
  """Run a command via subprocess, writing output to a file."""
  verbose(2, "+ docmdout executing: %s > %s" % (cmd, outfile))
  args = shlex.split(cmd)
  with open(outfile, "w") as outfile:
    rc = subprocess.call(args, stdout=outfile)
    if rc != 0:
      warning("error: command failed (rc=%d) cmd: %s" % (rc, cmd))
      if nf:
        return None
      error("")
  return True


# invoke command, writing output to file
def docmderrout(cmd, outfile, nf=None):
  """Run a command via subprocess, writing output to a file."""
  verbose(2, "+ docmdout executing: %s > %s" % (cmd, outfile))
  args = shlex.split(cmd)
  try:
    with open(outfile, "w") as outfile:
      rc = subprocess.call(args, stdout=outfile, stderr=outfile)
      if rc != 0:
        if nf:
          sys.stderr.write("error: command failed "
                           "(rc=%d) cmd: %s\n" % (rc, cmd))
          return rc
        else:
          error("command failed (rc=%d) cmd: %s\n" % (rc, cmd))
      return rc
  except IOError:
    error("unable to open %s for writing" % outfile)
  return 1


# invoke command, reading from one file and writing to another
def docmdinout(cmd, infile, outfile):
  """Run a command via subprocess with input and output file."""
  verbose(2, "+ docmdinout executing: %s < %s > %s" % (cmd, infile, outfile))
  args = shlex.split(cmd)
  cmdtf = tempfile.NamedTemporaryFile(mode="w", delete=True)
  with open(infile, "r") as inf:
    with open(outfile, "w") as outf:
      rc = subprocess.call(args, stdout=outf, stdin=inf, stderr=cmdtf)
      if rc != 0:
        warning("error: command failed (rc=%d) cmd: %s" % (rc, cmd))
        warning("output from failing command:")
        subprocess.call(["cat", cmdtf.name])
        return 1
  verbose(2, "+ finished: %s < %s > %s" % (cmd, infile, outfile))
  return 0


# invoke command, returning array of lines read from it
def docmdlines(cmd, nf=None):
  """Run a command via subprocess, returning output as an array of lines."""
  verbose(2, "+ docmdlines executing: %s" % cmd)
  args = shlex.split(cmd)
  mypipe = subprocess.Popen(args, stdout=subprocess.PIPE)
  encoding = locale.getdefaultlocale()[1]
  pout, perr = mypipe.communicate()
  if mypipe.returncode != 0:
    if perr:
      decoded_err = perr.decode(encoding)
      warning(decoded_err)
    if nf:
      return None
    error("command failed (rc=%d): cmd was %s" % (mypipe.returncode, args))
  decoded = pout.decode(encoding)
  lines = decoded.strip().split("\n")
  return lines


# invoke command, returning raw bytes from read
def docmdbytes(cmd, nf=None):
  """Run a command via subprocess, returning output as raw bytestring."""
  args = shlex.split(cmd)
  mypipe = subprocess.Popen(args, stdout=subprocess.PIPE)
  pout, perr = mypipe.communicate()
  if mypipe.returncode != 0:
    encoding = locale.getdefaultlocale()[1]
    if perr:
      decoded_err = perr.decode(encoding)
      warning(decoded_err)
    if nf:
      return None
    error("command failed (rc=%d): cmd was %s" % (mypipe.returncode, args))
  return pout


# invoke a command with input coming from an echo'd string, e.g.
# Ex: "echo 1+2 | perl"
def docmdinstring(cmd, instring):
  """Invoke a command with stdin coming from a specific string."""
  verbose(2, "+ docmdinstring executing: echo %s | %s " % (cmd, instring))
  args = shlex.split(cmd)
  mypipe = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
  encoding = locale.getdefaultlocale()[1]
  sb = instring.encode("utf-8")
  pout, perr = mypipe.communicate(sb)
  if mypipe.returncode != 0:
    if perr:
      decoded_err = perr.decode(encoding)
      warning(decoded_err)
    error("command failed (rc=%d): cmd was %s" % (mypipe.returncode, args))
  decoded = pout.decode(encoding)
  lines = decoded.strip().split("\n")
  return lines


# Execute a command with an alarm timeout.
def docmdwithtimeout(cmd, timeout_duration):
  """Run a command via subprocess, returning exit status or -1 if timeout."""

  class TimeoutError(Exception):
    pass

  def handler(signum, _):
    verbose(9, "handler: signal %d" % signum)
    raise TimeoutError()

  # set the timeout handler
  prevhandler = signal.signal(signal.SIGALRM, handler)
  signal.alarm(timeout_duration)
  try:
    result = docmdnf(cmd)
  except TimeoutError as exc:
    verbose(1, "timeout triggered after %d "
            "seconds: %s" % (timeout_duration, str(exc)))
    result = -1
  finally:
    signal.alarm(0)
    signal.signal(signal.SIGALRM, prevhandler)
  return result


# perform default locale setup if needed
def setdeflanglocale():
  if "LANG" not in os.environ:
    warning("no env setting for LANG -- using default values")
    os.environ["LANG"] = "en_US.UTF-8"
    os.environ["LANGUAGE"] = "en_US:"


def determine_btrfs_ssdroot(here):
  """Determine ssd root."""

  path_components = here.split("/")
  root = "/%s" % path_components[1]
  verbose(2, "cwd=%s root=%s" % (here, root))

  # Is this a BTRFS ssd to begin with?
  outlines = docmdlines("stat -f --printf=%%T %s" % root)
  if not outlines:
    error("internal error-- could not determine FS type "
          "for root dir %s" % root)
  if outlines[0] != "btrfs":
    error("current FS type is %s, not btrfs (can't proceed)" % outlines[0])
  return root


def hr_size_to_bytes(sz):
  """Convert human readable size back to bytes."""
  m = hrszre.match(sz)
  if not m:
    warning("unmatchable size expr %s" % sz)
    return None
  val = float(m.group(1))
  facs = m.group(2)
  if facs not in factors:
    warning("unknown factor '%s' in size expr %s" % (facs, sz))
    return None
  fac = factors[facs]
  nb = int(val * fac)
  return nb


def bytes_to_hr_size(sz):
  """Convert bytes to human readable size."""
  fb = float(sz)
  for p in rfactors:
    tag = p[0]
    fac = p[1]
    frac = fb / fac
    if frac < 1.0:
      continue
    return "%2.1f%s" % (frac, tag)
  return "%d bytes" % sz


def trim_perf_report_file(infile):
  """Trim trailing spaces from lines in perf report."""
  verbose(1, "trim: reading " + infile)
  try:
    f = open(infile, "r")
  except IOError:
    warning("unable to open file %s for reading" % infile)
    return 1
  lines = f.readlines()
  f.close()
  verbose(1, "trim: rewriting " + infile)
  try:
    ft = open(infile, "w")
  except IOError:
    warning("unable to open file %s for rewriting" % infile)
    return 1
  for line in lines:
    sline = line.rstrip()
    ft.write(sline + "\n")
  ft.close()
  return 0


# Return value is branch, mods, untracked, renames, rev_renames
def get_git_status():
  """Collect and return info from git status -sb."""
  stcmd = "git status -sb"
  verbose(1, "modfiles git cmd: %s" % stcmd)
  lines = docmdlines(stcmd)

  # key is file, value is M/A/D
  modifications = {}

  # key is old file, val is new file
  renames = {}

  # untracked files
  untracked = {}

  # key is new file, val is old file
  rev_renames = {}

  # First line
  branch = None
  line = lines[0]
  bs = [re.compile(r"^\#\#\s+(\S+)\.\.(\S+)\s.*$"),
        re.compile(r"^\#\#\s+(\S+)\s*$")]
  for b in bs:
    m = b.match(line)
    if not m:
      continue
    branch = m.group(1)
  if not branch:
    error("internal error: pattern match failed "
          "for git status line %s" % line)

  # Remaining lines
  rs = re.compile(r"^\s*$")
  rb = re.compile(r"^\S+\.~\d+~$")
  r1 = re.compile(r"^(\S+)\s+(\S+)$")
  r2 = re.compile(r"^(\S+)\s+(\S+) \-\> (\S+)$")
  for line in lines[1:]:
    verbose(2, "git status line: +%s+" % line.strip())
    ms = rs.match(line)
    if ms:
      continue
    m1 = r1.match(line)
    if m1:
      op = m1.group(1)
      modfile = m1.group(2)
      if op == "??":
        untracked[modfile] = 1
        continue
      if op == "AM" or op == "MM":
        if rb.match(modfile):
          continue
        error("found modified or untracked "
              "file %s -- please run git add ." % modfile)
      if op != "A" and op != "M" and op != "D":
        error("internal error: bad op %s in git "
              "status line %s" % (op, line.strip()))
      if modfile in modifications:
        error("internal error: mod file %s "
              "already in table" % modfile)
      modifications[modfile] = op
      continue
    m2 = r2.match(line)
    if m2:
      op = m2.group(1)
      oldfile = m2.group(2)
      newfile = m2.group(3)
      if op == "RM":
        error("found modified file %s -- please run git add ." % newfile)
      if oldfile in modifications:
        error("internal error: src rename %s "
              "already in modifications table" % oldfile)
      if oldfile in renames:
        error("internal error: src rename %s "
              "already in modifications table" % oldfile)
      if op == "R":
        renames[oldfile] = newfile
        rev_renames[newfile] = oldfile
        if newfile in modifications:
          error("internal error: dest of rename %s "
                "already in modifications table" % newfile)
        renames[oldfile] = newfile
        rev_renames[newfile] = oldfile
        modifications[newfile] = "M"
      else:
        error("internal error: unknown op %s "
              "in git status line %s" % (op, line))
      continue
    error("internal error: pattern match failed "
          "for git status line %s" % line)
    return branch, modifications, untracked, renames, rev_renames


def seconds():
  """Return seconds since epoch."""
  return calendar.timegm(time.gmtime())
