#!/usr/bin/perl -w

#
# Reads tests from an output.rpt
# Runs compare.awk to determine pass/fail
# Writes an output.xml like the JUnit Ant task
# Mike Garrahan, 2009
#

use strict;

# if (@ARGV != 1) {
#    die "Usage: $0 outdir\n";
# }

if (@ARGV != 1) {
    die "Usage: $0 <charmm test dir>\n";
}

my $chm_test_dir = $ARGV[0];

my $outdir = "$chm_test_dir/output";
my $benchdir = "$chm_test_dir/bench";
my $rptfile = "$chm_test_dir/output.rpt";
my $xfailfile = "$chm_test_dir/output.xfail";
my $awkfile = "$chm_test_dir/compare.awk";
my $chmdiff = "$chm_test_dir/charmmdif";

# Returns a copy of its argument modified for safe inclusion in XML.
sub xmlEscape($) {
   my $rv = shift;
   $rv =~ s/&/&amp;/g; # must do first
   $rv =~ s/</&lt;/g;
   $rv =~ s/>/&gt;/g;
   $rv =~ s/"/&quot;/g;
   $rv =~ s/'/&apos;/g;
   $rv =~ s/[^[:cntrl:][:print:]]/*/g;
   return $rv;
}

my %suites = ();
my %result = ();
my $test;
my $suite;
open RPT, "< $rptfile" or die "$rptfile: $!";
while (<RPT>) {
   if (/^<\*\* (c.+test) : (\S+) \*\*>/) {
      $suite = $1;
      $test = $2;
      if (not exists $suites{$suite}) {
         $suites{$suite} = [];
      }
      push @{$suites{$suite}}, $test;
      next;
   }
   next if not defined($test);
   if (/^ Test NOT performed/) {
       $result{$test} = "ignored";
   } elsif (/^\*{5} NO TERMINATION/) {
       $result{$test} = "crashed";
   } elsif (/^\*{5} ABNORMAL TERMINATION/) {
       $result{$test} = "crashed";
   }
}
close RPT;

open AWK, "awk -f $awkfile $rptfile |" or die;
while (<AWK>) {
   if (/TEST (\S+) (\w+)/) {
      $test = $1;
      next if exists $result{$test};
      $result{$test} = lc $2;
   }
}
close AWK;

my %xfail = ();
my $maxfail = 10;
if (-e $xfailfile) {
   open XFAIL, "< $xfailfile" or die;
   foreach $test (<XFAIL>) {
      chomp $test;
      $xfail{$test} = 1;
   }
   close XFAIL;
   $xfail{"placeholder"} = 1;
}

print STDOUT "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
print STDOUT "<testsuites>\n";
my @failures = ();
my @skips = ();
my $tot_testct = 0;
foreach $suite (sort keys %suites) {
   my $testct = 0;
   my $skipct = 0;
   my $failct = 0;
   my %fail_lines = ();
   foreach $test (@{$suites{$suite}}) {
       ++$testct;
      if (($result{$test} eq "failed" or $result{$test} eq "crashed") and not exists $xfail{"$suite/$test"}) {
         push @failures, "$suite/$test";
         ++$failct;
      }
      elsif ($result{$test} eq "ignored" or exists $xfail{"$suite/$test"}) {
          push @skips, "$suite/$test";
          ++$skipct;
      } else {
          my $first_fail = check_for_fails("$test");
          if ($first_fail) {
              $result{$test} = "failed";
              $fail_lines{$test} = $first_fail;
              push @failures, "$suite/$test";
              ++$failct;
          }
      }
   }

   # need counts before we can write this
   print STDOUT "  <testsuite name=\"$suite\" tests=\"$testct\" skipped=\"$skipct\" failures=\"$failct\">\n";
   foreach $test (@{$suites{$suite}}) {
     if ($result{$test} eq "ignored" or exists $xfail{"$suite/$test"}) {
       print STDOUT "    <testcase name=\"$test\">\n";
       print STDOUT "      <skipped />\n";
       print STDOUT "    </testcase>\n";
     } elsif ($result{$test} eq "passed") {
       print STDOUT "    <testcase name=\"$test\" />\n";
     } else {
       print STDOUT "    <testcase name=\"$test\">\n";
       print STDOUT "      <failure>\n";
       if (($result{$test} eq "failed") && (exists $fail_lines{$test})) {
         print STDOUT "NEW FAILURE\n";
         print STDOUT xmlEscape($fail_lines{$test});
       } elsif ($result{$test} eq "failed") {
         print STDOUT "NEW FAILURE\n";
         if ((-e "$benchdir/$test.out") && (-e "$outdir/$test.out")) {
           print STDOUT xmlEscape(`sh $chmdiff -w $benchdir/$test.out $outdir/$test.out | head -n20`);
         } else {
           print STDOUT "MISSING TEST\n";
         }
       } elsif ($result{$test} eq "crashed") {
         print STDOUT "NEW CRASH\n";
         if (-e "$outdir/$test.err") {
           print STDOUT xmlEscape(`cat $outdir/$test.err`);
         }
         if (-e "$outdir/$test.core") {
           if (-e "../exec") {
             print STDOUT xmlEscape(`TERM=tty gdb --batch -ex bt ../exec/*/charmm $outdir/$test.core 2>/dev/null`);
           } elsif (-e "../bin") {
             print STDOUT xmlEscape(`TERM=tty gdb --batch -ex bt ../bin/charmm $outdir/$test.core 2>/dev/null`);
           }
         }
       } else {
         print STDOUT "UNKNOWN FAILURE\n";
       }
       print STDOUT "      </failure>\n";
       print STDOUT "    </testcase>\n";
     }
   }
   print STDOUT "  </testsuite>\n";
   $tot_testct += $testct;
 }
print STDOUT "</testsuites>\n";

if ($tot_testct == 0) {
   print STDERR "NO TESTS RUN\n";
   exit 2;
}

if (%xfail) {
   my @newfails = ();
   foreach $test (@failures) {
      if (not exists $xfail{$test}) {
         push @newfails, $test;
      }
   }
   if (@newfails) {
      print STDERR "NEW TEST FAILURES:\n";
      foreach $test (@newfails) {
         print STDERR "$test\n";
      }
      exit 1;
   }
   else {
      exit 0;
   }
}
elsif (@failures > $maxfail) {
   print STDERR scalar @failures, " TEST FAILURES\n";
   exit 1;
}
else {
   open XFAIL, "> $xfailfile" or die;
   foreach $test (@failures) {
      print XFAIL "$test\n";
   }
   close XFAIL;
   exit 0;
}

sub check_for_fails {
    my ($test_name) = @_;
    open(my $fh, "<", "$outdir/$test_name.out")
        or die "Can't open < $outdir/$test.out: $!";
    while(<$fh>) {
        if (($_ =~ /^test.*?fail/i) || ($_ =~ /^fail/i)) {
            return $_;
        }
    }
    close $fh
        or die "$fh: $!";
    return '';
}
