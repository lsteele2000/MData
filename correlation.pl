
use strict;
use Data::Dumper;
use Getopt::Long;
use JSON;

use constant Sample => 1;
use constant Population => 0;

my $cfgSource = shift || 'Correlation.json';

#my $meanType = Sample;
my $initConfig = {
	meanType => Sample,
	path => "\\Users\\lstee\\Documents\\Interactive Data\\",
	ref => [ 'SPY', '$TNX' ],
	comparee => ['JNPR'],
};
my $config = loadConfig( $cfgSource, $initConfig ) || die "Configuration error\n";

#my $path = $config->{path}; #"\\Users\\lstee\\Documents\\Interactive Data\\";

my @refData;
foreach my $ref ( @{$config->{ref}} )
{
	my $source = bestSource( $ref, $config->{path} );
	die "Could not find ref source for '$ref'\n" unless $source;

	print "$ref loaded from $source\n";
	push @refData, LoadData( "$config->{path}$source", $ref );
}

my @compareData;
foreach my $compare ( @{$config->{comparee}} )
{
	my $source = bestSource( $compare, $config->{path} );
	die "Could not find source for '$compare'\n" unless $source;

	print "$compare loaded from $source\n";
	push @compareData, LoadData( "$config->{path}$source", $compare );
}


my @refValues;
foreach my $data ( @refData )
{
	#print Data::Dumper->Dump( [$data] );
	my %obj;
       	$obj{name} = $data->{name};
	my $series = GetSeries( $data, 'Return' );
	$obj{series} = $series;
	$obj{mean} = mean(  $series );
	$obj{meanDev} = meanDeviation( $series, $obj{mean} );
	$obj{variance} = variance( $obj{meanDev}, $config->{meanType} );
	$obj{stdDev} = $obj{variance} ** .5;
	push @refValues, \%obj;
}
#print Data::Dumper->Dump( [$refValues[0]]);
#exit;

my @compareValues;
foreach my $data ( @compareData )
{
	#print Data::Dumper->Dump( [$data] );
	my %obj;
       	$obj{name} = $data->{name};
	my $series = GetSeries( $data, 'Return' );
	$obj{series} = $series;
	$obj{mean} = mean(  $series );
	$obj{meanDev} = meanDeviation( $series, $obj{mean} );
	$obj{variance} = variance( $obj{meanDev}, $config->{meanType} );
	$obj{stdDev} = $obj{variance} ** .5;
	push @compareValues, \%obj;
	#print "spy Variance $spyVariance, $spyStdDev\n";
	#print sprintf( "Spy Mean: %0.4f, Tnx Mean: %0.4f\n" , $spyMean , $tnxMean );
	#print "Mad1: ",join( ',', @$spyMad ),"\n";
}

foreach my $compV ( @compareValues )
{
	foreach my $refV (@refValues)
	{
		print "\n";
		print $compV->{name}," -- ", $refV->{name},"\n";
		die "Unequal data set sizes\n" unless scalar @{$refV->{series}} == scalar @{$compV->{series}};
		my $covar = covariance( $refV->{series}, $compV->{series}, $config->{meanType} );
		print "covar $covar\n";
		#my $testcovar = covariance( $refV->{series}, $refV->{series}, $config->{meanType} );
		#print "test $testcovar, $refV->{variance}\n";
		my $pearsonCorrelation = pearsonCorrelation( $covar, $refV->{stdDev}, $compV->{stdDev} );
		print "Pearson correlation $pearsonCorrelation\n";
		my $rSqd = $pearsonCorrelation ** 2;
		print "RSqd $rSqd\n";
	}
}




sub pearsonCorrelation {
	my ($covar, $std1, $std2) = @_;
	#printf "$covar, $std1, $std2\n";
	return $covar / ($std1*$std2);
}

sub variance {
my ($s, $asSample ) = @_;
	my $tot = 0;
	foreach my $next ( @$s )
	{
		$tot += $next**2;
		#print "$next, ", $next**2, " ,$tot\n";
	}
	my $cnt = @$s;
	--$cnt if $asSample;
	#print "$tot, $cnt\n";
	return $tot/$cnt;
}

