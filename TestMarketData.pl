
use strict;

use lib '.';
use Data::Dumper;
use JSON;
use MarketData;

use constant Sample => 1;
use constant Population => 0;

my $cfgSource = shift || 'Correlation.json';

my $initConfig = {
	meanType => Sample,
	path => "\\Users\\lstee\\Documents\\Interactive Data\\",
	ref => [ 'SPY', '$TNX' ],
	comparee => ['JNPR'],
};
my $config = loadConfig( $cfgSource, $initConfig ) || die "Configuration error\n";

my @refData;
foreach my $ref ( @{$config->{ref}} )
{
	my $next = MarketData->new( 'symbol' => $ref );
	$next->loadData();
	push @refData, $next;
}

#print Data::Dumper->Dump( [@refData] );

my @compareData;
foreach my $compare ( @{$config->{comparee}} )
{
	my $next = MarketData->new( 'symbol' => $compare );
	$next->loadData();
	push @compareData, $next;
}


my @refValues;
foreach my $md ( @refData )
{
	#print Data::Dumper->Dump( [$data] );
	my %obj;
       	$obj{name} = $md->symbol();
	my $series = $md->getSeries( 'Return' );
	$obj{series} = $series;
	$obj{mean} = $md->mean(  $series );
	$obj{meanDev} = $md->meanDeviation( $series, $obj{mean} );
	$obj{variance} = variance( $obj{meanDev}, $config->{meanType} );
	$obj{stdDev} = $obj{variance} ** .5;
	push @refValues, \%obj;
	#	print Data::Dumper->Dump( [%obj] );
}

my @compareValues;
foreach my $md ( @compareData )
{
	print $md->{name},"\n";
	#print Data::Dumper->Dump( [$data] );
	my %obj;
       	$obj{name} = $md->{name};
	my $series = $md->getSeries( 'Return' );
	$obj{series} = $series;
	$obj{mean} = $md->mean(  $series );
	$obj{meanDev} = $md->meanDeviation( $series, $obj{mean} );

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

exit;

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
__END__



