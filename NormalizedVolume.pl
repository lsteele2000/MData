
use strict;

use lib '.';
use Data::Dumper;
use MarketData;

my $cfgSource = shift || 'NormalizedVolume.json';
my $initConfig = {
	path => "\\Users\\lstee\\Documents\\Interactive Data\\",
	issues => ['JNPR'],
	maType => 'sma',		# pending implementation
	maWindow => 14,			# moving average window size
	normWindow => 20,		# lookback window for ma mean
};
my $config = MarketData::loadConfig( $cfgSource, $initConfig ) || die "Configuration error\n";
print Data::Dumper->Dump( [$config] );

my @issues;
my $mvAvgWindow = 14;
foreach my $sym ( @{$config->{issues}} )
{
	my %obj; 
	$obj{marketData} = my $md = MarketData->new( 'symbol' => $sym );
	$md->loadData();
	$obj{volSeries} = $md->getSeries(  "Vol" );
	$obj{volMoveAvg} = $md->movingAverage( $mvAvgWindow, $obj{volSeries}, 'decimals' => 0 ); # , 'count' => 40, 'verbose' => 1 ); 
	push @issues, \%obj;
}
my $md = $issues[0]->{marketData};
my $vol = $issues[0]->{volSeries};
my $volMoveAvg = $issues[0]->{volMoveAvg};
print ref($volMoveAvg),"\n";
my $mean = MarketData::mean( $volMoveAvg, 'back_window' => 90, 'verbose' => 0, 'ignore_leadingnulls' => 1 );
#print join( "\n", @$volMoveAvg), "\n";
#print "mean: $mean\n";
#print "Vol,VolMa\n";
my $maLabel = sprintf( "MoveAvg(%d)", $mvAvgWindow);
MarketData::outputDelimited( "test.csv", [ "Volume", $maLabel ], [ $vol, $volMoveAvg ] , "stdout" => 1 );
exit;
foreach my $index ( 0 .. $#$vol )
{
	print $vol->[$index], ",", $volMoveAvg->[$index], "\n"; 
}

__END__