sub covariance {
my ($s1, $s2, $asSample ) = @_;
	my $summed = 0;
	foreach my $index ( 1 .. scalar(@$s1) )
	{
		$summed += $s1->[$index-1] * $s2->[$index-1];
	}
	#print "covar sum $summed\n";
	my $cnt = @$s1;
	--$cnt if $asSample;
	return $summed/$cnt;
}

sub meanDeviation {
my ( $s, $mean ) = @_;
	$mean = mean($s) unless defined $mean;
	my @result = map { $_ - $mean } @$s;
	\@result;
}

sub mean {
my ($s) = @_;
	my $tot = 0;
	foreach my $next (@$s)
	{
		$tot += $next;
	}
	return $tot/scalar(@$s);

}

sub LoadData {
my ( $source, $name ) = @_;
	die "Source '$source' not found\n" unless -f $source;
	open IN, $source;

	my @series;
	my %headerIndex;
	my $hdr = <IN>;
	chomp $hdr;
	$hdr =~ s/\s//g;
	my @fields = split ',',$hdr;
	foreach my $index ( 0 .. scalar(@fields)-1 )
	{
		$headerIndex{$fields[$index]} = $index;
	}

	my $seriesContext = {
		'name'	=> $name,
		'source' => $source, 
		'header' => \%headerIndex, 
		'series' =>  \@series 
		};


	my $truncated = 0;
	while ( <IN> )
	{
		chomp;
		my @vals = split ',';
		push @series, \@vals;
		#last if ++$truncated > 10;
	}
	close IN;

	SetReturn( $seriesContext );
	NormalizeDate( $seriesContext );
	return $seriesContext;

}

sub SetReturn {
my ( $data ) = @_;

	my $hdr = $data->{header};
	die "Header not found\n" unless $hdr;
	return if $hdr->{Return};

	die "Close field not found\n" unless defined $hdr->{Close};
	my $closeIndex = $hdr->{Close};

	my $series = $data->{series};
	my $size = scalar( @{$series->[0]} );
	$hdr->{Return} = $size;

	my $enteries = scalar( @$series );
	foreach my $index ( 0 .. $enteries-2 )
	{
		my $curEntry = $series->[$index];
		my $nextEntry = $series->[$index+1];
		my $close = $curEntry->[$closeIndex];
		my $prev = $nextEntry->[$closeIndex];
		my $chg = $close-$prev;
		my $return = $chg/$prev;
		push @$curEntry,$return;
	}	
}

sub NormalizeDate {
my ( $data ) = @_;
	my $hdr = $data->{header};
	die "Header not found\n" unless $hdr;
	return if $hdr->{NormDate};
	die "Date field not found\n" unless defined $hdr->{Date};
	my $dateIndx = $hdr->{Date};

	my $series = $data->{series};
	my $size = scalar( @{$series->[0]} );
	$hdr->{NormDate} = $size;
	foreach my $entry ( @$series )
	{
		my $date = $entry->[$dateIndx];
		my @components = split '\/', $date;
		my $normDate = $components[2] . $components[0] . $components[1];
		push @$entry,$normDate;
	}	
}

sub GetSeries {
	my ($source, $value ) = @_;
	my @series;
	my $hdr = $source->{header};
	die "Header not found\n" unless $hdr;

	my $dateIndx = $hdr->{Date};
	die "$value field not found\n" unless defined $hdr->{$value};

	my $valIndx = $hdr->{$value};
	my $orig = $source->{series};
	
	foreach my $entry ( @$orig )
	{
		#push @series, [ $entry->[$dateIndx], $entry->[$valIndex] ];
		push @series, $entry->[$valIndx];
	}
	pop @series if $value eq 'Return';
	return \@series;
}

sub bestSource {
my ($issue, $path) = @_;
	opendir my $hdir, $path;
	$issue =~ s/^\$/^\\\$/;
	my @choices = sort grep { /^$issue .*\.csv$/ } readdir $hdir;
	closedir $hdir;
	#print join( "\n", @choices);
	return wantarray() ? \@choices : $choices[-1];
}

sub loadConfig {
	my ($cfg, $defaults) = @_;
	open IN, $cfg;
	my @val = <IN>;
	my $val = join "", @val;
	#print Data::Dumper->Dump( [$val] );
	my $loaded = decode_json( $val );
	#print Data::Dumper->Dump( [$loaded] );
	my %result = (%$defaults, %$loaded);
	#print Data::Dumper->Dump( [%result] );

	return \%result;
}
