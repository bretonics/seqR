#!/usr/bin/env perl

use strict; use warnings; use diagnostics; use feature qw(say);
use Getopt::Long; use Pod::Usage;

use File::Spec;

use MyConfig;

# =============================================================================
#   -------
#   | SeqR
#   -------
#   CAPITAN:        Andres Breton, http://andresbreton.com
#   USAGE:          Automated Sequence Analysis Workflow
#   DEPENDENCIES:   - Own 'Modules' repo
#
# =============================================================================


#-------------------------------------------------------------------------------
# COMMAND LINE
my $NAME;
my $REFERENCE;
my $INDEX;
my $READS1;
my $READS2;
my $usage = "\n\n$0 [options]\n
Options:
    -name           Sequence/Strain name
    -ref            Reference sequence file
    -index          Reference index name for bowtie2
    -r1             Illumina paired-end sequence reads 1
    -r2             Illumina paired-end sequence reads 2
    -help           Show this message
\n";

# OPTIONS
GetOptions(
    'name=s'        =>\$NAME,
    'ref=s'         =>\$REFERENCE,
    'index=s'       =>\$INDEX,
    'r1=s'          =>\$READS1,
    'r2=s'          =>\$READS2,
    help            =>sub{pod2usage($usage);}
)or pod2usage(2);
#-------------------------------------------------------------------------------
# CHECKS
checks(); # check CL arguments were passed

# Tools to run analysis
my %tools = (
    'bowtie2'       => {
                        version     => 'bowtie2 --version',
                        regX        => qr/version \s+(\d+\.\d+)$/,
                        version     => '2.2.6',
                        req         => 1,
                        },
    'samtools'      => {
                        version     => 'samtools',
                        regX        => qr/Version:\s+(\d+\.\d+)/,
                        version     => '1.3.1',
                        req         => 1,
                        },
    'nucmer'        => {
                        version     => 'nucmer --version',
                        regX        => qr/version:\s+(\d+\.\d+)$/,
                        version     => '3.1',
                        req         => 1,
                        },
    'nucmer'        => {
                        version     => 'mummerplot --version',
                        regX        => qr/version:\s+(\d+\.\d+)$/,
                        version     => '3.5',
                        req         => 1,
                        },
    'seqtk'         => {
                        version     => 'seqtk',
                        regX        => qr/Version:\s+(\d+\.\d+)/,
                        version     => '1.2',
                        req         => 1,
                        },
    'blastp'        => {
                        version     => 'blastp -version',
                        regX        => qr/blastp:\s+(\d+\.\d+)/,
                        version     => '2.2',
                        req         => 0,
                        },
    'makeblastdb'   => {
                        version     => 'makeblastdb -version',
                        regX        => qr/makeblastdb:\s+(\d+\.\d+)/,
                        version     => '2.2',
                        req         => 0,  # only if --proteins used
                        },
    # Standard UNIX utilities
    'less'          => { req => 1 },
    'grep'          => { req => 1 },  # yes, we need this before we can test versions :-/
    'egrep'         => { req => 1 },
    'sed'           => { req => 1 },
    'find'          => { req => 1 },
);

checkTools()

#-------------------------------------------------------------------------------
# VARIABLES

# Get/Set relative->aboslute paths for files
$REFERENCE      = File::Spec->rel2abs($REFERENCE);
$READS1         = File::Spec->rel2abs($READS1);
$READS2         = File::Spec->rel2abs($READS2);

