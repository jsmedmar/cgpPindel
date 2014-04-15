#!/usr/bin/perl

BEGIN {
  use Cwd qw(abs_path);
  use File::Basename;
  push (@INC,dirname(abs_path($0)).'/../lib');
};

use strict;
use warnings FATAL => 'all';
use autodie qw(:all);

use File::Path qw(remove_tree make_path);
use Getopt::Long;
use File::Spec;
use Pod::Usage qw(pod2usage);
use List::Util qw(first);
use Const::Fast qw(const);

use PCAP::Cli;
use Sanger::CGP::Pindel::Implement;

const my @VALID_PROCESS => qw(input pindel pin2vcf flag annot);
my %index_max = ( 'input'   => 2,
                  'split'   => 0,
                  'filter'  => 0,
                  'pindel'  => 0,
                  'pin2vcf' => 0,
                  'flag'    => 0,
                  'annot'   => 0,);

{
  my $options = setup();
  Sanger::CGP::Pindel::Implement::prepare($options);

  my $threads = PCAP::Threaded->new($options->{'threads'});

  # register any process that can run in parallel here
  $threads->add_function('input', \&Sanger::CGP::Pindel::Implement::input);
  $threads->add_function('split', \&Sanger::CGP::Pindel::Implement::split);
  $threads->add_function('filter', \&Sanger::CGP::Pindel::Implement::filter);
  $threads->add_function('pindel', \&Sanger::CGP::Pindel::Implement::pindel);

  # start processes here (in correct order obviously), add conditions for skipping based on 'process' option
  $threads->run(2, 'input', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'input');

  # count the valid input files, gives constant job count for downstream
  my $jobs = Sanger::CGP::Pindel::Implement::determine_jobs($options);

  $threads->run($jobs, 'split', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'split');
  $threads->run($jobs, 'filter', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'filter');
  $threads->run($jobs, 'pindel', $options) if(!exists $options->{'process'} || $options->{'process'} eq 'pindel');


}


sub setup {
  my %opts;
  GetOptions( 'h|help' => \$opts{'h'},
              'm|man' => \$opts{'m'},
              'c|cpus=i' => \$opts{'threads'},
              'r|reference=s' => \$opts{'reference'},
              'o|outdir=s' => \$opts{'outdir'},
              't|tumour=s' => \$opts{'tumour'},
              'n|normal=s' => \$opts{'normal'},
              'e|exclude=s' => \$opts{'exclude'},
              'p|process=s' => \$opts{'process'},
              'i|index=i' => \$opts{'index'},
  ) or pod2usage(2);

  pod2usage(-message => PCAP::license, -verbose => 1) if(defined $opts{'h'});
  pod2usage(-message => PCAP::license, -verbose => 2) if(defined $opts{'m'});

  # then check for no args:
  my $defined;
  for(keys %opts) { $defined++ if(defined $opts{$_}); }
  pod2usage(-msg  => "\nERROR: Options must be defined.\n", -verbose => 1,  -output => \*STDERR) unless($defined);

  PCAP::Cli::file_for_reading('reference', $opts{'reference'});
  PCAP::Cli::file_for_reading('tumour', $opts{'tumour'});
  PCAP::Cli::file_for_reading('normal', $opts{'normal'});
  PCAP::Cli::out_dir_check('outdir', $opts{'outdir'});

  delete $opts{'process'} unless(defined $opts{'process'});
  delete $opts{'index'} unless(defined $opts{'index'});
  delete $opts{'exclude'} unless(defined $opts{'exclude'});

  if(exists $opts{'process'}) {
    PCAP::Cli::valid_process('process', $opts{'process'}, \@VALID_PROCESS);
    if(exists $opts{'index'}) {
die "info from fai file and '-e' needed to do this";
      PCAP::Cli::opt_requires_opts('index', \%opts, ['process']);
die "No max has been defined for this process type\n" if($index_max{$opts{'process'}} == 0);
      PCAP::Cli::valid_index_by_factor('index', $opts{'index'}, $index_max{$opts{'process'}}, 1);
    }
  }
  elsif(exists $opts{'index'}) {
    die "ERROR: -index cannot be defined without -process\n";
  }

  # now safe to apply defaults
  $opts{'threads'} = 1 unless(defined $opts{'threads'});

  my $tmpdir = File::Spec->catdir($opts{'outdir'}, 'tmpPindel');
  make_path($tmpdir) unless(-d $tmpdir);
  my $progress = File::Spec->catdir($tmpdir, 'progress');
  make_path($progress) unless(-d $progress);
  my $logs = File::Spec->catdir($tmpdir, 'logs');
  make_path($logs) unless(-d $logs);

  $opts{'tmp'} = $tmpdir;

  return \%opts;
}

__END__

=head1 pindel.pl

Reference implementation of Cancer Genome Project indel calling
pipeline.

=head1 SYNOPSIS

pindel.pl [options]

  Required parameters:
    -outdir    -o   Folder to output result to.
    -reference -r   Path to reference genome file *.fa[.gz]
    -tumour    -t   Tumour BAM file
    -normal    -n   Normal BAM file

  Optional
    -exclude   -e   Exclude this list of ref sequences from processing
                     - comma separated, e.g. NC_007605,hs37d5
    -cpus      -c   Number of cores to use. [1]
                     - recommend 4 if possible

  Targeted processing:
    -process   -p   Only process this step then exit, optionally set -index
                      bwamem - only applicable if input is bam
                        mark - Run duplicate marking (-index N/A)

    -index     -i   Optionally restrict '-p' to single job
                      bwamem - 1..<lane_count>

  Other:
    -help      -h   Brief help message.
    -man       -m   Full documentation.

  File list can be full file names or wildcard, e.g.
    pindel.pl -c 4 -r some/genome.fa[.gz] -o myout -t tumour.bam -n normal.bam

  Run with '-m' for possible input file types.

=head1 OPTIONS

=over 8

=item B<-outdir>

=back