my $outDir      = setOutputDir("analysis/$NAME"); # create analysis directory
my $commands    = getCommands($NAME, $REFERENCE, $INDEX, $READS1, $READS2);
#-------------------------------------------------------------------------------
# CALLS
executeCommand("bowtie2-build", $commands); # bowtie2-build
executeCommand("bowtie2",       $commands); # bowtie2
executeCommand("samtools",      $commands, "view" ); # samtools view
executeCommand("samtools",      $commands, "sort");  # samtools sort
executeCommand("samtools",      $commands, "index"); # samtools index
# samtools 'tview' commented b/c you don't want to interupt your analysis
# with a screen...execute command above once done to see alignment
#executeCommand("samtools", 		$commands, "tview"); # samtools tview
executeCommand("samtools",      $commands, "consensus"); # samtools consensus
executeCommand("seqtk",         $commands); # seqtk
executeCommand("nucmer",        $commands); # nucmer
executeCommand("show-coords",   $commands); # show-coords
executeCommand("mummerplot",    $commands); # mummerplot
executeCommand("samtools",      $commands, "variants"); # samtools variants
#-------------------------------------------------------------------------------
# SUBS
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $input = checks();
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# This function checks command-line arguments using global variables
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $output = Dies from errors
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub checks {
    unless ($NAME) {
        die "Did not provide a sequence/strain name", $usage, $!;
    }
    unless ($REFERENCE) {
        die "Did not provide a reference sequence file", $usage, $!;
    }
    unless ($INDEX) {
        die "Did not provide an index name for bowtie2", $usage, $1
    }
    unless ($READS1 || $READS2) {
        die "Did not provide sequence paired-reads", $usage, $!;
    }

    return;
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $input = ($name, $reference, $index, $reads1, $reads2);
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# This function takes two (5) arguments, the SRA and accession. Creates an
# anonymous hash with commands as keys, values as command to execute, returning
# a reference to the hash of software. This simplifies both visual and future
# modifications you'd like to make for each command. One place, one change.
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $return = ($commands);
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub getCommands {
    my $filledUsage = 'Usage: ' . (caller(0))[3] . '($name, $reference, $index, $reads1, $reads2)';
    @_ == 5 or die wrongNumberArguments(), $filledUsage;

    my ($name, $reference, $index, $reads1, $reads2) = @_;

    my $commands = {
        "bowtie2-build"     => "bowtie2-build -o 3 $reference $index",
        "bowtie2"           => "bowtie2 -x $index -1 $reads1 -2 $reads2 -S $name.sam",
        # Hash of hashes for samtools since it has multipe option calls
        "samtools"          => {
                                view        => "samtools view -b $name.sam > $name.bam",
                                sort        => "samtools sort $name.bam -o $name.sorted.bam",
                                index       => "samtools index $name.sorted.bam",
                                tview       => "samtools tview $name.sorted.bam",
                                consensus   => "samtools mpileup -uf $reference $name.sorted.bam | bcftools call -c | vcfutils.pl vcf2fq > consensus.fastq",
                                variants    => "samtools mpileup -uf $reference $name.sorted.bam | bcftools call -mv -Oz > variants.vcf.gz",
                                },
        "seqtk"             => "seqtk seq -A consensus.fastq > consensus.fasta",
        "nucmer"            => "nucmer -maxmatch -c 100 -p nucmer $reference consensus.fasta",
        "show-coords"       => "show-coords -r -c -l nucmer.delta > nucmer.coords",
        "mummerplot"        => "mummerplot --png --color -p nucmer nucmer.delta",
    };
    return ($commands);
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $input = executeCommand($call, $commands, $option);
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# This function takes arguments 2 or 3 arguments; the call to the program to be
# executed, the hash of commands, and an optional 'option' for commands requiring
# a second flag (such as samtools).
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $output = Executes command and reports status
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub executeCommand {
    my $filledUsage = 'Usage: ' . (caller(0))[3] . '($call, $command, $option)';
    @_ == 2 or @_ == 3 or die wrongNumberArguments(), $filledUsage;

    my ($call, $command, $option) = @_;
    my $exec;

    if ($option) {
        $exec = $commands->{$call}{$option};
    } else {
        $exec = $commands->{$call};
    }

    say "Executing $call...\n\t$exec\n";
    my $result = `$exec`;
    # Status code of most recent system call or pipe.
    failedEx($exec) if ($? != 0); # $?  Child error.

    say "Done.\n\n";
    return;
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $input = ($command);
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# This function takes 1 argument, the executed sys call command.
# It prints warnings and dies when command execution fails
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $output = Print warnings and die when command execution fails
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub failedEx {
    my $filledUsage = 'Usage: ' . (caller(0))[3] . '($exec)';
    @_ == 1 or die wrongNumberArguments(), $filledUsage;

    my ($command) = @_;
    die	"WARNING: Something seems to have gone wrong!\n",
    	"Failed to execute '" , $command , "'\n",
    	"Please check installed software version and/or permissions\n\n", $!;
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $input = ($ourDirName)
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# This function takes no arguments, creates an output directory if non-existent
# for results, and moves into it.
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $output = '$ourDirName' output directory
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub setOutputDir {
    my ($outDir) =  @_;
    if (! -e $outDir){
        `mkdir -p $outDir`;
    }
    say "Changing to $outDir directory...\n";
    chdir($outDir) or die "$!";
    return $outDir;
}
